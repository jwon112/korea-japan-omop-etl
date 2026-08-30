/*******************************************************************************
Create one OMOP PERSON row per NHIS-NSC enrollee.

NHID_JK stores one row per person and eligibility year. AGE_GROUP is a
five-year band. The former ETL divided people into eight branches and scanned
NHID_JK repeatedly inside nested anti-joins. The branches reduce to the same
two birth-year rules used below:

1. If AGE_GROUP 0 exists, use its earliest year.
2. Otherwise use the earliest candidate derived from
   STND_Y - ((AGE_GROUP - 1) * 5).

The latest eligibility year supplies sex and location. MAX resolves an
unexpected duplicate person/year deterministically; normal NHID_JK data has
one row per person/year.
*******************************************************************************/

SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#person_rollup') IS NOT NULL
    DROP TABLE #person_rollup;

;WITH normalized AS (
    SELECT
        TRY_CONVERT(INT, person_id) AS person_id,
        TRY_CONVERT(INT, stnd_y) AS stnd_y,
        TRY_CONVERT(INT, age_group) AS age_group
    FROM @NHISNSC_rawdata.@NHIS_JK
)
SELECT
    person_id,
    COALESCE(
        MIN(CASE WHEN age_group = 0 THEN stnd_y END),
        MIN(CASE
                WHEN age_group > 0
                THEN stnd_y - ((age_group - 1) * 5)
            END)
    ) AS year_of_birth,
    MAX(stnd_y) AS latest_year
INTO #person_rollup
FROM normalized
WHERE person_id IS NOT NULL
  AND stnd_y BETWEEN 1900 AND 2100
  AND age_group >= 0
GROUP BY person_id
HAVING COALESCE(
           MIN(CASE WHEN age_group = 0 THEN stnd_y END),
           MIN(CASE
                   WHEN age_group > 0
                   THEN stnd_y - ((age_group - 1) * 5)
               END)
       ) BETWEEN 1800 AND 2100
OPTION (MAXDOP 4, RECOMPILE);

CREATE UNIQUE CLUSTERED INDEX IX_person_rollup_person
    ON #person_rollup (person_id);
GO

;WITH latest_attributes AS (
    SELECT
        r.person_id,
        r.year_of_birth,
        MAX(TRY_CONVERT(INT, j.sex)) AS sex,
        MAX(TRY_CONVERT(INT, j.sgg)) AS sgg
    FROM #person_rollup r
    JOIN @NHISNSC_rawdata.@NHIS_JK j
      ON TRY_CONVERT(INT, j.person_id) = r.person_id
     AND TRY_CONVERT(INT, j.stnd_y) = r.latest_year
    GROUP BY
        r.person_id,
        r.year_of_birth
)
INSERT INTO @NHISNSC_database.PERSON (
    person_id,
    gender_concept_id,
    year_of_birth,
    month_of_birth,
    day_of_birth,
    birth_datetime,
    race_concept_id,
    ethnicity_concept_id,
    location_id,
    provider_id,
    care_site_id,
    person_source_value,
    gender_source_value,
    gender_source_concept_id,
    race_source_value,
    race_source_concept_id,
    ethnicity_source_value,
    ethnicity_source_concept_id
)
SELECT
    person_id,
    CASE sex
        WHEN 1 THEN 8507
        WHEN 2 THEN 8532
        ELSE 0
    END AS gender_concept_id,
    year_of_birth,
    NULL AS month_of_birth,
    NULL AS day_of_birth,
    NULL AS birth_datetime,
    38003585 AS race_concept_id,
    38003564 AS ethnicity_concept_id,
    sgg AS location_id,
    NULL AS provider_id,
    NULL AS care_site_id,
    CONVERT(VARCHAR(50), person_id) AS person_source_value,
    CONVERT(VARCHAR(50), sex) AS gender_source_value,
    NULL AS gender_source_concept_id,
    NULL AS race_source_value,
    NULL AS race_source_concept_id,
    NULL AS ethnicity_source_value,
    NULL AS ethnicity_source_concept_id
FROM latest_attributes
OPTION (MAXDOP 4, RECOMPILE);

IF EXISTS (
    SELECT 1
    FROM @NHISNSC_database.PERSON
    WHERE person_id IS NULL
       OR year_of_birth IS NULL
       OR gender_concept_id IS NULL
)
    THROW 51000, 'PERSON contains a null required field.', 1;

IF (
    SELECT COUNT_BIG(*)
    FROM @NHISNSC_database.PERSON
) <> (
    SELECT COUNT_BIG(*)
    FROM #person_rollup
)
    THROW 51000, 'PERSON row count differs from the eligible person rollup.', 1;

DROP TABLE #person_rollup;
GO
