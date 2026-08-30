/**************************************
 Japan: JP_PATIENT -> PERSON
 POLICY: LOAD - see DOMAIN_ETL_POLICY.md (person)

 Relational JMDC policy:
 - JP_CLAIMS is the authoritative cohort/visit spine.
 - Load only members that occur in JP_CLAIMS.
 - Use JP_PATIENT only for member attributes.

 This avoids scanning and sorting all diagnosis, drug, and procedure rows merely
 to rediscover members already represented by their claims.
**************************************/

WITH canon AS (
    SELECT
        COALESCE(
            CONVERT(VARCHAR(50), TRY_CAST(
                NULLIF(LTRIM(RTRIM(CAST(c.member_id AS VARCHAR(100)))), '')
                AS DECIMAL(38, 0)
            )),
            NULLIF(LTRIM(RTRIM(CAST(c.member_id AS VARCHAR(100)))), '')
        ) AS member_id_str
    FROM @raw_database.JP_CLAIMS c
    GROUP BY
        COALESCE(
            CONVERT(VARCHAR(50), TRY_CAST(
                NULLIF(LTRIM(RTRIM(CAST(c.member_id AS VARCHAR(100)))), '')
                AS DECIMAL(38, 0)
            )),
            NULLIF(LTRIM(RTRIM(CAST(c.member_id AS VARCHAR(100)))), '')
        )
),
pt AS (
    SELECT
        COALESCE(
            CONVERT(VARCHAR(50), TRY_CAST(
                NULLIF(LTRIM(RTRIM(CAST(p.member_id AS VARCHAR(100)))), '')
                AS DECIMAL(38, 0)
            )),
            NULLIF(LTRIM(RTRIM(CAST(p.member_id AS VARCHAR(100)))), '')
        ) AS member_id_str,
        MAX(p.gender_of_member) AS gender_of_member,
        MAX(p.month_and_year_of_birth_of_memb) AS month_and_year_of_birth_of_memb
    FROM @raw_database.JP_PATIENT p
    GROUP BY
        COALESCE(
            CONVERT(VARCHAR(50), TRY_CAST(
                NULLIF(LTRIM(RTRIM(CAST(p.member_id AS VARCHAR(100)))), '')
                AS DECIMAL(38, 0)
            )),
            NULLIF(LTRIM(RTRIM(CAST(p.member_id AS VARCHAR(100)))), '')
        )
)
INSERT INTO @cdm_database.person (
    person_id, gender_concept_id, year_of_birth, month_of_birth, day_of_birth,
    birth_datetime, race_concept_id, ethnicity_concept_id, location_id, provider_id,
    care_site_id, person_source_value, gender_source_value, gender_source_concept_id,
    race_source_value, race_source_concept_id, ethnicity_source_value,
    ethnicity_source_concept_id
)
SELECT
    (SELECT ISNULL(MAX(person_id), 0) FROM @cdm_database.person)
        + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS person_id,
    CASE
        WHEN pt.gender_of_member IN ('1', 'M', 'Male', 'male') THEN 8507
        WHEN pt.gender_of_member IN ('2', 'F', 'Female', 'female') THEN 8532
        ELSE 0
    END AS gender_concept_id,
    CASE
        WHEN LEN(RTRIM(pt.month_and_year_of_birth_of_memb)) >= 4
        THEN TRY_CAST(SUBSTRING(RTRIM(pt.month_and_year_of_birth_of_memb), 1, 4) AS INT)
        ELSE 1950
    END AS year_of_birth,
    CASE
        WHEN LEN(RTRIM(pt.month_and_year_of_birth_of_memb)) >= 6
        THEN TRY_CAST(SUBSTRING(RTRIM(pt.month_and_year_of_birth_of_memb), 5, 2) AS INT)
        ELSE NULL
    END AS month_of_birth,
    NULL AS day_of_birth,
    NULL AS birth_datetime,
    38003585 AS race_concept_id,
    38003564 AS ethnicity_concept_id,
    NULL AS location_id,
    NULL AS provider_id,
    NULL AS care_site_id,
    c.member_id_str AS person_source_value,
    pt.gender_of_member AS gender_source_value,
    NULL AS gender_source_concept_id,
    NULL AS race_source_value,
    NULL AS race_source_concept_id,
    NULL AS ethnicity_source_value,
    NULL AS ethnicity_source_concept_id
FROM canon c
LEFT JOIN pt
  ON pt.member_id_str = c.member_id_str
WHERE c.member_id_str IS NOT NULL
  AND c.member_id_str <> ''
  AND NOT EXISTS (
      SELECT 1
      FROM @cdm_database.person pp
      WHERE pp.person_source_value = c.member_id_str
  );

SELECT CAST('person' AS VARCHAR(50)) AS _etl_table,
       @@ROWCOUNT AS _etl_inserted_rows;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.person')
      AND name = N'UX_jmdc_person_source_value'
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_jmdc_person_source_value
        ON @cdm_database.person (person_source_value)
        WHERE person_source_value IS NOT NULL;
END;
