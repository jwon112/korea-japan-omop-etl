/**************************************
 Japan: cost (minimal payer-point representation)
 POLICY: LOAD - see MAPPING_POLICY.md

 Cost source:
 - JP_CLAIMS.total_point -> Visit
 - jmdc_drug_norm.total_cost -> Drug
 - jmdc_proc_norm.total_cost -> Procedure

 master_seq is globally unique across JMDC source domains and is already the
 event primary identifier. Reuse it as both cost_id and cost_event_id.
 Currency and paid-by components remain unknown because the source values are
 reimbursement points, not a reviewed currency amount.
**************************************/

IF OBJECT_ID('@cdm_database.jmdc_drug_norm', 'U') IS NULL
    THROW 51000, 'cost requires completed drug_exposure staging', 1;

IF OBJECT_ID('@cdm_database.jmdc_proc_norm', 'U') IS NULL
    THROW 51000, 'cost requires completed procedure_occurrence staging', 1;

IF OBJECT_ID('@cdm_database.jmdc_claim_cost_norm', 'U') IS NOT NULL
   AND (
       COL_LENGTH('@cdm_database.jmdc_claim_cost_norm', 'master_seq') IS NULL
       OR COL_LENGTH('@cdm_database.jmdc_claim_cost_norm', 'total_cost') IS NULL
   )
BEGIN
    DROP TABLE @cdm_database.jmdc_claim_cost_norm;
END;

IF OBJECT_ID('@cdm_database.jmdc_claim_cost_norm', 'U') IS NULL
BEGIN
    SELECT
        sm.master_seq,
        TRY_CAST(
            REPLACE(
                REPLACE(CAST(c.total_point AS VARCHAR(100)), CHAR(13), ''),
                ',',
                ''
            )
            AS FLOAT
        ) AS total_cost
    INTO @cdm_database.jmdc_claim_cost_norm
    FROM @raw_database.JP_CLAIMS c
    INNER HASH JOIN @cdm_database.SEQ_MASTER sm
      ON sm.source_table = 'CLM'
     AND sm.member_id = CAST(c.member_id AS VARCHAR(50))
     AND sm.claim_id = CAST(c.claim_id AS VARCHAR(50))
     AND sm.statement_id IS NULL
    WHERE c.total_point IS NOT NULL
    OPTION (RECOMPILE, MAXDOP 4);
END;
GO

DECLARE @visit_rows BIGINT = 0;

IF NOT EXISTS (
    SELECT TOP (1) 1
    FROM @cdm_database.cost
    WHERE cost_domain_id = 'Visit'
)
BEGIN
    INSERT INTO @cdm_database.cost (
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
        revenue_code_source_value,
        drg_concept_id,
        drg_source_value
    )
    SELECT
        c.master_seq AS cost_id,
        c.master_seq AS cost_event_id,
        CAST(N'Visit' AS VARCHAR(20)) AS cost_domain_id,
        0 AS cost_type_concept_id,
        NULL AS currency_concept_id,
        c.total_cost AS total_charge,
        c.total_cost,
        NULL, NULL, NULL,
        NULL, NULL, NULL,
        NULL, NULL, NULL, NULL,
        NULL, NULL, NULL,
        NULL, NULL
    FROM @cdm_database.jmdc_claim_cost_norm c
    WHERE c.total_cost IS NOT NULL;

    SET @visit_rows = @@ROWCOUNT;
END;

SELECT
    CAST('cost_visit' AS VARCHAR(50)) AS _etl_table,
    @visit_rows AS _etl_inserted_rows;
GO

DECLARE @drug_rows BIGINT = 0;

IF NOT EXISTS (
    SELECT TOP (1) 1
    FROM @cdm_database.cost
    WHERE cost_domain_id = 'Drug'
)
BEGIN
    INSERT INTO @cdm_database.cost (
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
        revenue_code_source_value,
        drg_concept_id,
        drg_source_value
    )
    SELECT
        c.master_seq AS cost_id,
        c.master_seq AS cost_event_id,
        CAST(N'Drug' AS VARCHAR(20)) AS cost_domain_id,
        0 AS cost_type_concept_id,
        NULL AS currency_concept_id,
        c.total_cost AS total_charge,
        c.total_cost,
        NULL, NULL, NULL,
        NULL, NULL, NULL,
        NULL, NULL, NULL, NULL,
        NULL, NULL, NULL,
        NULL, NULL
    FROM @cdm_database.jmdc_drug_norm c
    WHERE c.total_cost IS NOT NULL;

    SET @drug_rows = @@ROWCOUNT;
END;

SELECT
    CAST('cost_drug' AS VARCHAR(50)) AS _etl_table,
    @drug_rows AS _etl_inserted_rows;
GO

DECLARE @procedure_rows BIGINT = 0;

IF NOT EXISTS (
    SELECT TOP (1) 1
    FROM @cdm_database.cost
    WHERE cost_domain_id = 'Procedure'
)
BEGIN
    INSERT INTO @cdm_database.cost (
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
        revenue_code_source_value,
        drg_concept_id,
        drg_source_value
    )
    SELECT
        c.master_seq AS cost_id,
        c.master_seq AS cost_event_id,
        CAST(N'Procedure' AS VARCHAR(20)) AS cost_domain_id,
        0 AS cost_type_concept_id,
        NULL AS currency_concept_id,
        c.total_cost AS total_charge,
        c.total_cost,
        NULL, NULL, NULL,
        NULL, NULL, NULL,
        NULL, NULL, NULL, NULL,
        NULL, NULL, NULL,
        NULL, NULL
    FROM @cdm_database.jmdc_proc_norm c
    WHERE c.total_cost IS NOT NULL;

    SET @procedure_rows = @@ROWCOUNT;
END;

SELECT
    CAST('cost_procedure' AS VARCHAR(50)) AS _etl_table,
    @procedure_rows AS _etl_inserted_rows;
GO
