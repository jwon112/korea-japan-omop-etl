/**************************************
 Japan: JP_PATIENT.withdrawal_death_flag -> death
 POLICY: LOAD - see MAPPING_POLICY.md

 A source death flag of exactly 1 is required. The observation end date is
 used as the available death date, and invalid dates are not loaded.
**************************************/

;WITH patient_death AS (
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
            LTRIM(RTRIM(
                REPLACE(
                    REPLACE(
                        REPLACE(
                            CAST(pt.withdrawal_death_flag AS VARCHAR(50)),
                            CHAR(13),
                            ''
                        ),
                        CHAR(10),
                        ''
                    ),
                    CHAR(9),
                    ''
                )
            )),
            ''
        ) AS death_flag,
        NULLIF(
            LTRIM(RTRIM(CAST(pt.observation_end AS VARCHAR(20)))),
            ''
        ) AS observation_end_str
    FROM @raw_database.JP_PATIENT pt
),
ready AS (
    SELECT
        p.person_id,
        d.death_flag,
        CASE
            WHEN LEN(d.observation_end_str) >= 8
            THEN TRY_CONVERT(
                DATE,
                LEFT(d.observation_end_str, 8),
                112
            )
            WHEN LEN(d.observation_end_str) = 6
            THEN EOMONTH(
                TRY_CONVERT(
                    DATE,
                    d.observation_end_str + '01',
                    112
                )
            )
        END AS death_date
    FROM patient_death d
    INNER JOIN @cdm_database.person p
      ON p.person_source_value = d.member_id_str
    WHERE d.death_flag = '1'
),
one_per_person AS (
    SELECT
        person_id,
        MAX(death_date) AS death_date
    FROM ready
    WHERE death_date IS NOT NULL
    GROUP BY person_id
)
INSERT INTO @cdm_database.death (
    person_id,
    death_date,
    death_datetime,
    death_type_concept_id,
    cause_concept_id,
    cause_source_value,
    cause_source_concept_id
)
SELECT
    r.person_id,
    r.death_date,
    NULL AS death_datetime,
    38003565 AS death_type_concept_id,
    NULL AS cause_concept_id,
    '1' AS cause_source_value,
    NULL AS cause_source_concept_id
FROM one_per_person r
WHERE NOT EXISTS (
    SELECT 1
    FROM @cdm_database.death d
    WHERE d.person_id = r.person_id
);

SELECT
    CAST('death' AS VARCHAR(50)) AS _etl_table,
    @@ROWCOUNT AS _etl_inserted_rows;
