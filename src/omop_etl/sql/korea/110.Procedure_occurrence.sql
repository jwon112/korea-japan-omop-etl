/**************************************
 Korea NHIS-NSC: procedure_occurrence

 30T and 60T are each scanned once and written directly to the CDM. Type 1/2
 source rows are retained as Procedure even when unmapped. Other non-drug,
 non-device rows are retained only when an active Procedure mapping exists and
 the source code is not also an active Device code.
***************************************/

IF OBJECT_ID('tempdb..#procedure_mapping', 'U') IS NOT NULL
    DROP TABLE #procedure_mapping;

;WITH valid_mapping AS (
    SELECT DISTINCT
        LTRIM(RTRIM(CONVERT(VARCHAR(50), m.source_code))) AS source_code,
        m.target_concept_id
    FROM @Mapping_database.SOURCE_TO_CONCEPT_MAP m
    JOIN @Mapping_database.CONCEPT c
      ON c.concept_id = m.target_concept_id
     AND c.domain_id = 'Procedure'
     AND c.standard_concept = 'S'
     AND c.invalid_reason IS NULL
    WHERE m.invalid_reason IS NULL
      AND LOWER(m.domain_id) = 'procedure'
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
INTO #procedure_mapping
FROM ranked_mapping;

CREATE UNIQUE CLUSTERED INDEX IX_procedure_mapping_source_target
    ON #procedure_mapping (source_code, target_concept_id);

IF EXISTS (
    SELECT 1
    FROM #procedure_mapping
    GROUP BY source_code
    HAVING COUNT_BIG(*) > 99
)
    THROW 51022, 'Procedure mapping exceeds the 99-target event ID allocation.', 1;

IF OBJECT_ID('tempdb..#device_code', 'U') IS NOT NULL
    DROP TABLE #device_code;

SELECT DISTINCT
    LTRIM(RTRIM(CONVERT(VARCHAR(50), m.source_code))) AS source_code
INTO #device_code
FROM @Mapping_database.SOURCE_TO_CONCEPT_MAP m
JOIN @Mapping_database.CONCEPT c
  ON c.concept_id = m.target_concept_id
 AND c.domain_id = 'Device'
 AND c.standard_concept = 'S'
 AND c.invalid_reason IS NULL
WHERE m.invalid_reason IS NULL
  AND LOWER(m.domain_id) = 'device'
  AND NULLIF(LTRIM(RTRIM(CONVERT(VARCHAR(50), m.source_code))), '')
      IS NOT NULL;

CREATE UNIQUE CLUSTERED INDEX IX_device_code_source
    ON #device_code (source_code);

IF OBJECT_ID('tempdb..#procedure_constants', 'U') IS NOT NULL
    DROP TABLE #procedure_constants;

SELECT CASE WHEN EXISTS (
    SELECT 1 FROM @NHISNSC_database.CONCEPT
    WHERE concept_id = 45756900
      AND domain_id = 'Type Concept'
      AND invalid_reason IS NULL
) THEN 45756900 ELSE 0 END AS procedure_type_concept_id
INTO #procedure_constants;
GO

/**************************************
 30T procedure rows
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
        ) AS procedure_date,
        NULLIF(LTRIM(RTRIM(CONVERT(VARCHAR(50), r.div_cd))), '') AS div_cd,
        LEFT(LTRIM(RTRIM(CONVERT(VARCHAR(50), r.div_cd))), 5)
            AS mapping_code,
        CONVERT(VARCHAR(10), r.div_type_cd) AS div_type_cd,
        TRY_CONVERT(FLOAT, r.mdcn_exec_freq) AS mdcn_exec_freq,
        TRY_CONVERT(FLOAT, r.dd_mqty_exec_freq) AS dd_mqty_exec_freq,
        TRY_CONVERT(FLOAT, r.dd_mqty_freq) AS dd_mqty_freq,
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
    WHERE r.div_type_cd IN ('1', '2')
       OR (
            r.div_type_cd NOT IN ('1', '2', '3', '4', '5', '7', '8')
        AND EXISTS (
                SELECT 1
                FROM #procedure_mapping p
                WHERE p.source_code = LEFT(
                    LTRIM(RTRIM(CONVERT(VARCHAR(50), r.div_cd))), 5
                )
            )
        AND NOT EXISTS (
                SELECT 1
                FROM #device_code d
                WHERE d.source_code = LEFT(
                    LTRIM(RTRIM(CONVERT(VARCHAR(50), r.div_cd))), 5
                )
            )
       )
), valid_30 AS (
    SELECT *
    FROM source_30
    WHERE procedure_date IS NOT NULL
      AND div_cd IS NOT NULL
      AND procedure_date BETWEEN visit_start_date AND visit_end_date
)
INSERT INTO @NHISNSC_database.PROCEDURE_OCCURRENCE (
    procedure_occurrence_id,
    person_id,
    procedure_concept_id,
    procedure_date,
    procedure_type_concept_id,
    modifier_concept_id,
    quantity,
    provider_id,
    visit_occurrence_id,
    procedure_source_value,
    procedure_source_concept_id
)
SELECT
    s.master_seq * CONVERT(BIGINT, 100) + COALESCE(m.target_ordinal, 1),
    s.person_id,
    COALESCE(m.target_concept_id, 0),
    s.procedure_date,
    k.procedure_type_concept_id,
    NULL,
    TRY_CONVERT(
        INT,
        (CASE WHEN s.dd_mqty_exec_freq > 0 THEN s.dd_mqty_exec_freq ELSE 1 END)
        * (CASE WHEN s.mdcn_exec_freq > 0 THEN s.mdcn_exec_freq ELSE 1 END)
        * (CASE WHEN s.dd_mqty_freq > 0 THEN s.dd_mqty_freq ELSE 1 END)
    ),
    NULL,
    s.key_seq,
    s.div_cd,
    NULL
FROM valid_30 s
LEFT JOIN #procedure_mapping m
  ON m.source_code = s.mapping_code
CROSS JOIN #procedure_constants k
OPTION (RECOMPILE, MAXDOP 2);
GO

/**************************************
 60T procedure rows
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
        ) AS procedure_date,
        NULLIF(LTRIM(RTRIM(CONVERT(VARCHAR(50), r.div_cd))), '') AS div_cd,
        LEFT(LTRIM(RTRIM(CONVERT(VARCHAR(50), r.div_cd))), 5)
            AS mapping_code,
        CONVERT(VARCHAR(10), r.div_type_cd) AS div_type_cd,
        TRY_CONVERT(FLOAT, r.mdcn_exec_freq) AS mdcn_exec_freq,
        TRY_CONVERT(FLOAT, r.dd_mqty_freq) AS dd_mqty_freq,
        TRY_CONVERT(FLOAT, r.dd_exec_freq) AS dd_exec_freq,
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
    WHERE r.div_type_cd IN ('1', '2')
       OR (
            r.div_type_cd NOT IN ('1', '2', '3', '4', '5', '7', '8')
        AND EXISTS (
                SELECT 1
                FROM #procedure_mapping p
                WHERE p.source_code = LEFT(
                    LTRIM(RTRIM(CONVERT(VARCHAR(50), r.div_cd))), 5
                )
            )
        AND NOT EXISTS (
                SELECT 1
                FROM #device_code d
                WHERE d.source_code = LEFT(
                    LTRIM(RTRIM(CONVERT(VARCHAR(50), r.div_cd))), 5
                )
            )
       )
), valid_60 AS (
    SELECT *
    FROM source_60
    WHERE procedure_date IS NOT NULL
      AND div_cd IS NOT NULL
      AND procedure_date BETWEEN visit_start_date AND visit_end_date
)
INSERT INTO @NHISNSC_database.PROCEDURE_OCCURRENCE (
    procedure_occurrence_id,
    person_id,
    procedure_concept_id,
    procedure_date,
    procedure_type_concept_id,
    modifier_concept_id,
    quantity,
    provider_id,
    visit_occurrence_id,
    procedure_source_value,
    procedure_source_concept_id
)
SELECT
    s.master_seq * CONVERT(BIGINT, 100) + COALESCE(m.target_ordinal, 1),
    s.person_id,
    COALESCE(m.target_concept_id, 0),
    s.procedure_date,
    k.procedure_type_concept_id,
    NULL,
    TRY_CONVERT(
        INT,
        (CASE WHEN s.dd_mqty_freq > 0 THEN s.dd_mqty_freq ELSE 1 END)
        * (CASE WHEN s.dd_exec_freq > 0 THEN s.dd_exec_freq ELSE 1 END)
        * (CASE WHEN s.mdcn_exec_freq > 0 THEN s.mdcn_exec_freq ELSE 1 END)
    ),
    NULL,
    s.key_seq,
    s.div_cd,
    NULL
FROM valid_60 s
LEFT JOIN #procedure_mapping m
  ON m.source_code = s.mapping_code
CROSS JOIN #procedure_constants k
OPTION (RECOMPILE, MAXDOP 2);
GO

DROP TABLE #procedure_constants;
DROP TABLE #device_code;
DROP TABLE #procedure_mapping;
GO
