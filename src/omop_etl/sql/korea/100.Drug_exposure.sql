/**************************************
 Korea NHIS-NSC: drug_exposure

 30T and 60T are each scanned once and written directly to the CDM. Only the
 small mapping and constant tables use tempdb. Active standard Drug mappings
 may expand one source event; unmapped drug candidates are retained as 0.
***************************************/

IF OBJECT_ID('tempdb..#drug_mapping', 'U') IS NOT NULL
    DROP TABLE #drug_mapping;

;WITH valid_mapping AS (
    SELECT DISTINCT
        LTRIM(RTRIM(CONVERT(VARCHAR(50), m.source_code))) AS source_code,
        m.target_concept_id
    FROM @Mapping_database.SOURCE_TO_CONCEPT_MAP m
    JOIN @Mapping_database.CONCEPT c
      ON c.concept_id = m.target_concept_id
     AND c.domain_id = 'Drug'
     AND c.standard_concept = 'S'
     AND c.invalid_reason IS NULL
    WHERE m.invalid_reason IS NULL
      AND LOWER(m.domain_id) = 'drug'
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
INTO #drug_mapping
FROM ranked_mapping;

CREATE UNIQUE CLUSTERED INDEX IX_drug_mapping_source_target
    ON #drug_mapping (source_code, target_concept_id);

IF EXISTS (
    SELECT 1
    FROM #drug_mapping
    GROUP BY source_code
    HAVING COUNT_BIG(*) > 99
)
    THROW 51021, 'Drug mapping exceeds the 99-target event ID allocation.', 1;

IF OBJECT_ID('tempdb..#drug_constants', 'U') IS NOT NULL
    DROP TABLE #drug_constants;

SELECT
    CASE WHEN EXISTS (
        SELECT 1 FROM @NHISNSC_database.CONCEPT
        WHERE concept_id = 38000180
          AND domain_id = 'Type Concept'
          AND invalid_reason IS NULL
    ) THEN 38000180 ELSE 0 END AS inpatient_type_concept_id,
    CASE WHEN EXISTS (
        SELECT 1 FROM @NHISNSC_database.CONCEPT
        WHERE concept_id = 581452
          AND domain_id = 'Type Concept'
          AND invalid_reason IS NULL
    ) THEN 581452 ELSE 0 END AS other_type_concept_id,
    CASE WHEN EXISTS (
        SELECT 1 FROM @NHISNSC_database.CONCEPT
        WHERE concept_id = 4132161
          AND domain_id = 'Route'
          AND standard_concept = 'S'
          AND invalid_reason IS NULL
    ) THEN 4132161 ELSE 0 END AS oral_route_concept_id,
    CASE WHEN EXISTS (
        SELECT 1 FROM @NHISNSC_database.CONCEPT
        WHERE concept_id = 4142048
          AND domain_id = 'Route'
          AND standard_concept = 'S'
          AND invalid_reason IS NULL
    ) THEN 4142048 ELSE 0 END AS subcutaneous_route_concept_id,
    CASE WHEN EXISTS (
        SELECT 1 FROM @NHISNSC_database.CONCEPT
        WHERE concept_id = 4171047
          AND domain_id = 'Route'
          AND standard_concept = 'S'
          AND invalid_reason IS NULL
    ) THEN 4171047 ELSE 0 END AS intravenous_route_concept_id
INTO #drug_constants;
GO

/**************************************
 30T drug rows
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
        ) AS drug_start_date,
        NULLIF(LTRIM(RTRIM(CONVERT(VARCHAR(50), r.div_cd))), '') AS div_cd,
        CONVERT(VARCHAR(10), r.div_type_cd) AS div_type_cd,
        CONVERT(VARCHAR(10), claim.form_cd) AS form_cd,
        TRY_CONVERT(FLOAT, r.mdcn_exec_freq) AS mdcn_exec_freq,
        TRY_CONVERT(FLOAT, r.dd_mqty_exec_freq) AS dd_mqty_exec_freq,
        TRY_CONVERT(FLOAT, r.dd_mqty_freq) AS dd_mqty_freq,
        CASE
            WHEN TRY_CONVERT(INT, r.clause_cd) BETWEEN 1 AND 9
                THEN RIGHT('0' + CONVERT(VARCHAR(10), TRY_CONVERT(INT, r.clause_cd)), 2)
            ELSE CONVERT(VARCHAR(10), r.clause_cd)
        END AS clause_cd,
        CASE
            WHEN TRY_CONVERT(INT, r.item_cd) BETWEEN 1 AND 9
                THEN RIGHT('0' + CONVERT(VARCHAR(10), TRY_CONVERT(INT, r.item_cd)), 2)
            ELSE CONVERT(VARCHAR(10), r.item_cd)
        END AS item_cd,
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
    JOIN @NHISNSC_rawdata.@NHIS_20T claim
      ON TRY_CONVERT(BIGINT, claim.key_seq) = sm.key_seq
     AND TRY_CONVERT(INT, claim.person_id) = sm.person_id
    WHERE r.div_type_cd IN ('3', '4', '5')
       OR EXISTS (
            SELECT 1
            FROM #drug_mapping m
            WHERE m.source_code =
                LTRIM(RTRIM(CONVERT(VARCHAR(50), r.div_cd)))
       )
), valid_30 AS (
    SELECT
        s.*,
        CASE
            WHEN s.mdcn_exec_freq >= 1 AND s.mdcn_exec_freq <= 36525
                THEN CONVERT(INT, FLOOR(s.mdcn_exec_freq))
            ELSE 1
        END AS days_supply
    FROM source_30 s
    WHERE s.drug_start_date IS NOT NULL
      AND s.div_cd IS NOT NULL
      AND s.drug_start_date BETWEEN s.visit_start_date AND s.visit_end_date
)
INSERT INTO @NHISNSC_database.DRUG_EXPOSURE (
    drug_exposure_id, person_id, drug_concept_id,
    drug_exposure_start_date, drug_exposure_end_date,
    drug_type_concept_id, stop_reason, refills, quantity, days_supply,
    sig, route_concept_id, lot_number, provider_id, visit_occurrence_id,
    drug_source_value, drug_source_concept_id, route_source_value,
    dose_unit_source_value
)
SELECT
    s.master_seq * CONVERT(BIGINT, 100) + COALESCE(m.target_ordinal, 1),
    s.person_id,
    COALESCE(m.target_concept_id, 0),
    s.drug_start_date,
    CASE
        WHEN d.death_date IS NOT NULL
         AND d.death_date < DATEADD(DAY, s.days_supply - 1, s.drug_start_date)
            THEN d.death_date
        ELSE DATEADD(DAY, s.days_supply - 1, s.drug_start_date)
    END,
    CASE
        WHEN s.form_cd IN ('02', '2', '04', '06', '10', '12')
            THEN k.inpatient_type_concept_id
        ELSE k.other_type_concept_id
    END,
    NULL,
    NULL,
    (CASE WHEN s.dd_mqty_exec_freq > 0 THEN s.dd_mqty_exec_freq ELSE 1 END)
        * (CASE WHEN s.mdcn_exec_freq > 0 THEN s.mdcn_exec_freq ELSE 1 END)
        * (CASE WHEN s.dd_mqty_freq > 0 THEN s.dd_mqty_freq ELSE 1 END),
    s.days_supply,
    s.clause_cd,
    CASE
        WHEN s.clause_cd = '03' AND s.item_cd = '01'
            THEN k.oral_route_concept_id
        WHEN s.clause_cd = '04' AND s.item_cd = '01'
            THEN k.subcutaneous_route_concept_id
        WHEN s.clause_cd = '04' AND s.item_cd IN ('02', '03')
            THEN k.intravenous_route_concept_id
        ELSE 0
    END,
    NULL,
    NULL,
    s.key_seq,
    s.div_cd,
    NULL,
    s.clause_cd + '/' + s.item_cd,
    NULL
FROM valid_30 s
LEFT JOIN #drug_mapping m
  ON m.source_code = s.div_cd
LEFT JOIN @NHISNSC_database.DEATH d
  ON d.person_id = s.person_id
CROSS JOIN #drug_constants k
WHERE d.death_date IS NULL
   OR s.drug_start_date <= d.death_date
OPTION (RECOMPILE, MAXDOP 2);
GO

/**************************************
 60T drug rows
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
        ) AS drug_start_date,
        NULLIF(LTRIM(RTRIM(CONVERT(VARCHAR(50), r.div_cd))), '') AS div_cd,
        CONVERT(VARCHAR(10), r.div_type_cd) AS div_type_cd,
        CONVERT(VARCHAR(10), claim.form_cd) AS form_cd,
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
    JOIN @NHISNSC_rawdata.@NHIS_20T claim
      ON TRY_CONVERT(BIGINT, claim.key_seq) = sm.key_seq
     AND TRY_CONVERT(INT, claim.person_id) = sm.person_id
    WHERE r.div_type_cd IN ('3', '4', '5')
       OR EXISTS (
            SELECT 1
            FROM #drug_mapping m
            WHERE m.source_code =
                LTRIM(RTRIM(CONVERT(VARCHAR(50), r.div_cd)))
       )
), valid_60 AS (
    SELECT
        s.*,
        CASE
            WHEN s.mdcn_exec_freq >= 1 AND s.mdcn_exec_freq <= 36525
                THEN CONVERT(INT, FLOOR(s.mdcn_exec_freq))
            ELSE 1
        END AS days_supply
    FROM source_60 s
    WHERE s.drug_start_date IS NOT NULL
      AND s.div_cd IS NOT NULL
      AND s.drug_start_date BETWEEN s.visit_start_date AND s.visit_end_date
)
INSERT INTO @NHISNSC_database.DRUG_EXPOSURE (
    drug_exposure_id, person_id, drug_concept_id,
    drug_exposure_start_date, drug_exposure_end_date,
    drug_type_concept_id, stop_reason, refills, quantity, days_supply,
    sig, route_concept_id, lot_number, provider_id, visit_occurrence_id,
    drug_source_value, drug_source_concept_id, route_source_value,
    dose_unit_source_value
)
SELECT
    s.master_seq * CONVERT(BIGINT, 100) + COALESCE(m.target_ordinal, 1),
    s.person_id,
    COALESCE(m.target_concept_id, 0),
    s.drug_start_date,
    CASE
        WHEN d.death_date IS NOT NULL
         AND d.death_date < DATEADD(DAY, s.days_supply - 1, s.drug_start_date)
            THEN d.death_date
        ELSE DATEADD(DAY, s.days_supply - 1, s.drug_start_date)
    END,
    CASE
        WHEN s.form_cd IN ('02', '2', '04', '06', '10', '12')
            THEN k.inpatient_type_concept_id
        ELSE k.other_type_concept_id
    END,
    NULL,
    NULL,
    (CASE WHEN s.dd_mqty_freq > 0 THEN s.dd_mqty_freq ELSE 1 END)
        * (CASE WHEN s.dd_exec_freq > 0 THEN s.dd_exec_freq ELSE 1 END)
        * (CASE WHEN s.mdcn_exec_freq > 0 THEN s.mdcn_exec_freq ELSE 1 END),
    s.days_supply,
    NULL,
    0,
    NULL,
    NULL,
    s.key_seq,
    s.div_cd,
    NULL,
    NULL,
    NULL
FROM valid_60 s
LEFT JOIN #drug_mapping m
  ON m.source_code = s.div_cd
LEFT JOIN @NHISNSC_database.DEATH d
  ON d.person_id = s.person_id
CROSS JOIN #drug_constants k
WHERE d.death_date IS NULL
   OR s.drug_start_date <= d.death_date
OPTION (RECOMPILE, MAXDOP 2);
GO

DROP TABLE #drug_constants;
DROP TABLE #drug_mapping;
GO
