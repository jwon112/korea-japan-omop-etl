/*******************************************************************************
Korea NHIS-NSC condition_occurrence

Each NHID_40 diagnosis row is anchored to its deterministic SEQ_MASTER row
and to an accepted visit. An active source code may expand to more than one
active standard Condition concept; an unmapped source row is retained once
with concept_id 0. Event IDs reserve 99 target slots per source row.
*******************************************************************************/

SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#condition_mapping') IS NOT NULL
    DROP TABLE #condition_mapping;

;WITH active_mapping AS (
    SELECT DISTINCT
        LTRIM(RTRIM(stcm.source_code)) AS source_code,
        stcm.target_concept_id
    FROM @Mapping_database.source_to_concept_map stcm
    JOIN @Mapping_database.CONCEPT c
      ON c.concept_id = stcm.target_concept_id
    WHERE LOWER(stcm.domain_id) = 'condition'
      AND stcm.invalid_reason IS NULL
      AND c.invalid_reason IS NULL
      AND c.standard_concept = 'S'
      AND c.domain_id = 'Condition'
      AND NULLIF(LTRIM(RTRIM(stcm.source_code)), '') IS NOT NULL
),
ranked_mapping AS (
    SELECT
        source_code,
        target_concept_id,
        ROW_NUMBER() OVER (
            PARTITION BY source_code
            ORDER BY target_concept_id
        ) AS target_ordinal
    FROM active_mapping
)
SELECT
    source_code,
    target_concept_id,
    target_ordinal
INTO #condition_mapping
FROM ranked_mapping;

CREATE UNIQUE CLUSTERED INDEX IX_condition_mapping
    ON #condition_mapping (source_code, target_concept_id);

IF EXISTS (
    SELECT 1
    FROM #condition_mapping
    GROUP BY source_code
    HAVING COUNT_BIG(*) > 99
)
    THROW 51020,
        'Condition mapping exceeds the 99-target event ID allocation.', 1;
GO

;WITH condition_source AS (
    SELECT
        sm.master_seq,
        sm.person_id,
        sm.key_seq AS visit_occurrence_id,
        TRY_CONVERT(INT, src.seq_no) AS diagnosis_sequence,
        NULLIF(LTRIM(RTRIM(src.sick_sym)), '') AS source_code,
        v.visit_start_date,
        v.visit_end_date
    FROM @NHISNSC_database.SEQ_MASTER sm
    JOIN @NHISNSC_rawdata.@NHIS_40T src
      ON src.key_seq = sm.key_seq
     AND src.seq_no = sm.seq_no
    JOIN @NHISNSC_database.VISIT_OCCURRENCE v
      ON v.visit_occurrence_id = sm.key_seq
     AND v.person_id = sm.person_id
    WHERE sm.source_table = '140'
)
INSERT INTO @NHISNSC_database.CONDITION_OCCURRENCE (
    condition_occurrence_id,
    person_id,
    condition_concept_id,
    condition_start_date,
    condition_end_date,
    condition_type_concept_id,
    stop_reason,
    provider_id,
    visit_occurrence_id,
    condition_source_value,
    condition_source_concept_id
)
SELECT
    CONVERT(BIGINT, s.master_seq) * 100
        + COALESCE(m.target_ordinal, 1) AS condition_occurrence_id,
    s.person_id,
    COALESCE(m.target_concept_id, 0) AS condition_concept_id,
    s.visit_start_date,
    s.visit_end_date,
    CASE s.diagnosis_sequence
        WHEN 1 THEN 44786627
        WHEN 2 THEN 44786629
        WHEN 3 THEN 45756845
        WHEN 4 THEN 45756846
        ELSE 45756847
    END AS condition_type_concept_id,
    NULL AS stop_reason,
    NULL AS provider_id,
    s.visit_occurrence_id,
    s.source_code AS condition_source_value,
    NULL AS condition_source_concept_id
FROM condition_source s
LEFT JOIN #condition_mapping m
  ON m.source_code = s.source_code
OPTION (HASH JOIN, RECOMPILE, MAXDOP 4);
GO

DROP TABLE #condition_mapping;
GO
