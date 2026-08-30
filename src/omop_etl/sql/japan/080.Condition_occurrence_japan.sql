/**************************************
 Japan: JP_DIAGNOSIS -> CONDITION_OCCURRENCE
 POLICY: LOAD - see MAPPING_POLICY.md

 Relational 500K policy:
 - Normalize the wide RAW source once into a narrow staging table.
 - Attach SEQ_MASTER once while staging and retain that deterministic source ID.
 - Resolve ICD-10 mappings once per distinct normalized code.
 - Use the source master_seq as condition_occurrence_id.
**************************************/

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    INNER JOIN sys.tables t ON i.object_id = t.object_id
    WHERE i.name = N'IX_stcm_source_code_japan_etl'
      AND t.name = N'source_to_concept_map'
      AND SCHEMA_NAME(t.schema_id) = N'dbo'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_stcm_source_code_japan_etl
        ON dbo.source_to_concept_map (source_code)
        INCLUDE (target_concept_id, invalid_reason, domain_id);
END;
GO

IF OBJECT_ID('@cdm_database.jmdc_diag_norm', 'U') IS NULL
BEGIN
    SELECT
        sm.master_seq,
        CAST(
            NULLIF(LTRIM(RTRIM(CAST(d.member_id AS VARCHAR(100)))), '')
            AS VARCHAR(50)
        ) AS member_id_str,
        CAST(
            NULLIF(LTRIM(RTRIM(CAST(d.claim_id AS VARCHAR(100)))), '')
            AS VARCHAR(50)
        ) AS claim_id_str,
        TRY_CAST(d.statement_id AS BIGINT) AS statement_id,
        CAST(
            NULLIF(
                LTRIM(RTRIM(CAST(d.icd10_level4_code AS VARCHAR(100)))),
                ''
            )
            AS VARCHAR(20)
        ) AS icd10_level4_code,
        CAST(
            CASE
                WHEN REPLACE(
                         REPLACE(
                             UPPER(LTRIM(RTRIM(CAST(
                                 d.icd10_level4_code AS VARCHAR(100)
                             )))),
                             '-',
                             ''
                         ),
                         '.',
                         ''
                     ) LIKE '[A-Z][0-9][0-9][0-9]'
                THEN LEFT(
                         REPLACE(
                             REPLACE(
                                 UPPER(LTRIM(RTRIM(CAST(
                                     d.icd10_level4_code AS VARCHAR(100)
                                 )))),
                                 '-',
                                 ''
                             ),
                             '.',
                             ''
                         ),
                         3
                     )
                     + '.'
                     + RIGHT(
                         REPLACE(
                             REPLACE(
                                 UPPER(LTRIM(RTRIM(CAST(
                                     d.icd10_level4_code AS VARCHAR(100)
                                 )))),
                                 '-',
                                 ''
                             ),
                             '.',
                             ''
                         ),
                         1
                     )
                ELSE REPLACE(
                         UPPER(LTRIM(RTRIM(CAST(
                             d.icd10_level4_code AS VARCHAR(100)
                         )))),
                         '-',
                         ''
                     )
            END
            AS VARCHAR(20)
        ) AS norm_code,
        @cdm_database.fn_jmdc_date(
            d.date_of_medical_care_start
        ) AS cond_date,
        TRY_CAST(d.main_disease_flag AS INT) AS main_disease_flag
    INTO @cdm_database.jmdc_diag_norm
    FROM @raw_database.JP_DIAGNOSIS d
    INNER HASH JOIN @cdm_database.SEQ_MASTER sm
      ON sm.source_table = 'DIA'
     AND sm.member_id = CAST(d.member_id AS VARCHAR(50))
     AND sm.claim_id = CAST(d.claim_id AS VARCHAR(50))
     AND ISNULL(sm.statement_id, CONVERT(BIGINT, -9223372036854775808))
         = ISNULL(
             TRY_CAST(d.statement_id AS BIGINT),
             CONVERT(BIGINT, -9223372036854775808)
         )
    WHERE d.icd10_level4_code IS NOT NULL
      AND RTRIM(d.icd10_level4_code) <> ''
    OPTION (RECOMPILE, MAXDOP 4);
END;
GO

IF OBJECT_ID('@cdm_database.jmdc_icd10_to_concept', 'U') IS NULL
BEGIN
    ;WITH codes AS (
        SELECT DISTINCT norm_code
        FROM @cdm_database.jmdc_diag_norm
        WHERE norm_code IS NOT NULL
          AND norm_code <> ''
    )
    SELECT
        c.norm_code,
        ISNULL(cm_map.target_concept_id, 0) AS target_concept_id
    INTO @cdm_database.jmdc_icd10_to_concept
    FROM codes c
    OUTER APPLY (
        SELECT TOP (1)
            cm.target_concept_id
        FROM @cdm_database.source_to_concept_map cm
        WHERE cm.source_code = c.norm_code
          AND cm.invalid_reason IS NULL
          AND LOWER(cm.domain_id) = 'condition'
        ORDER BY cm.target_concept_id
    ) cm_map;

    CREATE UNIQUE NONCLUSTERED INDEX IX_jmdc_icd10_to_concept
        ON @cdm_database.jmdc_icd10_to_concept (norm_code);
END;
GO

/* Never retain a cross-domain or invalid standard concept. */
UPDATE m
SET target_concept_id = 0
FROM @cdm_database.jmdc_icd10_to_concept m
LEFT JOIN @cdm_database.CONCEPT c
  ON c.concept_id = m.target_concept_id
WHERE m.target_concept_id <> 0
  AND (
      c.concept_id IS NULL
      OR c.standard_concept <> 'S'
      OR c.invalid_reason IS NOT NULL
      OR LOWER(c.domain_id) <> 'condition'
  );
GO

DECLARE @inserted_rows BIGINT = 0;

IF NOT EXISTS (SELECT TOP (1) 1 FROM @cdm_database.condition_occurrence)
BEGIN
    INSERT INTO @cdm_database.condition_occurrence (
        condition_occurrence_id, person_id, condition_concept_id,
        condition_start_date, condition_end_date, condition_type_concept_id,
        visit_occurrence_id, condition_source_value,
        condition_source_concept_id, master_seq
    )
    SELECT
        d.master_seq AS condition_occurrence_id,
        p.person_id,
        ISNULL(cm.target_concept_id, 0) AS condition_concept_id,
        CAST(
            COALESCE(d.cond_date, v.visit_start_date, v.visit_end_date)
            AS DATE
        ) AS condition_start_date,
        CAST(
            COALESCE(d.cond_date, v.visit_start_date, v.visit_end_date)
            AS DATE
        ) AS condition_end_date,
        CASE
            WHEN d.main_disease_flag = 1 THEN 44786627
            ELSE 44786629
        END AS condition_type_concept_id,
        v.visit_occurrence_id,
        d.icd10_level4_code AS condition_source_value,
        NULL AS condition_source_concept_id,
        d.master_seq
    FROM @cdm_database.jmdc_diag_norm d
    INNER HASH JOIN @cdm_database.person p
      ON p.person_source_value = d.member_id_str
    INNER HASH JOIN @cdm_database.visit_occurrence v
      ON v.person_id = p.person_id
     AND v.visit_source_value = d.claim_id_str
    LEFT HASH JOIN @cdm_database.jmdc_icd10_to_concept cm
      ON cm.norm_code = d.norm_code
    WHERE COALESCE(
              d.cond_date,
              v.visit_start_date,
              v.visit_end_date
          ) IS NOT NULL
    OPTION (RECOMPILE, MAXDOP 4);

    SET @inserted_rows = @@ROWCOUNT;
END
ELSE
BEGIN
    INSERT INTO @cdm_database.condition_occurrence (
        condition_occurrence_id, person_id, condition_concept_id,
        condition_start_date, condition_end_date, condition_type_concept_id,
        visit_occurrence_id, condition_source_value,
        condition_source_concept_id, master_seq
    )
    SELECT
        d.master_seq AS condition_occurrence_id,
        p.person_id,
        ISNULL(cm.target_concept_id, 0) AS condition_concept_id,
        CAST(
            COALESCE(d.cond_date, v.visit_start_date, v.visit_end_date)
            AS DATE
        ) AS condition_start_date,
        CAST(
            COALESCE(d.cond_date, v.visit_start_date, v.visit_end_date)
            AS DATE
        ) AS condition_end_date,
        CASE
            WHEN d.main_disease_flag = 1 THEN 44786627
            ELSE 44786629
        END AS condition_type_concept_id,
        v.visit_occurrence_id,
        d.icd10_level4_code AS condition_source_value,
        NULL AS condition_source_concept_id,
        d.master_seq
    FROM @cdm_database.jmdc_diag_norm d
    INNER HASH JOIN @cdm_database.person p
      ON p.person_source_value = d.member_id_str
    INNER HASH JOIN @cdm_database.visit_occurrence v
      ON v.person_id = p.person_id
     AND v.visit_source_value = d.claim_id_str
    LEFT HASH JOIN @cdm_database.jmdc_icd10_to_concept cm
      ON cm.norm_code = d.norm_code
    WHERE COALESCE(
              d.cond_date,
              v.visit_start_date,
              v.visit_end_date
          ) IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM @cdm_database.condition_occurrence co
          WHERE co.condition_occurrence_id = d.master_seq
      )
    OPTION (RECOMPILE, MAXDOP 4);

    SET @inserted_rows = @@ROWCOUNT;
END;

SELECT CAST('condition_occurrence' AS VARCHAR(50)) AS _etl_table,
       @inserted_rows AS _etl_inserted_rows;
