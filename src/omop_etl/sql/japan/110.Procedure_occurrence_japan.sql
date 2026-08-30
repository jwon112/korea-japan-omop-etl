/**************************************
 Japan: JP_PROCEDURE -> procedure_occurrence
 POLICY: LOAD - see MAPPING_POLICY.md

 Relational 500K policy:
 - Normalize the large source once and retain master_seq and cost.
 - Resolve policy and mappings once per distinct code/version.
 - Administrative fee rows remain source events with concept_id = 0.
 - Only active standard Procedure concepts enter procedure_concept_id.
 - Use master_seq as the deterministic procedure_occurrence_id.
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

IF OBJECT_ID('@cdm_database.jmdc_proc_code_to_concept', 'U') IS NULL
BEGIN
    CREATE TABLE @cdm_database.jmdc_proc_code_to_concept (
        country              VARCHAR(10)  NOT NULL DEFAULT 'JP',
        source_code          VARCHAR(50)  NOT NULL,
        source_code_system   VARCHAR(50)  NOT NULL DEFAULT 'JMDC_STD_PROC',
        target_vocabulary_id VARCHAR(20)  NOT NULL,
        target_concept_code  VARCHAR(50)  NOT NULL,
        mapping_type         VARCHAR(50)  NOT NULL,
        mapping_version      VARCHAR(20)  NOT NULL DEFAULT '1.0',
        note                 VARCHAR(500) NULL,
        CONSTRAINT PK_jmdc_proc_code_to_concept
            PRIMARY KEY (
                country,
                source_code,
                source_code_system,
                mapping_version
            )
    );
END;
GO

/* 160095710 is venipuncture, not the old HBsAb LOINC seed. */
DELETE FROM @cdm_database.jmdc_proc_code_to_concept
WHERE country = N'JP'
  AND source_code = N'160095710'
  AND source_code_system = N'JMDC_STD_PROC'
  AND target_vocabulary_id = N'LOINC'
  AND target_concept_code = N'75409-3';
GO

MERGE @cdm_database.jmdc_proc_code_to_concept AS tgt
USING (
    SELECT
        country,
        source_code,
        source_code_system,
        target_vocabulary_id,
        target_concept_code,
        mapping_type,
        mapping_version,
        note
    FROM (VALUES
        (N'JP', N'160022610', N'JMDC_STD_PROC', N'LOINC', N'1742-6',  N'clinical_test', N'1.0', N'ALT; master name match'),
        (N'JP', N'160022510', N'JMDC_STD_PROC', N'LOINC', N'1920-8',  N'clinical_test', N'1.0', N'AST'),
        (N'JP', N'160019210', N'JMDC_STD_PROC', N'LOINC', N'2160-0',  N'clinical_test', N'1.0', N'creatinine'),
        (N'JP', N'160019010', N'JMDC_STD_PROC', N'LOINC', N'3094-0',  N'clinical_test', N'1.0', N'BUN'),
        (N'JP', N'160020410', N'JMDC_STD_PROC', N'LOINC', N'2324-2',  N'clinical_test', N'1.0', N'gamma-GT'),
        (N'JP', N'160021110', N'JMDC_STD_PROC', N'LOINC', N'2951-2',  N'clinical_test', N'1.0', N'sodium (Na)'),
        (N'JP', N'160010010', N'JMDC_STD_PROC', N'LOINC', N'4548-4',  N'clinical_test', N'1.0', N'HbA1c'),
        (N'JP', N'160019410', N'JMDC_STD_PROC', N'LOINC', N'2345-7',  N'clinical_test', N'1.0', N'glucose'),
        (N'JP', N'160021410', N'JMDC_STD_PROC', N'LOINC', N'2823-3',  N'clinical_test', N'1.0', N'potassium'),
        (N'JP', N'160020910', N'JMDC_STD_PROC', N'LOINC', N'2571-8',  N'clinical_test', N'1.0', N'triglyceride'),
        (N'JP', N'160017010', N'JMDC_STD_PROC', N'LOINC', N'1975-2',  N'clinical_test', N'1.0', N'total bilirubin'),
        (N'JP', N'160019310', N'JMDC_STD_PROC', N'LOINC', N'3084-1',  N'clinical_test', N'1.0', N'uric acid'),
        (N'JP', N'160017410', N'JMDC_STD_PROC', N'LOINC', N'2885-2',  N'clinical_test', N'1.0', N'total protein'),
        (N'JP', N'160008010', N'JMDC_STD_PROC', N'LOINC', N'58410-2', N'clinical_test', N'1.0', N'CBC panel'),
        (N'JP', N'160019510', N'JMDC_STD_PROC', N'LOINC', N'2532-0',  N'clinical_test', N'1.0', N'LD'),
        (N'JP', N'160020010', N'JMDC_STD_PROC', N'LOINC', N'6768-6',  N'clinical_test', N'1.0', N'ALP'),
        (N'JP', N'160018910', N'JMDC_STD_PROC', N'LOINC', N'1751-7',  N'clinical_test', N'1.0', N'albumin'),
        (N'JP', N'160167250', N'JMDC_STD_PROC', N'LOINC', N'18262-6', N'clinical_test', N'1.0', N'LDL cholesterol'),
        (N'JP', N'160000310', N'JMDC_STD_PROC', N'LOINC', N'24357-6', N'clinical_test', N'1.0', N'urinalysis'),
        (N'JP', N'160020610', N'JMDC_STD_PROC', N'LOINC', N'2157-6',  N'clinical_test', N'1.0', N'creatine kinase (CK)'),
        (N'JP', N'160054710', N'JMDC_STD_PROC', N'LOINC', N'1988-5',  N'clinical_test', N'1.0', N'C reactive protein (CRP)'),
        (N'JP', N'160023410', N'JMDC_STD_PROC', N'LOINC', N'2085-9',  N'clinical_test', N'1.0', N'HDL cholesterol'),
        (N'JP', N'160022410', N'JMDC_STD_PROC', N'LOINC', N'2093-3',  N'clinical_test', N'1.0', N'total cholesterol'),
        (N'JP', N'160020310', N'JMDC_STD_PROC', N'LOINC', N'1798-8',  N'clinical_test', N'1.0', N'amylase'),
        (N'JP', N'160021510', N'JMDC_STD_PROC', N'LOINC', N'17861-6', N'clinical_test', N'1.0', N'calcium'),
        (N'JP', N'160017110', N'JMDC_STD_PROC', N'LOINC', N'1968-7',  N'clinical_test', N'1.0', N'direct bilirubin'),
        (N'JP', N'160012010', N'JMDC_STD_PROC', N'LOINC', N'5902-2',  N'clinical_test', N'1.0', N'prothrombin time (PT)'),
        (N'JP', N'160021810', N'JMDC_STD_PROC', N'LOINC', N'2777-1',  N'clinical_test', N'1.0', N'inorganic phosphate'),
        (N'JP', N'160020210', N'JMDC_STD_PROC', N'LOINC', N'2098-2',  N'clinical_test', N'1.0', N'cholinesterase (ChE)'),
        (N'JP', N'160031710', N'JMDC_STD_PROC', N'LOINC', N'3016-3',  N'clinical_test', N'1.0', N'thyroid-stimulating hormone (TSH)'),
        (N'JP', N'160012310', N'JMDC_STD_PROC', N'LOINC', N'3173-2',  N'clinical_test', N'1.0', N'activated partial thromboplastin time (APTT)'),
        (N'JP', N'160033310', N'JMDC_STD_PROC', N'LOINC', N'3024-7',  N'clinical_test', N'1.0', N'free thyroxine (FT4)'),
        (N'JP', N'160033210', N'JMDC_STD_PROC', N'LOINC', N'3051-0',  N'clinical_test', N'1.0', N'free triiodothyronine (FT3)'),
        (N'JP', N'160095710', N'JMDC_STD_PROC', N'SNOMED', N'28520004', N'clinical_procedure', N'1.0', N'blood sampling (vein); venipuncture'),
        (N'JP', N'170027910', N'JMDC_STD_PROC', N'SNOMED', N'168537006', N'diagnostic_imaging', N'1.0', N'plain radiography; generic plain X-ray'),
        (N'JP', N'170015410', N'JMDC_STD_PROC', N'SNOMED', N'77477000', N'diagnostic_imaging', N'1.0', N'computerized tomography; generic CT'),
        (N'JP', N'160068410', N'JMDC_STD_PROC', N'SNOMED', N'447113005', N'clinical_procedure', N'1.0', N'ECG at least 12 leads'),
        (N'JP', N'140022710', N'JMDC_STD_PROC', N'SNOMED', N'56251003', N'clinical_procedure', N'1.0', N'nebulizer'),
        (N'JP', N'140022810', N'JMDC_STD_PROC', N'SNOMED', N'56251003', N'clinical_procedure', N'1.0', N'ultrasonic nebulizer'),
        (N'JP', N'180031010', N'JMDC_STD_PROC', N'SNOMED', N'75516001', N'clinical_procedure', N'1.0', N'outpatient psychotherapy under 30 minutes'),
        (N'JP', N'130003810', N'JMDC_STD_PROC', N'SNOMED', N'433853007', N'clinical_procedure', N'1.0', N'intravenous drip infusion'),
        (N'JP', N'130009310', N'JMDC_STD_PROC', N'SNOMED', N'433853007', N'clinical_procedure', N'1.0', N'intravenous drip infusion'),
        (N'JP', N'130003510', N'JMDC_STD_PROC', N'SNOMED', N'43060002', N'clinical_procedure', N'1.0', N'intravenous injection'),
        (N'JP', N'130005310', N'JMDC_STD_PROC', N'SNOMED', N'27813003', N'clinical_procedure', N'1.0', N'intra-articular injection'),
        (N'JP', N'180032710', N'JMDC_STD_PROC', N'SNOMED', N'52052004', N'clinical_procedure', N'1.0', N'orthopedic rehabilitation [1]'),
        (N'JP', N'180027810', N'JMDC_STD_PROC', N'SNOMED', N'52052004', N'clinical_procedure', N'1.0', N'orthopedic rehabilitation [1]'),
        (N'JP', N'180027910', N'JMDC_STD_PROC', N'SNOMED', N'52052004', N'clinical_procedure', N'1.0', N'orthopedic rehabilitation [2]'),
        (N'JP', N'160084510', N'JMDC_STD_PROC', N'SNOMED', N'55468007', N'clinical_procedure', N'1.0', N'slit-lamp microscopy anterior segment'),
        (N'JP', N'160084650', N'JMDC_STD_PROC', N'SNOMED', N'55468007', N'clinical_procedure', N'1.0', N'slit-lamp microscopy with staining'),
        (N'JP', N'160081130', N'JMDC_STD_PROC', N'SNOMED', N'53524009', N'clinical_procedure', N'1.0', N'detailed ophthalmoscopy bilateral'),
        (N'JP', N'160081010', N'JMDC_STD_PROC', N'SNOMED', N'53524009', N'clinical_procedure', N'1.0', N'detailed ophthalmoscopy unilateral'),
        (N'JP', N'160208010', N'JMDC_STD_PROC', N'SNOMED', N'252886007', N'clinical_procedure', N'1.0', N'refraction assessment'),
        (N'JP', N'160183310', N'JMDC_STD_PROC', N'SNOMED', N'20067007', N'clinical_procedure', N'1.0', N'ocular fundus photography'),
        (N'JP', N'140000610', N'JMDC_STD_PROC', N'SNOMED', N'182531007', N'clinical_procedure', N'1.0', N'dressing of wound under 100 cm2'),
        (N'JP', N'170020110', N'JMDC_STD_PROC', N'SNOMED', N'113091000', N'diagnostic_imaging', N'1.0', N'generic MRI'),
        (N'JP', N'160082210', N'JMDC_STD_PROC', N'SNOMED', N'103752008', N'clinical_procedure', N'1.0', N'generic perimetry'),
        (N'JP', N'160081610', N'JMDC_STD_PROC', N'SNOMED', N'55468007', N'clinical_procedure', N'1.0', N'slit-lamp microscopy anterior and posterior segments'),
        (N'JP', N'140012410', N'JMDC_STD_PROC', N'SNOMED', N'27777002', N'clinical_procedure', N'1.0', N'wart cryotherapy')
    ) AS v(
        country,
        source_code,
        source_code_system,
        target_vocabulary_id,
        target_concept_code,
        mapping_type,
        mapping_version,
        note
    )
) AS src
ON tgt.country = src.country
AND tgt.source_code = src.source_code
AND tgt.source_code_system = src.source_code_system
AND tgt.mapping_version = src.mapping_version
WHEN MATCHED THEN
    UPDATE SET
        tgt.target_vocabulary_id = src.target_vocabulary_id,
        tgt.target_concept_code = src.target_concept_code,
        tgt.mapping_type = src.mapping_type,
        tgt.note = src.note
WHEN NOT MATCHED THEN
    INSERT (
        country,
        source_code,
        source_code_system,
        target_vocabulary_id,
        target_concept_code,
        mapping_type,
        mapping_version,
        note
    )
    VALUES (
        src.country,
        src.source_code,
        src.source_code_system,
        src.target_vocabulary_id,
        src.target_concept_code,
        src.mapping_type,
        src.mapping_version,
        src.note
    );
GO

IF OBJECT_ID('@cdm_database.jmdc_proc_norm', 'U') IS NOT NULL
   AND (
       COL_LENGTH('@cdm_database.jmdc_proc_norm', 'master_seq') IS NULL
       OR COL_LENGTH('@cdm_database.jmdc_proc_norm', 'total_cost') IS NULL
   )
BEGIN
    DROP TABLE @cdm_database.jmdc_proc_norm;
END;
GO

IF OBJECT_ID('@cdm_database.jmdc_proc_norm', 'U') IS NULL
BEGIN
    SELECT
        sm.master_seq,
        CAST(
            NULLIF(LTRIM(RTRIM(CAST(pr.member_id AS VARCHAR(100)))), '')
            AS VARCHAR(50)
        ) AS member_id_str,
        CAST(
            NULLIF(LTRIM(RTRIM(CAST(pr.claim_id AS VARCHAR(100)))), '')
            AS VARCHAR(50)
        ) AS claim_id_str,
        TRY_CAST(pr.statement_id AS BIGINT) AS statement_id,
        CAST(
            COALESCE(
                CONVERT(
                    VARCHAR(50),
                    TRY_CONVERT(
                        DECIMAL(38, 0),
                        NULLIF(
                            LTRIM(RTRIM(CAST(
                                pr.standardized_procedure_code
                                AS VARCHAR(100)
                            ))),
                            ''
                        )
                    )
                ),
                NULLIF(
                    UPPER(LTRIM(RTRIM(CAST(
                        pr.standardized_procedure_code AS VARCHAR(100)
                    )))),
                    ''
                )
            )
            AS VARCHAR(50)
        ) AS proc_code_str,
        CAST(
            COALESCE(
                CONVERT(
                    VARCHAR(50),
                    TRY_CONVERT(
                        DECIMAL(38, 0),
                        NULLIF(
                            LTRIM(RTRIM(CAST(
                                pr.standardized_procedure_version
                                AS VARCHAR(100)
                            ))),
                            ''
                        )
                    )
                ),
                NULLIF(
                    UPPER(LTRIM(RTRIM(CAST(
                        pr.standardized_procedure_version AS VARCHAR(100)
                    )))),
                    ''
                )
            )
            AS VARCHAR(50)
        ) AS proc_version_str,
        @cdm_database.fn_jmdc_date(
            pr.date_of_procedure
        ) AS proc_dt,
        TRY_CAST(
            REPLACE(
                REPLACE(CAST(pr.actual_point AS VARCHAR(100)), CHAR(13), ''),
                ',',
                ''
            )
            AS FLOAT
        ) AS total_cost
    INTO @cdm_database.jmdc_proc_norm
    FROM @raw_database.JP_PROCEDURE pr
    INNER HASH JOIN @cdm_database.SEQ_MASTER sm
      ON sm.source_table = 'PRC'
     AND sm.member_id = CAST(pr.member_id AS VARCHAR(50))
     AND sm.claim_id = CAST(pr.claim_id AS VARCHAR(50))
     AND ISNULL(
             sm.statement_id,
             CONVERT(BIGINT, -9223372036854775808)
         )
         = ISNULL(
             TRY_CAST(pr.statement_id AS BIGINT),
             CONVERT(BIGINT, -9223372036854775808)
         )
    OPTION (RECOMPILE, MAXDOP 4);
END;
GO

IF OBJECT_ID('@cdm_database.jmdc_proc_code_map', 'U') IS NOT NULL
   AND (
       COL_LENGTH('@cdm_database.jmdc_proc_code_map', 'proc_version_str') IS NULL
       OR COL_LENGTH('@cdm_database.jmdc_proc_code_map', 'is_admin_fee') IS NULL
   )
BEGIN
    DROP TABLE @cdm_database.jmdc_proc_code_map;
END;
GO

IF OBJECT_ID('@cdm_database.jmdc_proc_code_map', 'U') IS NULL
BEGIN
    ;WITH codes AS (
        SELECT DISTINCT
            proc_code_str,
            proc_version_str
        FROM @cdm_database.jmdc_proc_norm
        WHERE proc_code_str IS NOT NULL
          AND proc_code_str <> ''
    ),
    master_base AS (
        SELECT
            CAST(
                COALESCE(
                    CONVERT(
                        VARCHAR(50),
                        TRY_CONVERT(
                            DECIMAL(38, 0),
                            NULLIF(
                                LTRIM(RTRIM(CAST(
                                    pm.standardized_procedure_code
                                    AS VARCHAR(100)
                                ))),
                                ''
                            )
                        )
                    ),
                    NULLIF(
                        UPPER(LTRIM(RTRIM(CAST(
                            pm.standardized_procedure_code AS VARCHAR(100)
                        )))),
                        ''
                    )
                )
                AS VARCHAR(50)
            ) AS proc_code_str,
            CAST(
                COALESCE(
                    CONVERT(
                        VARCHAR(50),
                        TRY_CONVERT(
                            DECIMAL(38, 0),
                            NULLIF(
                                LTRIM(RTRIM(CAST(
                                    pm.standardized_procedure_version
                                    AS VARCHAR(100)
                                ))),
                                ''
                            )
                        )
                    ),
                    NULLIF(
                        UPPER(LTRIM(RTRIM(CAST(
                            pm.standardized_procedure_version AS VARCHAR(100)
                        )))),
                        ''
                    )
                )
                AS VARCHAR(50)
            ) AS proc_version_str,
            CAST(pm.standardized_procedure_name AS NVARCHAR(500))
                AS procedure_name,
            CAST(pm.procedure_category_medium_class AS NVARCHAR(500))
                AS medium_class,
            CAST(pm.procedure_category_small_classi AS NVARCHAR(500))
                AS small_class,
            COALESCE(
                NULLIF(UPPER(LTRIM(RTRIM(CAST(pm.icd9cm_level3 AS VARCHAR(100))))), ''),
                NULLIF(UPPER(LTRIM(RTRIM(CAST(pm.icd9cm_level2 AS VARCHAR(100))))), ''),
                NULLIF(UPPER(LTRIM(RTRIM(CAST(pm.icd9cm_level1 AS VARCHAR(100))))), '')
            ) AS icd9proc_code
        FROM @raw_database.JP_PROCEDURE_MASTER pm
    ),
    master_ranked AS (
        SELECT
            mb.*,
            ROW_NUMBER() OVER (
                PARTITION BY mb.proc_code_str, mb.proc_version_str
                ORDER BY
                    CASE WHEN mb.procedure_name IS NULL THEN 1 ELSE 0 END,
                    mb.procedure_name
            ) AS rn
        FROM master_base mb
    )
    SELECT
        c.proc_code_str,
        c.proc_version_str,
        CAST(pol.is_admin_fee AS BIT) AS is_admin_fee,
        CAST(
            CASE
                WHEN pol.is_admin_fee = 1 THEN 0
                ELSE COALESCE(xw.concept_id, cm_try.target_concept_id, 0)
            END
            AS INT
        ) AS target_concept_id
    INTO @cdm_database.jmdc_proc_code_map
    FROM codes c
    LEFT JOIN master_ranked pm
      ON pm.proc_code_str = c.proc_code_str
     AND ISNULL(pm.proc_version_str, '') = ISNULL(c.proc_version_str, '')
     AND pm.rn = 1
    OUTER APPLY (
        SELECT CASE
            WHEN pm.proc_code_str IS NOT NULL
             AND (
                 LOWER(LTRIM(RTRIM(pm.medium_class))) IN (
                     N'administration',
                     N'first consultation/re-consultation fee',
                     N'dietary/life treatment expense during hospital stay',
                     N'hospitalization fee, etc.',
                     N'medical management, etc.'
                 )
                 OR LOWER(LTRIM(RTRIM(pm.procedure_name))) LIKE N'additional fee%'
                 OR LOWER(LTRIM(RTRIM(pm.procedure_name))) LIKE N'%management fee%'
                 OR LOWER(LTRIM(RTRIM(pm.procedure_name))) LIKE N'%diet expense%'
                 OR LOWER(LTRIM(RTRIM(pm.procedure_name))) LIKE N'%patient charge on diet%'
                 OR LOWER(LTRIM(RTRIM(pm.procedure_name))) LIKE N'diagnosis of plain radiographs%'
                 OR LOWER(LTRIM(RTRIM(pm.procedure_name))) LIKE N'%allowance%'
                 OR LOWER(LTRIM(RTRIM(pm.procedure_name))) LIKE N'%implementation plan fee%'
                 OR LOWER(LTRIM(RTRIM(pm.small_class))) LIKE N'%interpretation fee%'
                 OR LOWER(LTRIM(RTRIM(pm.small_class))) LIKE N'%consultation fee%'
                 OR LOWER(LTRIM(RTRIM(pm.small_class))) LIKE N'%prescription fee%'
                 OR LOWER(LTRIM(RTRIM(pm.small_class))) LIKE N'%dispensing fee%'
                 OR LOWER(LTRIM(RTRIM(pm.small_class))) LIKE N'%management fee%'
                 OR LOWER(LTRIM(RTRIM(pm.procedure_name))) LIKE N'%consultation fee%'
                 OR LOWER(LTRIM(RTRIM(pm.procedure_name))) LIKE N'%interpretation fee%'
                 OR LOWER(LTRIM(RTRIM(pm.procedure_name))) LIKE N'%prescription fee%'
                 OR LOWER(LTRIM(RTRIM(pm.procedure_name))) LIKE N'%dispensing fee%'
             )
            THEN 1
            WHEN pm.proc_code_str IS NULL
             AND LEFT(c.proc_code_str, 3) IN (N'111', N'112', N'113', N'120')
            THEN 1
            ELSE 0
        END AS is_admin_fee
    ) pol
    LEFT JOIN @cdm_database.jmdc_proc_code_to_concept xmap
      ON xmap.country = N'JP'
     AND xmap.source_code = c.proc_code_str
     AND xmap.source_code_system = N'JMDC_STD_PROC'
     AND xmap.mapping_version = N'1.0'
    LEFT JOIN @cdm_database.CONCEPT xw
      ON xw.vocabulary_id = xmap.target_vocabulary_id
     AND xw.concept_code = xmap.target_concept_code
     AND xw.standard_concept = 'S'
     AND xw.invalid_reason IS NULL
     AND xw.domain_id = N'Procedure'
     AND GETDATE() >= xw.valid_start_date
     AND GETDATE() < ISNULL(
         xw.valid_end_date,
         DATEFROMPARTS(2099, 12, 31)
     )
    OUTER APPLY (
        SELECT TOP (1)
            m.target_concept_id
        FROM (VALUES
            (pm.icd9proc_code, 0),
            (c.proc_code_str, 1),
            (
                CASE WHEN c.proc_version_str IS NOT NULL
                     THEN c.proc_code_str + c.proc_version_str END,
                2
            ),
            (
                CASE WHEN c.proc_version_str IS NOT NULL
                     THEN c.proc_code_str + N':' + c.proc_version_str END,
                3
            ),
            (
                CASE WHEN c.proc_version_str IS NOT NULL
                     THEN c.proc_code_str + N'-' + c.proc_version_str END,
                4
            ),
            (REPLACE(c.proc_code_str, N'-', N''), 5)
        ) key_candidate(source_code, priority)
        INNER JOIN @cdm_database.source_to_concept_map m
          ON m.source_code = key_candidate.source_code
         AND m.invalid_reason IS NULL
         AND LOWER(m.domain_id) = N'procedure'
        INNER JOIN @cdm_database.CONCEPT target
          ON target.concept_id = m.target_concept_id
         AND target.standard_concept = 'S'
         AND target.invalid_reason IS NULL
         AND target.domain_id = N'Procedure'
         AND GETDATE() >= target.valid_start_date
         AND GETDATE() < ISNULL(
             target.valid_end_date,
             DATEFROMPARTS(2099, 12, 31)
         )
        WHERE pol.is_admin_fee = 0
          AND key_candidate.source_code IS NOT NULL
        ORDER BY
            key_candidate.priority,
            CASE
                WHEN m.target_vocabulary_id IN (
                    N'CPT4',
                    N'ICD10PCS',
                    N'ICD9Proc',
                    N'SNOMED',
                    N'OPCS4'
                ) THEN 1
                WHEN m.target_vocabulary_id LIKE N'HCPCS%' THEN 2
                ELSE 3
            END,
            m.target_concept_id
    ) cm_try
    OPTION (RECOMPILE, MAXDOP 4);

    CREATE UNIQUE NONCLUSTERED INDEX IX_jmdc_proc_code_map
        ON @cdm_database.jmdc_proc_code_map (
            proc_code_str,
            proc_version_str
        );
END;
GO

/* A rerun refreshes corrected policy mappings without duplicating events. */
IF EXISTS (SELECT TOP (1) 1 FROM @cdm_database.procedure_occurrence)
BEGIN
    UPDATE po
    SET po.procedure_concept_id = ISNULL(cm.target_concept_id, 0)
    FROM @cdm_database.procedure_occurrence po
    INNER HASH JOIN @cdm_database.jmdc_proc_norm r
      ON r.master_seq = po.master_seq
    LEFT HASH JOIN @cdm_database.jmdc_proc_code_map cm
      ON cm.proc_code_str = r.proc_code_str
     AND ISNULL(cm.proc_version_str, '') = ISNULL(r.proc_version_str, '')
    WHERE po.procedure_concept_id <> ISNULL(cm.target_concept_id, 0)
    OPTION (RECOMPILE, MAXDOP 4);
END;
GO

DECLARE @inserted_rows BIGINT = 0;

IF NOT EXISTS (SELECT TOP (1) 1 FROM @cdm_database.procedure_occurrence)
BEGIN
    INSERT INTO @cdm_database.procedure_occurrence (
        procedure_occurrence_id,
        person_id,
        procedure_concept_id,
        procedure_date,
        procedure_datetime,
        procedure_type_concept_id,
        visit_occurrence_id,
        procedure_source_value,
        procedure_source_concept_id,
        master_seq
    )
    SELECT
        r.master_seq AS procedure_occurrence_id,
        p.person_id,
        ISNULL(cm.target_concept_id, 0) AS procedure_concept_id,
        dt.proc_date AS procedure_date,
        NULL AS procedure_datetime,
        44818517 AS procedure_type_concept_id,
        v.visit_occurrence_id,
        r.proc_code_str AS procedure_source_value,
        NULL AS procedure_source_concept_id,
        r.master_seq
    FROM @cdm_database.jmdc_proc_norm r
    INNER HASH JOIN @cdm_database.person p
      ON p.person_source_value = r.member_id_str
    INNER HASH JOIN @cdm_database.visit_occurrence v
      ON v.person_id = p.person_id
     AND v.visit_source_value = r.claim_id_str
    LEFT HASH JOIN @cdm_database.jmdc_proc_code_map cm
      ON cm.proc_code_str = r.proc_code_str
     AND ISNULL(cm.proc_version_str, '') = ISNULL(r.proc_version_str, '')
    CROSS APPLY (
        SELECT CAST(
            COALESCE(r.proc_dt, v.visit_start_date, v.visit_end_date)
            AS DATE
        ) AS proc_date
    ) dt
    WHERE dt.proc_date IS NOT NULL
    OPTION (RECOMPILE, MAXDOP 4);

    SET @inserted_rows = @@ROWCOUNT;
END
ELSE
BEGIN
    INSERT INTO @cdm_database.procedure_occurrence (
        procedure_occurrence_id,
        person_id,
        procedure_concept_id,
        procedure_date,
        procedure_datetime,
        procedure_type_concept_id,
        visit_occurrence_id,
        procedure_source_value,
        procedure_source_concept_id,
        master_seq
    )
    SELECT
        r.master_seq AS procedure_occurrence_id,
        p.person_id,
        ISNULL(cm.target_concept_id, 0) AS procedure_concept_id,
        dt.proc_date AS procedure_date,
        NULL AS procedure_datetime,
        44818517 AS procedure_type_concept_id,
        v.visit_occurrence_id,
        r.proc_code_str AS procedure_source_value,
        NULL AS procedure_source_concept_id,
        r.master_seq
    FROM @cdm_database.jmdc_proc_norm r
    INNER HASH JOIN @cdm_database.person p
      ON p.person_source_value = r.member_id_str
    INNER HASH JOIN @cdm_database.visit_occurrence v
      ON v.person_id = p.person_id
     AND v.visit_source_value = r.claim_id_str
    LEFT HASH JOIN @cdm_database.jmdc_proc_code_map cm
      ON cm.proc_code_str = r.proc_code_str
     AND ISNULL(cm.proc_version_str, '') = ISNULL(r.proc_version_str, '')
    CROSS APPLY (
        SELECT CAST(
            COALESCE(r.proc_dt, v.visit_start_date, v.visit_end_date)
            AS DATE
        ) AS proc_date
    ) dt
    WHERE dt.proc_date IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM @cdm_database.procedure_occurrence po
          WHERE po.procedure_occurrence_id = r.master_seq
      )
    OPTION (RECOMPILE, MAXDOP 4);

    SET @inserted_rows = @@ROWCOUNT;
END;

SELECT
    CAST('procedure_occurrence' AS VARCHAR(50)) AS _etl_table,
    @inserted_rows AS _etl_inserted_rows;
GO
