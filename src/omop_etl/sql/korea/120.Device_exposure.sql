/**************************************
 Korea NHIS-NSC: device_exposure

 30T and 60T are each scanned once and written directly to the CDM. Type 7/8
 rows are retained as Device even when unmapped. Other non-drug,
 non-procedure rows are retained only when an active Device mapping exists and
 the source code is not also an active Procedure code.
***************************************/

IF OBJECT_ID('tempdb..#device_mapping', 'U') IS NOT NULL
    DROP TABLE #device_mapping;

;WITH valid_mapping AS (
    SELECT DISTINCT
        LTRIM(RTRIM(CONVERT(VARCHAR(50), m.source_code))) AS source_code,
        m.target_concept_id
    FROM @Mapping_database.SOURCE_TO_CONCEPT_MAP m
    JOIN @Mapping_database.CONCEPT c
      ON c.concept_id = m.target_concept_id
     AND c.domain_id = 'Device'
     AND c.standard_concept = 'S'
     AND c.invalid_reason IS NULL
    WHERE m.invalid_reason IS NULL
      AND LOWER(m.domain_id) = 'device'
      AND NULLIF(LTRIM(RTRIM(CONVERT(VARCHAR(50), m.source_code))), '')
          IS NOT NULL
), ranked_mapping AS (
    SELECT
        source_code,
        target_concept_id,
        ROW_NUMBER() OVER (
            PARTITION BY source_code
            ORDER BY target_concept_id
        ) AS target_ordinal
    FROM valid_mapping
)
SELECT source_code, target_concept_id, target_ordinal
INTO #device_mapping
FROM ranked_mapping;

CREATE UNIQUE CLUSTERED INDEX IX_device_mapping_source_target
    ON #device_mapping (source_code, target_concept_id);

IF EXISTS (
    SELECT 1
    FROM #device_mapping
    GROUP BY source_code
    HAVING COUNT_BIG(*) > 99
)
    THROW 51023, 'Device mapping exceeds the 99-target event ID allocation.', 1;

IF OBJECT_ID('tempdb..#procedure_code', 'U') IS NOT NULL
    DROP TABLE #procedure_code;

SELECT DISTINCT
    LTRIM(RTRIM(CONVERT(VARCHAR(50), m.source_code))) AS source_code
INTO #procedure_code
FROM @Mapping_database.SOURCE_TO_CONCEPT_MAP m
JOIN @Mapping_database.CONCEPT c
  ON c.concept_id = m.target_concept_id
 AND c.domain_id = 'Procedure'
 AND c.standard_concept = 'S'
 AND c.invalid_reason IS NULL
WHERE m.invalid_reason IS NULL
  AND LOWER(m.domain_id) = 'procedure'
  AND NULLIF(LTRIM(RTRIM(CONVERT(VARCHAR(50), m.source_code))), '')
      IS NOT NULL;

CREATE UNIQUE CLUSTERED INDEX IX_procedure_code_source
    ON #procedure_code (source_code);

IF OBJECT_ID('tempdb..#device_constants', 'U') IS NOT NULL
    DROP TABLE #device_constants;

SELECT CASE WHEN EXISTS (
    SELECT 1 FROM @NHISNSC_database.CONCEPT
    WHERE concept_id = 44818705
      AND domain_id = 'Type Concept'
      AND invalid_reason IS NULL
) THEN 44818705 ELSE 0 END AS device_type_concept_id
INTO #device_constants;
GO

/**************************************
 30T device rows
***************************************/
;WITH source_30 AS (
    SELECT
        sm.master_seq,
        sm.person_id,
        sm.key_seq,
        TRY_CONVERT(
            DATE,
            NULLIF(LTRIM(RTRIM(CONVERT(VARCHAR(20), r.recu_fr_dt))), ''),
            112
        ) AS device_start_date,
        NULLIF(LTRIM(RTRIM(CONVERT(VARCHAR(100), r.div_cd))), '') AS div_cd,
        CONVERT(VARCHAR(10), r.div_type_cd) AS div_type_cd,
        TRY_CONVERT(FLOAT, r.mdcn_exec_freq) AS mdcn_exec_freq,
        TRY_CONVERT(FLOAT, r.dd_mqty_exec_freq) AS dd_mqty_exec_freq,
        TRY_CONVERT(FLOAT, r.dd_mqty_freq) AS dd_mqty_freq,
        TRY_CONVERT(FLOAT, r.amt) AS amount,
        TRY_CONVERT(FLOAT, r.un_cost) AS unit_cost,
        v.visit_start_date,
        v.visit_end_date
    FROM @NHISNSC_rawdata.@NHIS_30T r
    JOIN @NHISNSC_database.SEQ_MASTER sm
      ON sm.source_table = '130'
     AND sm.key_seq = TRY_CONVERT(BIGINT, r.key_seq)
     AND sm.seq_no = TRY_CONVERT(NUMERIC(4), r.seq_no)
    JOIN @NHISNSC_database.VISIT_OCCURRENCE v
      ON v.visit_occurrence_id = sm.key_seq
     AND v.person_id = sm.person_id
    WHERE r.div_type_cd IN ('7', '8')
       OR (
            r.div_type_cd NOT IN ('1', '2', '3', '4', '5', '7', '8')
        AND EXISTS (
                SELECT 1
                FROM #device_mapping d
                WHERE d.source_code =
                    LTRIM(RTRIM(CONVERT(VARCHAR(50), r.div_cd)))
            )
        AND NOT EXISTS (
                SELECT 1
                FROM #procedure_code p
                WHERE p.source_code =
                    LTRIM(RTRIM(CONVERT(VARCHAR(50), r.div_cd)))
            )
       )
), valid_30 AS (
    SELECT
        s.*,
        CASE
            WHEN s.mdcn_exec_freq >= 1 AND s.mdcn_exec_freq <= 36525
                THEN CONVERT(INT, FLOOR(s.mdcn_exec_freq))
            ELSE 1
        END AS exposure_days
    FROM source_30 s
    WHERE s.device_start_date IS NOT NULL
      AND s.div_cd IS NOT NULL
      AND s.device_start_date BETWEEN s.visit_start_date AND s.visit_end_date
)
INSERT INTO @NHISNSC_database.DEVICE_EXPOSURE (
    device_exposure_id,
    person_id,
    device_concept_id,
    device_exposure_start_date,
    device_exposure_end_date,
    device_type_concept_id,
    unique_device_id,
    quantity,
    provider_id,
    visit_occurrence_id,
    device_source_value,
    device_source_concept_id
)
SELECT
    s.master_seq * CONVERT(BIGINT, 100) + COALESCE(m.target_ordinal, 1),
    s.person_id,
    COALESCE(m.target_concept_id, 0),
    s.device_start_date,
    CASE
        WHEN d.death_date IS NOT NULL
         AND d.death_date < DATEADD(DAY, s.exposure_days - 1, s.device_start_date)
            THEN d.death_date
        ELSE DATEADD(DAY, s.exposure_days - 1, s.device_start_date)
    END,
    k.device_type_concept_id,
    NULL,
    TRY_CONVERT(
        INT,
        CASE
            WHEN s.amount > 0 AND s.unit_cost > 0 AND s.amount >= s.unit_cost
                THEN s.amount / s.unit_cost
            ELSE
                (CASE WHEN s.dd_mqty_exec_freq > 0 THEN s.dd_mqty_exec_freq ELSE 1 END)
                * (CASE WHEN s.mdcn_exec_freq > 0 THEN s.mdcn_exec_freq ELSE 1 END)
                * (CASE WHEN s.dd_mqty_freq > 0 THEN s.dd_mqty_freq ELSE 1 END)
        END
    ),
    NULL,
    s.key_seq,
    s.div_cd,
    NULL
FROM valid_30 s
LEFT JOIN #device_mapping m
  ON m.source_code = s.div_cd
LEFT JOIN @NHISNSC_database.DEATH d
  ON d.person_id = s.person_id
CROSS JOIN #device_constants k
WHERE d.death_date IS NULL
   OR s.device_start_date <= d.death_date
OPTION (RECOMPILE, MAXDOP 2);
GO

/**************************************
 60T device rows
***************************************/
;WITH source_60 AS (
    SELECT
        sm.master_seq,
        sm.person_id,
        sm.key_seq,
        TRY_CONVERT(
            DATE,
            NULLIF(LTRIM(RTRIM(CONVERT(VARCHAR(20), r.recu_fr_dt))), ''),
            112
        ) AS device_start_date,
        NULLIF(LTRIM(RTRIM(CONVERT(VARCHAR(100), r.div_cd))), '') AS div_cd,
        CONVERT(VARCHAR(10), r.div_type_cd) AS div_type_cd,
        TRY_CONVERT(FLOAT, r.mdcn_exec_freq) AS mdcn_exec_freq,
        TRY_CONVERT(FLOAT, r.dd_mqty_freq) AS dd_mqty_freq,
        TRY_CONVERT(FLOAT, r.dd_exec_freq) AS dd_exec_freq,
        TRY_CONVERT(FLOAT, r.amt) AS amount,
        TRY_CONVERT(FLOAT, r.un_cost) AS unit_cost,
        v.visit_start_date,
        v.visit_end_date
    FROM @NHISNSC_rawdata.@NHIS_60T r
    JOIN @NHISNSC_database.SEQ_MASTER sm
      ON sm.source_table = '160'
     AND sm.key_seq = TRY_CONVERT(BIGINT, r.key_seq)
     AND sm.seq_no = TRY_CONVERT(NUMERIC(4), r.seq_no)
    JOIN @NHISNSC_database.VISIT_OCCURRENCE v
      ON v.visit_occurrence_id = sm.key_seq
     AND v.person_id = sm.person_id
    WHERE r.div_type_cd IN ('7', '8')
       OR (
            r.div_type_cd NOT IN ('1', '2', '3', '4', '5', '7', '8')
        AND EXISTS (
                SELECT 1
                FROM #device_mapping d
                WHERE d.source_code =
                    LTRIM(RTRIM(CONVERT(VARCHAR(50), r.div_cd)))
            )
        AND NOT EXISTS (
                SELECT 1
                FROM #procedure_code p
                WHERE p.source_code =
                    LTRIM(RTRIM(CONVERT(VARCHAR(50), r.div_cd)))
            )
       )
), valid_60 AS (
    SELECT
        s.*,
        CASE
            WHEN s.mdcn_exec_freq >= 1 AND s.mdcn_exec_freq <= 36525
                THEN CONVERT(INT, FLOOR(s.mdcn_exec_freq))
            ELSE 1
        END AS exposure_days
    FROM source_60 s
    WHERE s.device_start_date IS NOT NULL
      AND s.div_cd IS NOT NULL
      AND s.device_start_date BETWEEN s.visit_start_date AND s.visit_end_date
)
INSERT INTO @NHISNSC_database.DEVICE_EXPOSURE (
    device_exposure_id,
    person_id,
    device_concept_id,
    device_exposure_start_date,
    device_exposure_end_date,
    device_type_concept_id,
    unique_device_id,
    quantity,
    provider_id,
    visit_occurrence_id,
    device_source_value,
    device_source_concept_id
)
SELECT
    s.master_seq * CONVERT(BIGINT, 100) + COALESCE(m.target_ordinal, 1),
    s.person_id,
    COALESCE(m.target_concept_id, 0),
    s.device_start_date,
    CASE
        WHEN d.death_date IS NOT NULL
         AND d.death_date < DATEADD(DAY, s.exposure_days - 1, s.device_start_date)
            THEN d.death_date
        ELSE DATEADD(DAY, s.exposure_days - 1, s.device_start_date)
    END,
    k.device_type_concept_id,
    NULL,
    TRY_CONVERT(
        INT,
        CASE
            WHEN s.amount > 0 AND s.unit_cost > 0 AND s.amount >= s.unit_cost
                THEN s.amount / s.unit_cost
            ELSE
                (CASE WHEN s.mdcn_exec_freq > 0 THEN s.mdcn_exec_freq ELSE 1 END)
                * (CASE WHEN s.dd_mqty_freq > 0 THEN s.dd_mqty_freq ELSE 1 END)
                * (CASE WHEN s.dd_exec_freq > 0 THEN s.dd_exec_freq ELSE 1 END)
        END
    ),
    NULL,
    s.key_seq,
    s.div_cd,
    NULL
FROM valid_60 s
LEFT JOIN #device_mapping m
  ON m.source_code = s.div_cd
LEFT JOIN @NHISNSC_database.DEATH d
  ON d.person_id = s.person_id
CROSS JOIN #device_constants k
WHERE d.death_date IS NULL
   OR s.device_start_date <= d.death_date
OPTION (RECOMPILE, MAXDOP 2);
GO

DROP TABLE #device_constants;
DROP TABLE #procedure_code;
DROP TABLE #device_mapping;
GO
