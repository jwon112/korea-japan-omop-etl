/**************************************
 Japan: observation_period
 POLICY: LOAD - see MAPPING_POLICY.md

 JP_PATIENT observation_start/observation_end is the authoritative enrollment
 span for claim-backed persons. Claims months are used only when a claim-backed
 person has no valid patient span.
**************************************/

;WITH patient_base AS (
    SELECT
        CAST(
            COALESCE(
                CONVERT(
                    VARCHAR(50),
                    TRY_CONVERT(
                        DECIMAL(38, 0),
                        NULLIF(
                            LTRIM(RTRIM(CAST(pt.member_id AS VARCHAR(100)))),
                            ''
                        )
                    )
                ),
                NULLIF(
                    LTRIM(RTRIM(CAST(pt.member_id AS VARCHAR(100)))),
                    ''
                )
            )
            AS VARCHAR(50)
        ) AS member_id_str,
        NULLIF(
            LTRIM(RTRIM(CAST(pt.observation_start AS VARCHAR(20)))),
            ''
        ) AS start_str,
        NULLIF(
            LTRIM(RTRIM(CAST(pt.observation_end AS VARCHAR(20)))),
            ''
        ) AS end_str
    FROM @raw_database.JP_PATIENT pt
),
patient_dates AS (
    SELECT
        member_id_str,
        CASE
            WHEN LEN(start_str) >= 8
            THEN TRY_CONVERT(DATE, LEFT(start_str, 8), 112)
            WHEN LEN(start_str) = 6
            THEN TRY_CONVERT(DATE, start_str + '01', 112)
        END AS start_date,
        CASE
            WHEN LEN(end_str) >= 8
            THEN TRY_CONVERT(DATE, LEFT(end_str, 8), 112)
            WHEN LEN(end_str) = 6
            THEN EOMONTH(TRY_CONVERT(DATE, end_str + '01', 112))
        END AS end_date
    FROM patient_base
),
patient_span AS (
    SELECT
        p.person_id,
        MIN(d.start_date) AS start_date,
        MAX(d.end_date) AS end_date
    FROM patient_dates d
    INNER JOIN @cdm_database.person p
      ON p.person_source_value = d.member_id_str
    WHERE d.start_date IS NOT NULL
      AND d.end_date IS NOT NULL
      AND d.end_date >= d.start_date
    GROUP BY p.person_id
)
UPDATE op
SET
    op.observation_period_start_date = s.start_date,
    op.observation_period_end_date = s.end_date,
    op.period_type_concept_id = 44814725
FROM @cdm_database.observation_period op
INNER JOIN patient_span s ON s.person_id = op.person_id
WHERE op.observation_period_start_date <> s.start_date
   OR op.observation_period_end_date <> s.end_date
   OR op.period_type_concept_id <> 44814725;

;WITH patient_base AS (
    SELECT
        CAST(
            COALESCE(
                CONVERT(
                    VARCHAR(50),
                    TRY_CONVERT(
                        DECIMAL(38, 0),
                        NULLIF(
                            LTRIM(RTRIM(CAST(pt.member_id AS VARCHAR(100)))),
                            ''
                        )
                    )
                ),
                NULLIF(
                    LTRIM(RTRIM(CAST(pt.member_id AS VARCHAR(100)))),
                    ''
                )
            )
            AS VARCHAR(50)
        ) AS member_id_str,
        NULLIF(
            LTRIM(RTRIM(CAST(pt.observation_start AS VARCHAR(20)))),
            ''
        ) AS start_str,
        NULLIF(
            LTRIM(RTRIM(CAST(pt.observation_end AS VARCHAR(20)))),
            ''
        ) AS end_str
    FROM @raw_database.JP_PATIENT pt
),
patient_dates AS (
    SELECT
        member_id_str,
        CASE
            WHEN LEN(start_str) >= 8
            THEN TRY_CONVERT(DATE, LEFT(start_str, 8), 112)
            WHEN LEN(start_str) = 6
            THEN TRY_CONVERT(DATE, start_str + '01', 112)
        END AS start_date,
        CASE
            WHEN LEN(end_str) >= 8
            THEN TRY_CONVERT(DATE, LEFT(end_str, 8), 112)
            WHEN LEN(end_str) = 6
            THEN EOMONTH(TRY_CONVERT(DATE, end_str + '01', 112))
        END AS end_date
    FROM patient_base
),
patient_span AS (
    SELECT
        p.person_id,
        MIN(d.start_date) AS start_date,
        MAX(d.end_date) AS end_date
    FROM patient_dates d
    INNER JOIN @cdm_database.person p
      ON p.person_source_value = d.member_id_str
    WHERE d.start_date IS NOT NULL
      AND d.end_date IS NOT NULL
      AND d.end_date >= d.start_date
    GROUP BY p.person_id
)
INSERT INTO @cdm_database.observation_period (
    person_id,
    observation_period_start_date,
    observation_period_end_date,
    period_type_concept_id
)
SELECT
    s.person_id,
    s.start_date,
    s.end_date,
    44814725
FROM patient_span s
WHERE NOT EXISTS (
    SELECT 1
    FROM @cdm_database.observation_period op
    WHERE op.person_id = s.person_id
);

/* Fallback for a claim-backed person with no usable JP_PATIENT span. */
IF EXISTS (
    SELECT TOP (1) 1
    FROM @cdm_database.person p
    LEFT JOIN @cdm_database.observation_period op
      ON op.person_id = p.person_id
    WHERE op.person_id IS NULL
)
BEGIN
    ;WITH claim_month AS (
        SELECT
            CAST(
                COALESCE(
                    CONVERT(
                        VARCHAR(50),
                        TRY_CONVERT(
                            DECIMAL(38, 0),
                            NULLIF(
                                LTRIM(RTRIM(CAST(
                                    c.member_id AS VARCHAR(100)
                                ))),
                                ''
                            )
                        )
                    ),
                    NULLIF(
                        LTRIM(RTRIM(CAST(c.member_id AS VARCHAR(100)))),
                        ''
                    )
                )
                AS VARCHAR(50)
            ) AS member_id_str,
            TRY_CONVERT(
                DATE,
                CONVERT(
                    VARCHAR(6),
                    TRY_CONVERT(INT, c.month_and_year_of_medical_care)
                ) + '01',
                112
            ) AS month_start
        FROM @raw_database.JP_CLAIMS c
    ),
    claim_span AS (
        SELECT
            p.person_id,
            MIN(cm.month_start) AS start_date,
            EOMONTH(MAX(cm.month_start)) AS end_date
        FROM claim_month cm
        INNER JOIN @cdm_database.person p
          ON p.person_source_value = cm.member_id_str
        LEFT JOIN @cdm_database.observation_period op
          ON op.person_id = p.person_id
        WHERE op.person_id IS NULL
          AND cm.month_start IS NOT NULL
        GROUP BY p.person_id
    )
    INSERT INTO @cdm_database.observation_period (
        person_id,
        observation_period_start_date,
        observation_period_end_date,
        period_type_concept_id
    )
    SELECT
        s.person_id,
        s.start_date,
        s.end_date,
        44814725
    FROM claim_span s
    WHERE s.start_date IS NOT NULL
      AND s.end_date IS NOT NULL
      AND s.end_date >= s.start_date;
END;

SELECT
    CAST('observation_period' AS VARCHAR(50)) AS _etl_table,
    COUNT_BIG(*) AS _etl_total_rows
FROM @cdm_database.observation_period;
