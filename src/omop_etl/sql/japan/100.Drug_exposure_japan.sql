/**************************************
 Japan (JMDC sample): JP_DRUG -> drug_exposure
 POLICY: LOAD - see DOMAIN_ETL_POLICY.md (drug_exposure)

 500K note:
 - Normalize the large JP_DRUG source into a narrow staging table once.
 - Resolve drug code mappings once per distinct normalized drug code.
 - Mapping priority: exact JMDC source map -> ATC Maps to prefix -> 0.
 - Classification-only ATC concepts are never stored in drug_concept_id.
**************************************/

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    INNER JOIN sys.tables t ON i.object_id = t.object_id
    WHERE i.name = N'IX_concept_voc_code_japan_etl'
      AND t.name = N'concept'
      AND SCHEMA_NAME(t.schema_id) = N'dbo'
)
    CREATE NONCLUSTERED INDEX IX_concept_voc_code_japan_etl
        ON dbo.concept (vocabulary_id, concept_code)
        INCLUDE (concept_id, invalid_reason);
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    INNER JOIN sys.tables t ON i.object_id = t.object_id
    WHERE i.name = N'IX_stcm_source_code_japan_etl'
      AND t.name = N'source_to_concept_map'
      AND SCHEMA_NAME(t.schema_id) = N'dbo'
)
    CREATE NONCLUSTERED INDEX IX_stcm_source_code_japan_etl
        ON dbo.source_to_concept_map (source_code)
        INCLUDE (target_concept_id, invalid_reason, domain_id);
GO

IF OBJECT_ID('@cdm_database.jmdc_drug_norm', 'U') IS NULL
BEGIN
    SELECT
        sm.master_seq,
        CAST(NULLIF(LTRIM(RTRIM(CAST(r.member_id AS VARCHAR(100)))), '') AS VARCHAR(50)) AS member_id_str,
        CAST(NULLIF(LTRIM(RTRIM(CAST(r.claim_id AS VARCHAR(100)))), '') AS VARCHAR(50)) AS claim_id_str,
        TRY_CAST(r.statement_id AS BIGINT) AS statement_id,
        CONVERT(VARCHAR(50), TRY_CAST(r.jmdc_drug_code AS DECIMAL(38, 0))) AS drug_code_str,
        CAST(
            COALESCE(
                CASE WHEN REPLACE(REPLACE(UPPER(LTRIM(RTRIM(CAST(dm.who_atc_code AS VARCHAR(100))))), ' ', ''), '-', '')
                          LIKE '[A-Z][0-9][0-9][A-Z][A-Z][0-9][0-9]'
                     THEN REPLACE(REPLACE(UPPER(LTRIM(RTRIM(CAST(dm.who_atc_code AS VARCHAR(100))))), ' ', ''), '-', '') END,
                CASE WHEN REPLACE(REPLACE(UPPER(LTRIM(RTRIM(CAST(dm.who_atc_name AS VARCHAR(400))))), ' ', ''), '-', '')
                          LIKE '[A-Z][0-9][0-9][A-Z][A-Z][0-9][0-9]'
                     THEN REPLACE(REPLACE(UPPER(LTRIM(RTRIM(CAST(dm.who_atc_name AS VARCHAR(400))))), ' ', ''), '-', '') END,
                CASE WHEN REPLACE(REPLACE(UPPER(LTRIM(RTRIM(CAST(dm.who_atc_code AS VARCHAR(100))))), ' ', ''), '-', '')
                          LIKE '[A-Z][0-9][0-9][A-Z][A-Z]'
                     THEN REPLACE(REPLACE(UPPER(LTRIM(RTRIM(CAST(dm.who_atc_code AS VARCHAR(100))))), ' ', ''), '-', '') END,
                CASE WHEN REPLACE(REPLACE(UPPER(LTRIM(RTRIM(CAST(dm.who_atc_name AS VARCHAR(400))))), ' ', ''), '-', '')
                          LIKE '[A-Z][0-9][0-9][A-Z][A-Z]'
                     THEN REPLACE(REPLACE(UPPER(LTRIM(RTRIM(CAST(dm.who_atc_name AS VARCHAR(400))))), ' ', ''), '-', '') END,
                CASE WHEN REPLACE(REPLACE(UPPER(LTRIM(RTRIM(CAST(dm.who_atc_code AS VARCHAR(100))))), ' ', ''), '-', '')
                          LIKE '[A-Z][0-9][0-9][A-Z]'
                     THEN REPLACE(REPLACE(UPPER(LTRIM(RTRIM(CAST(dm.who_atc_code AS VARCHAR(100))))), ' ', ''), '-', '') END,
                CASE WHEN REPLACE(REPLACE(UPPER(LTRIM(RTRIM(CAST(dm.who_atc_name AS VARCHAR(400))))), ' ', ''), '-', '')
                          LIKE '[A-Z][0-9][0-9][A-Z]'
                     THEN REPLACE(REPLACE(UPPER(LTRIM(RTRIM(CAST(dm.who_atc_name AS VARCHAR(400))))), ' ', ''), '-', '') END,
                CASE WHEN REPLACE(REPLACE(UPPER(LTRIM(RTRIM(CAST(dm.who_atc_code AS VARCHAR(100))))), ' ', ''), '-', '')
                          LIKE '[A-Z][0-9][0-9]'
                     THEN REPLACE(REPLACE(UPPER(LTRIM(RTRIM(CAST(dm.who_atc_code AS VARCHAR(100))))), ' ', ''), '-', '') END,
                CASE WHEN REPLACE(REPLACE(UPPER(LTRIM(RTRIM(CAST(dm.who_atc_name AS VARCHAR(400))))), ' ', ''), '-', '')
                          LIKE '[A-Z][0-9][0-9]'
                     THEN REPLACE(REPLACE(UPPER(LTRIM(RTRIM(CAST(dm.who_atc_name AS VARCHAR(400))))), ' ', ''), '-', '') END,
                UPPER(LTRIM(RTRIM(CONVERT(VARCHAR(50), TRY_CAST(r.jmdc_drug_code AS DECIMAL(38, 0))))))
            ) AS VARCHAR(50)
        ) AS norm_drug_code,
        @cdm_database.fn_jmdc_date(r.date_of_prescription) AS drug_dt,
        TRY_CAST(r.administered_amount AS FLOAT) AS quantity,
        TRY_CAST(r.administered_days AS INT) AS days_supply,
        TRY_CAST(
            REPLACE(
                REPLACE(CAST(r.actual_point AS VARCHAR(100)), CHAR(13), ''),
                ',',
                ''
            )
            AS FLOAT
        ) AS total_cost
    INTO @cdm_database.jmdc_drug_norm
    FROM @raw_database.JP_DRUG r
    LEFT HASH JOIN @raw_database.JP_DRUG_MASTER dm
      ON dm.jmdc_drug_code = r.jmdc_drug_code
    INNER HASH JOIN @cdm_database.SEQ_MASTER sm
      ON sm.source_table = 'DRG'
     AND sm.member_id = CAST(r.member_id AS VARCHAR(50))
     AND sm.claim_id = CAST(r.claim_id AS VARCHAR(50))
     AND ISNULL(sm.statement_id, CONVERT(BIGINT, -9223372036854775808))
         = ISNULL(
             TRY_CAST(r.statement_id AS BIGINT),
             CONVERT(BIGINT, -9223372036854775808)
         )
    OPTION (RECOMPILE, MAXDOP 4);
END;
GO

IF OBJECT_ID('@cdm_database.jmdc_drug_code_to_concept', 'U') IS NOT NULL
   AND (
       COL_LENGTH(
           '@cdm_database.jmdc_drug_code_to_concept',
           'drug_code_str'
       ) IS NULL
       OR COL_LENGTH(
           '@cdm_database.jmdc_drug_code_to_concept',
           'mapping_version'
       ) IS NULL
   )
    DROP TABLE @cdm_database.jmdc_drug_code_to_concept;
GO

IF OBJECT_ID('@cdm_database.jmdc_drug_code_to_concept', 'U') IS NULL
BEGIN
    ;WITH codes AS (
        SELECT DISTINCT drug_code_str, norm_drug_code
        FROM @cdm_database.jmdc_drug_norm
        WHERE drug_code_str IS NOT NULL AND drug_code_str <> ''
    ),
    candidate_keys AS (
        SELECT
            c.drug_code_str,
            c.norm_drug_code,
            k.source_code,
            k.priority,
            k.require_drug_source_domain
        FROM codes c
        CROSS APPLY (VALUES
            (c.drug_code_str, 0, 1),
            (c.norm_drug_code, 1, 0),
            (
                CASE WHEN LEN(c.norm_drug_code) > 5
                     THEN LEFT(c.norm_drug_code, 5) END,
                2,
                1
            ),
            (
                CASE WHEN LEN(c.norm_drug_code) > 4
                     THEN LEFT(c.norm_drug_code, 4) END,
                3,
                1
            ),
            (
                CASE WHEN LEN(c.norm_drug_code) > 3
                     THEN LEFT(c.norm_drug_code, 3) END,
                4,
                1
            )
        ) k(source_code, priority, require_drug_source_domain)
        WHERE k.source_code IS NOT NULL
          AND k.source_code <> ''
    ),
    ranked_maps AS (
        SELECT
            ck.drug_code_str,
            m.target_concept_id,
            ROW_NUMBER() OVER (
                PARTITION BY ck.drug_code_str
                ORDER BY
                    ck.priority,
                    CASE
                        WHEN ck.priority = 1 THEN 1
                        WHEN LOWER(m.domain_id) IN (N'drug', N'ingredient')
                        THEN 1
                        ELSE 2
                    END,
                    CASE
                        WHEN ck.priority = 0
                         AND m.target_vocabulary_id LIKE N'RxNorm%'
                        THEN 1
                        WHEN ck.priority = 0 THEN 2
                        ELSE 1
                    END,
                    m.target_concept_id
            ) AS rn
        FROM candidate_keys ck
        INNER JOIN @cdm_database.source_to_concept_map m
          ON m.source_code = ck.source_code
         AND m.invalid_reason IS NULL
        INNER JOIN @cdm_database.CONCEPT target
          ON target.concept_id = m.target_concept_id
         AND target.standard_concept = 'S'
         AND target.domain_id = 'Drug'
         AND target.invalid_reason IS NULL
        WHERE ck.require_drug_source_domain = 0
           OR LOWER(m.domain_id) IN (N'drug', N'ingredient')
           OR m.target_vocabulary_id LIKE N'RxNorm%'
    )
    SELECT
        c.drug_code_str,
        c.norm_drug_code,
        ISNULL(rm.target_concept_id, 0) AS target_concept_id,
        CAST('2.0' AS VARCHAR(20)) AS mapping_version
    INTO @cdm_database.jmdc_drug_code_to_concept
    FROM codes c
    LEFT JOIN ranked_maps rm
      ON rm.drug_code_str = c.drug_code_str
     AND rm.rn = 1
    OPTION (RECOMPILE, MAXDOP 4);

    CREATE UNIQUE NONCLUSTERED INDEX IX_jmdc_drug_code_to_concept
        ON @cdm_database.jmdc_drug_code_to_concept (drug_code_str);
END;
GO

DECLARE @inserted_rows BIGINT = 0;

IF NOT EXISTS (SELECT TOP (1) 1 FROM @cdm_database.drug_exposure)
BEGIN
    INSERT INTO @cdm_database.drug_exposure (
        drug_exposure_id, person_id, drug_concept_id,
        drug_exposure_start_date, drug_exposure_end_date,
        drug_type_concept_id, quantity, days_supply, visit_occurrence_id,
        drug_source_value, drug_source_concept_id, master_seq
    )
    SELECT
        r.master_seq AS drug_exposure_id,
        p.person_id,
        ISNULL(cm.target_concept_id, 0) AS drug_concept_id,
        dt.start_date AS drug_exposure_start_date,
        CASE
            WHEN r.days_supply BETWEEN 1 AND 36500
             AND dt.start_date <= DATEADD(
                     DAY,
                     1 - r.days_supply,
                     CONVERT(DATE, '99991231', 112)
                 )
            THEN DATEADD(DAY, r.days_supply - 1, dt.start_date)
            ELSE dt.start_date
        END AS drug_exposure_end_date,
        581452 AS drug_type_concept_id,
        r.quantity,
        r.days_supply,
        v.visit_occurrence_id,
        r.drug_code_str AS drug_source_value,
        NULL AS drug_source_concept_id,
        r.master_seq
    FROM @cdm_database.jmdc_drug_norm r
    INNER HASH JOIN @cdm_database.person p
      ON p.person_source_value = r.member_id_str
    INNER HASH JOIN @cdm_database.visit_occurrence v
      ON v.person_id = p.person_id
     AND v.visit_source_value = r.claim_id_str
    LEFT HASH JOIN @cdm_database.jmdc_drug_code_to_concept cm
      ON cm.drug_code_str = r.drug_code_str
    CROSS APPLY (
        SELECT CAST(
            COALESCE(r.drug_dt, v.visit_start_date, v.visit_end_date)
            AS DATE
        ) AS start_date
    ) dt
    WHERE dt.start_date IS NOT NULL
    OPTION (RECOMPILE, MAXDOP 4);

    SET @inserted_rows = @@ROWCOUNT;
END
ELSE
BEGIN
    INSERT INTO @cdm_database.drug_exposure (
        drug_exposure_id, person_id, drug_concept_id,
        drug_exposure_start_date, drug_exposure_end_date,
        drug_type_concept_id, quantity, days_supply, visit_occurrence_id,
        drug_source_value, drug_source_concept_id, master_seq
    )
    SELECT
        r.master_seq AS drug_exposure_id,
        p.person_id,
        ISNULL(cm.target_concept_id, 0) AS drug_concept_id,
        dt.start_date AS drug_exposure_start_date,
        CASE
            WHEN r.days_supply BETWEEN 1 AND 36500
             AND dt.start_date <= DATEADD(
                     DAY,
                     1 - r.days_supply,
                     CONVERT(DATE, '99991231', 112)
                 )
            THEN DATEADD(DAY, r.days_supply - 1, dt.start_date)
            ELSE dt.start_date
        END AS drug_exposure_end_date,
        581452 AS drug_type_concept_id,
        r.quantity,
        r.days_supply,
        v.visit_occurrence_id,
        r.drug_code_str AS drug_source_value,
        NULL AS drug_source_concept_id,
        r.master_seq
    FROM @cdm_database.jmdc_drug_norm r
    INNER HASH JOIN @cdm_database.person p
      ON p.person_source_value = r.member_id_str
    INNER HASH JOIN @cdm_database.visit_occurrence v
      ON v.person_id = p.person_id
     AND v.visit_source_value = r.claim_id_str
    LEFT HASH JOIN @cdm_database.jmdc_drug_code_to_concept cm
      ON cm.drug_code_str = r.drug_code_str
    CROSS APPLY (
        SELECT CAST(
            COALESCE(r.drug_dt, v.visit_start_date, v.visit_end_date)
            AS DATE
        ) AS start_date
    ) dt
    WHERE dt.start_date IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM @cdm_database.drug_exposure de
          WHERE de.drug_exposure_id = r.master_seq
      )
    OPTION (RECOMPILE, MAXDOP 4);

    SET @inserted_rows = @@ROWCOUNT;
END;

SELECT CAST('drug_exposure' AS VARCHAR(50)) AS _etl_table,
       @inserted_rows AS _etl_inserted_rows;
