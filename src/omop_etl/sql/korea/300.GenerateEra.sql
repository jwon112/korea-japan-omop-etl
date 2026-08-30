/**************************************
 Korea NHIS-NSC: drug_era and condition_era

 Merge mapped clinical intervals separated by no more than 30 days. Running
 maximum end dates handle nested and overlapping intervals without the
 quadratic self-joins used by the legacy OHDSI conversion script.
***************************************/

IF OBJECT_ID('tempdb..#drug_interval', 'U') IS NOT NULL
    DROP TABLE #drug_interval;

SELECT
    d.drug_exposure_id,
    d.person_id,
    ingredient.concept_id AS ingredient_concept_id,
    d.drug_exposure_start_date AS start_date,
    COALESCE(
        d.drug_exposure_end_date,
        DATEADD(DAY, NULLIF(d.days_supply, 0) - 1,
                d.drug_exposure_start_date),
        d.drug_exposure_start_date
    ) AS end_date
INTO #drug_interval
FROM @NHISNSC_database.DRUG_EXPOSURE d
JOIN @Mapping_database.CONCEPT_ANCESTOR ca
  ON ca.descendant_concept_id = d.drug_concept_id
JOIN @Mapping_database.CONCEPT ingredient
  ON ingredient.concept_id = ca.ancestor_concept_id
 AND ingredient.vocabulary_id IN ('RxNorm', 'RxNorm Extension')
 AND ingredient.concept_class_id = 'Ingredient'
 AND ingredient.standard_concept = 'S'
 AND ingredient.invalid_reason IS NULL
WHERE d.drug_concept_id > 0;

CREATE CLUSTERED INDEX IX_drug_interval_merge
    ON #drug_interval
       (person_id, ingredient_concept_id, start_date, end_date,
        drug_exposure_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = OFF);
GO

;WITH prior_end AS (
    SELECT
        i.*,
        MAX(i.end_date) OVER (
            PARTITION BY i.person_id, i.ingredient_concept_id
            ORDER BY i.start_date, i.end_date, i.drug_exposure_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS previous_max_end
    FROM #drug_interval i
), boundaries AS (
    SELECT
        p.*,
        CASE
            WHEN p.previous_max_end IS NULL
              OR p.start_date > DATEADD(DAY, 30, p.previous_max_end)
                THEN 1
            ELSE 0
        END AS starts_new_era
    FROM prior_end p
), islands AS (
    SELECT
        b.*,
        SUM(CONVERT(BIGINT, b.starts_new_era)) OVER (
            PARTITION BY b.person_id, b.ingredient_concept_id
            ORDER BY b.start_date, b.end_date, b.drug_exposure_id
            ROWS UNBOUNDED PRECEDING
        ) AS era_number
    FROM boundaries b
), era_rows AS (
    SELECT
        person_id,
        ingredient_concept_id,
        era_number,
        MIN(start_date) AS era_start_date,
        MAX(end_date) AS era_end_date,
        COUNT_BIG(*) AS exposure_count
    FROM islands
    GROUP BY person_id, ingredient_concept_id, era_number
), numbered AS (
    SELECT
        ROW_NUMBER() OVER (
            ORDER BY person_id, ingredient_concept_id,
                     era_start_date, era_end_date
        ) AS era_id,
        *
    FROM era_rows
)
INSERT INTO @NHISNSC_database.DRUG_ERA (
    drug_era_id,
    person_id,
    drug_concept_id,
    drug_era_start_date,
    drug_era_end_date,
    drug_exposure_count,
    gap_days
)
SELECT
    CONVERT(INT, era_id),
    person_id,
    ingredient_concept_id,
    era_start_date,
    era_end_date,
    CONVERT(INT, exposure_count),
    30
FROM numbered
OPTION (RECOMPILE, MAXDOP 2);
GO

DROP TABLE #drug_interval;
GO

IF OBJECT_ID('tempdb..#condition_interval', 'U') IS NOT NULL
    DROP TABLE #condition_interval;

SELECT
    c.condition_occurrence_id,
    c.person_id,
    c.condition_concept_id,
    c.condition_start_date AS start_date,
    COALESCE(c.condition_end_date, c.condition_start_date) AS end_date
INTO #condition_interval
FROM @NHISNSC_database.CONDITION_OCCURRENCE c
WHERE c.condition_concept_id > 0;

CREATE CLUSTERED INDEX IX_condition_interval_merge
    ON #condition_interval
       (person_id, condition_concept_id, start_date, end_date,
        condition_occurrence_id)
    WITH (MAXDOP = 1, SORT_IN_TEMPDB = OFF);
GO

;WITH prior_end AS (
    SELECT
        i.*,
        MAX(i.end_date) OVER (
            PARTITION BY i.person_id, i.condition_concept_id
            ORDER BY i.start_date, i.end_date, i.condition_occurrence_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS previous_max_end
    FROM #condition_interval i
), boundaries AS (
    SELECT
        p.*,
        CASE
            WHEN p.previous_max_end IS NULL
              OR p.start_date > DATEADD(DAY, 30, p.previous_max_end)
                THEN 1
            ELSE 0
        END AS starts_new_era
    FROM prior_end p
), islands AS (
    SELECT
        b.*,
        SUM(CONVERT(BIGINT, b.starts_new_era)) OVER (
            PARTITION BY b.person_id, b.condition_concept_id
            ORDER BY b.start_date, b.end_date, b.condition_occurrence_id
            ROWS UNBOUNDED PRECEDING
        ) AS era_number
    FROM boundaries b
), era_rows AS (
    SELECT
        person_id,
        condition_concept_id,
        era_number,
        MIN(start_date) AS era_start_date,
        MAX(end_date) AS era_end_date,
        COUNT_BIG(*) AS occurrence_count
    FROM islands
    GROUP BY person_id, condition_concept_id, era_number
), numbered AS (
    SELECT
        ROW_NUMBER() OVER (
            ORDER BY person_id, condition_concept_id,
                     era_start_date, era_end_date
        ) AS era_id,
        *
    FROM era_rows
)
INSERT INTO @NHISNSC_database.CONDITION_ERA (
    condition_era_id,
    person_id,
    condition_concept_id,
    condition_era_start_date,
    condition_era_end_date,
    condition_occurrence_count
)
SELECT
    CONVERT(INT, era_id),
    person_id,
    condition_concept_id,
    era_start_date,
    era_end_date,
    CONVERT(INT, occurrence_count)
FROM numbered
OPTION (RECOMPILE, MAXDOP 2);
GO

DROP TABLE #condition_interval;
GO
