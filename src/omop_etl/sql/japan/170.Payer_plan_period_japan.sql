/**************************************
 Japan: payer_plan_period (minimal)
 POLICY: LOAD - see MAPPING_POLICY.md

 JMDC does not provide a reviewed payer or plan identifier in this extract.
 Reuse the claim-derived observation span and retain payer/plan fields as
 unknown. One person has one deterministic payer period.
**************************************/

DECLARE @inserted_rows BIGINT = 0;

UPDATE ppp
SET
    ppp.payer_plan_period_start_date = op.observation_period_start_date,
    ppp.payer_plan_period_end_date = op.observation_period_end_date
FROM @cdm_database.payer_plan_period ppp
INNER JOIN @cdm_database.observation_period op
  ON op.person_id = ppp.person_id
WHERE ppp.payer_plan_period_start_date <> op.observation_period_start_date
   OR ppp.payer_plan_period_end_date <> op.observation_period_end_date;

IF NOT EXISTS (SELECT TOP (1) 1 FROM @cdm_database.payer_plan_period)
BEGIN
    INSERT INTO @cdm_database.payer_plan_period (
        payer_plan_period_id,
        person_id,
        payer_plan_period_start_date,
        payer_plan_period_end_date,
        payer_concept_id,
        payer_source_value,
        payer_source_concept_id,
        plan_concept_id,
        plan_source_value,
        plan_source_concept_id,
        sponsor_concept_id,
        sponsor_source_value,
        sponsor_source_concept_id,
        family_source_value,
        stop_reason_concept_id,
        stop_reason_source_value,
        stop_reason_source_concept_id
    )
    SELECT
        op.person_id AS payer_plan_period_id,
        op.person_id,
        op.observation_period_start_date,
        op.observation_period_end_date,
        NULL, NULL, NULL,
        NULL, NULL, NULL,
        NULL, NULL, NULL,
        NULL, NULL, NULL, NULL
    FROM @cdm_database.observation_period op
    WHERE op.observation_period_start_date IS NOT NULL
      AND op.observation_period_end_date IS NOT NULL
      AND op.observation_period_end_date >= op.observation_period_start_date;

    SET @inserted_rows = @@ROWCOUNT;
END
ELSE
BEGIN
    INSERT INTO @cdm_database.payer_plan_period (
        payer_plan_period_id,
        person_id,
        payer_plan_period_start_date,
        payer_plan_period_end_date,
        payer_concept_id,
        payer_source_value,
        payer_source_concept_id,
        plan_concept_id,
        plan_source_value,
        plan_source_concept_id,
        sponsor_concept_id,
        sponsor_source_value,
        sponsor_source_concept_id,
        family_source_value,
        stop_reason_concept_id,
        stop_reason_source_value,
        stop_reason_source_concept_id
    )
    SELECT
        op.person_id AS payer_plan_period_id,
        op.person_id,
        op.observation_period_start_date,
        op.observation_period_end_date,
        NULL, NULL, NULL,
        NULL, NULL, NULL,
        NULL, NULL, NULL,
        NULL, NULL, NULL, NULL
    FROM @cdm_database.observation_period op
    WHERE op.observation_period_start_date IS NOT NULL
      AND op.observation_period_end_date IS NOT NULL
      AND op.observation_period_end_date >= op.observation_period_start_date
      AND NOT EXISTS (
          SELECT 1
          FROM @cdm_database.payer_plan_period ppp
          WHERE ppp.payer_plan_period_id = op.person_id
      );

    SET @inserted_rows = @@ROWCOUNT;
END;

SELECT
    CAST('payer_plan_period' AS VARCHAR(50)) AS _etl_table,
    @inserted_rows AS _etl_inserted_rows;
