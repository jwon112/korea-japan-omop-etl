/**************************************
 Korea NHIS-NSC: cost

 Visit costs come from NHID_20. Drug, Procedure, and Device costs reuse the
 AMT value captured in SEQ_MASTER during the single source-detail scan.
 Event IDs reserve the final two digits for vocabulary expansion, so integer
 division by 100 recovers the source master_seq.
***************************************/

IF NOT EXISTS (
	SELECT 1
	FROM @Mapping_database.CONCEPT
	WHERE concept_id = 31968
	  AND domain_id = 'Type Concept'
	  AND invalid_reason IS NULL
)
	THROW 51030, 'Required cost type concept 31968 is not active.', 1;

IF NOT EXISTS (
	SELECT 1
	FROM @Mapping_database.CONCEPT
	WHERE concept_id = 44818598
	  AND domain_id = 'Currency'
	  AND standard_concept = 'S'
	  AND invalid_reason IS NULL
)
	THROW 51031, 'Required KRW currency concept 44818598 is not active standard.', 1;

IF OBJECT_ID('tempdb..#procedure_codes', 'U') IS NOT NULL
	DROP TABLE #procedure_codes;

SELECT DISTINCT scm.source_code
INTO #procedure_codes
FROM @Mapping_database.source_to_concept_map scm
JOIN @Mapping_database.CONCEPT c
  ON c.concept_id = scm.target_concept_id
WHERE scm.domain_id = 'Procedure'
  AND scm.invalid_reason IS NULL
  AND c.invalid_reason IS NULL
  AND c.standard_concept = 'S'
  AND c.domain_id = 'Procedure';

CREATE UNIQUE CLUSTERED INDEX UX_procedure_codes
	ON #procedure_codes (source_code);
GO

-- Claim-level Visit cost.
;WITH claim_cost AS (
	SELECT
		TRY_CONVERT(BIGINT, key_seq) AS visit_occurrence_id,
		TRY_CONVERT(INT, person_id) AS person_id,
		TRY_CONVERT(FLOAT, dmd_tramt) AS total_charge,
		TRY_CONVERT(FLOAT, edec_tramt) AS total_paid,
		TRY_CONVERT(FLOAT, edec_jbrdn_amt) AS paid_by_payer,
		TRY_CONVERT(FLOAT, edec_sbrdn_amt) AS paid_by_patient,
		CAST(dmd_drg_no AS VARCHAR(50)) AS drg_source_value
	FROM @NHISNSC_rawdata.@NHIS_20T
)
INSERT INTO @NHISNSC_database.COST (
	cost_id,
	cost_event_id,
	cost_domain_id,
	cost_type_concept_id,
	currency_concept_id,
	total_charge,
	total_cost,
	total_paid,
	paid_by_payer,
	paid_by_patient,
	paid_patient_copay,
	paid_patient_coinsurance,
	paid_patient_deductible,
	paid_by_primary,
	paid_ingredient_cost,
	paid_dispensing_fee,
	payer_plan_period_id,
	amount_allowed,
	revenue_code_concept_id,
	drg_concept_id,
	revenue_code_source_value,
	drg_source_value
)
SELECT
	v.visit_occurrence_id * CAST(10 AS BIGINT) + 1,
	v.visit_occurrence_id,
	'Visit',
	31968,
	44818598,
	r.total_charge,
	NULL,
	r.total_paid,
	r.paid_by_payer,
	r.paid_by_patient,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	pp.payer_plan_period_id,
	NULL,
	NULL,
	NULL,
	NULL,
	r.drg_source_value
FROM @NHISNSC_database.VISIT_OCCURRENCE v
JOIN claim_cost r
  ON r.visit_occurrence_id = v.visit_occurrence_id
 AND r.person_id = v.person_id
LEFT JOIN @NHISNSC_database.PAYER_PLAN_PERIOD pp
  ON pp.person_id = v.person_id
 AND v.visit_start_date BETWEEN pp.payer_plan_period_start_date
							AND pp.payer_plan_period_end_date
WHERE r.total_charge IS NOT NULL
   OR r.total_paid IS NOT NULL
   OR r.paid_by_payer IS NOT NULL
   OR r.paid_by_patient IS NOT NULL
OPTION (HASH JOIN, RECOMPILE, MAXDOP 4);
GO

-- Drug event cost. Source table is recovered from the deterministic master key,
-- not from drug_type_concept_id.
INSERT INTO @NHISNSC_database.COST (
	cost_id,
	cost_event_id,
	cost_domain_id,
	cost_type_concept_id,
	currency_concept_id,
	total_charge,
	total_cost,
	total_paid,
	paid_by_payer,
	paid_by_patient,
	paid_patient_copay,
	paid_patient_coinsurance,
	paid_patient_deductible,
	paid_by_primary,
	paid_ingredient_cost,
	paid_dispensing_fee,
	payer_plan_period_id,
	amount_allowed,
	revenue_code_concept_id,
	drg_concept_id,
	revenue_code_source_value,
	drg_source_value
)
SELECT
	e.drug_exposure_id * CAST(10 AS BIGINT) + 2,
	e.drug_exposure_id,
	'Drug',
	31968,
	44818598,
	NULL,
	m.total_cost,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	pp.payer_plan_period_id,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL
FROM @NHISNSC_database.DRUG_EXPOSURE e
JOIN @NHISNSC_database.SEQ_MASTER m
  ON m.master_seq = e.drug_exposure_id / CAST(100 AS BIGINT)
 AND m.person_id = e.person_id
 AND m.source_table IN ('130', '160')
LEFT JOIN @NHISNSC_database.PAYER_PLAN_PERIOD pp
  ON pp.person_id = e.person_id
 AND e.drug_exposure_start_date BETWEEN pp.payer_plan_period_start_date
									AND pp.payer_plan_period_end_date
WHERE e.drug_exposure_id % CAST(100 AS BIGINT) = 1
  AND m.total_cost IS NOT NULL
OPTION (HASH JOIN, RECOMPILE, MAXDOP 4);
GO

-- Procedure event cost.
INSERT INTO @NHISNSC_database.COST (
	cost_id,
	cost_event_id,
	cost_domain_id,
	cost_type_concept_id,
	currency_concept_id,
	total_charge,
	total_cost,
	total_paid,
	paid_by_payer,
	paid_by_patient,
	paid_patient_copay,
	paid_patient_coinsurance,
	paid_patient_deductible,
	paid_by_primary,
	paid_ingredient_cost,
	paid_dispensing_fee,
	payer_plan_period_id,
	amount_allowed,
	revenue_code_concept_id,
	drg_concept_id,
	revenue_code_source_value,
	drg_source_value
)
SELECT
	e.procedure_occurrence_id * CAST(10 AS BIGINT) + 3,
	e.procedure_occurrence_id,
	'Procedure',
	31968,
	44818598,
	NULL,
	m.total_cost,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	pp.payer_plan_period_id,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL
FROM @NHISNSC_database.PROCEDURE_OCCURRENCE e
JOIN @NHISNSC_database.SEQ_MASTER m
  ON m.master_seq = e.procedure_occurrence_id / CAST(100 AS BIGINT)
 AND m.person_id = e.person_id
 AND m.source_table IN ('130', '160')
LEFT JOIN @NHISNSC_database.PAYER_PLAN_PERIOD pp
  ON pp.person_id = e.person_id
 AND e.procedure_date BETWEEN pp.payer_plan_period_start_date
						  AND pp.payer_plan_period_end_date
WHERE e.procedure_occurrence_id % CAST(100 AS BIGINT) = 1
  AND m.total_cost IS NOT NULL
OPTION (HASH JOIN, RECOMPILE, MAXDOP 4);
GO

-- Device costs are omitted for codes also represented in Procedure to avoid
-- charging the same source detail in both domains.
INSERT INTO @NHISNSC_database.COST (
	cost_id,
	cost_event_id,
	cost_domain_id,
	cost_type_concept_id,
	currency_concept_id,
	total_charge,
	total_cost,
	total_paid,
	paid_by_payer,
	paid_by_patient,
	paid_patient_copay,
	paid_patient_coinsurance,
	paid_patient_deductible,
	paid_by_primary,
	paid_ingredient_cost,
	paid_dispensing_fee,
	payer_plan_period_id,
	amount_allowed,
	revenue_code_concept_id,
	drg_concept_id,
	revenue_code_source_value,
	drg_source_value
)
SELECT
	e.device_exposure_id * CAST(10 AS BIGINT) + 4,
	e.device_exposure_id,
	'Device',
	31968,
	44818598,
	NULL,
	m.total_cost,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	pp.payer_plan_period_id,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL
FROM @NHISNSC_database.DEVICE_EXPOSURE e
JOIN @NHISNSC_database.SEQ_MASTER m
  ON m.master_seq = e.device_exposure_id / CAST(100 AS BIGINT)
 AND m.person_id = e.person_id
 AND m.source_table IN ('130', '160')
LEFT JOIN @NHISNSC_database.PAYER_PLAN_PERIOD pp
  ON pp.person_id = e.person_id
 AND e.device_exposure_start_date BETWEEN pp.payer_plan_period_start_date
									 AND pp.payer_plan_period_end_date
WHERE e.device_exposure_id % CAST(100 AS BIGINT) = 1
  AND m.total_cost IS NOT NULL
  AND NOT EXISTS (
	SELECT 1
	FROM #procedure_codes pc
	WHERE pc.source_code = e.device_source_value
)
OPTION (HASH JOIN, RECOMPILE, MAXDOP 4);
GO

DROP TABLE #procedure_codes;
GO
