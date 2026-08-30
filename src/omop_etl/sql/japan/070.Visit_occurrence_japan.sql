/**************************************
 Japan: JP_CLAIMS -> VISIT_OCCURRENCE
 POLICY: LOAD - see DOMAIN_ETL_POLICY.md (visit_occurrence)

 Relational JMDC policy:
 - One valid JP_CLAIMS row becomes one visit.
 - Diagnosis, drug, and procedure rows attach to that claim-backed visit.
 - Claim dates are authoritative; claim month is the final date fallback.
 - The claim SEQ_MASTER key is the deterministic visit_occurrence_id.

 Fresh and append paths are separate. The fresh path never reads the target
 table, which prevents SQL Server from eagerly spooling all claim rows before
 inserting them.
**************************************/

DECLARE @inserted_rows BIGINT = 0;

IF NOT EXISTS (SELECT TOP (1) 1 FROM @cdm_database.visit_occurrence)
BEGIN
    WITH claims AS (
        SELECT
            COALESCE(
                CONVERT(VARCHAR(50), TRY_CAST(
                    NULLIF(LTRIM(RTRIM(CAST(c.member_id AS VARCHAR(100)))), '')
                    AS DECIMAL(38, 0)
                )),
                NULLIF(LTRIM(RTRIM(CAST(c.member_id AS VARCHAR(100)))), '')
            ) AS member_id_str,
            COALESCE(
                CONVERT(VARCHAR(50), TRY_CAST(
                    NULLIF(LTRIM(RTRIM(CAST(c.claim_id AS VARCHAR(100)))), '')
                    AS DECIMAL(38, 0)
                )),
                NULLIF(LTRIM(RTRIM(CAST(c.claim_id AS VARCHAR(100)))), '')
            ) AS claim_id_str,
            @cdm_database.fn_jmdc_date(c.admission_date) AS admission_date,
            @cdm_database.fn_jmdc_date(c.discharge_date) AS discharge_date,
            TRY_CONVERT(
                DATE,
                CONVERT(
                    VARCHAR(6),
                    TRY_CONVERT(INT, c.month_and_year_of_medical_care)
                ) + '01',
                112
            ) AS claim_month_start,
            c.type_of_claim
        FROM @raw_database.JP_CLAIMS c
    ),
    ready AS (
        SELECT
            member_id_str,
            claim_id_str,
            COALESCE(
                admission_date,
                discharge_date,
                claim_month_start
            ) AS visit_start_date,
            CASE
                WHEN COALESCE(
                         discharge_date,
                         admission_date,
                         EOMONTH(claim_month_start)
                     ) < COALESCE(
                         admission_date,
                         discharge_date,
                         claim_month_start
                     )
                THEN COALESCE(
                         admission_date,
                         discharge_date,
                         claim_month_start
                     )
                ELSE COALESCE(
                         discharge_date,
                         admission_date,
                         EOMONTH(claim_month_start)
                     )
            END AS visit_end_date,
            type_of_claim
        FROM claims
        WHERE member_id_str IS NOT NULL
          AND member_id_str <> ''
          AND claim_id_str IS NOT NULL
          AND claim_id_str <> ''
    )
    INSERT INTO @cdm_database.visit_occurrence (
        visit_occurrence_id, person_id, visit_concept_id, visit_start_date,
        visit_start_datetime, visit_end_date, visit_end_datetime,
        visit_type_concept_id, provider_id, care_site_id, visit_source_value,
        visit_source_concept_id, master_seq
    )
    SELECT
        sm.master_seq AS visit_occurrence_id,
        p.person_id,
        CASE
            WHEN r.type_of_claim IN ('inpatient', 'Inpatient', '1') THEN 9201
            WHEN r.type_of_claim IN ('outpatient', 'Outpatient', '2') THEN 9202
            ELSE 9202
        END AS visit_concept_id,
        r.visit_start_date,
        NULL AS visit_start_datetime,
        r.visit_end_date,
        NULL AS visit_end_datetime,
        44818517 AS visit_type_concept_id,
        NULL AS provider_id,
        NULL AS care_site_id,
        r.claim_id_str AS visit_source_value,
        NULL AS visit_source_concept_id,
        sm.master_seq
    FROM ready r
    INNER HASH JOIN @cdm_database.person p
      ON p.person_source_value = r.member_id_str
    INNER HASH JOIN @cdm_database.SEQ_MASTER sm
      ON sm.source_table = 'CLM'
     AND sm.member_id = r.member_id_str
     AND sm.claim_id = r.claim_id_str
     AND sm.statement_id IS NULL
    WHERE r.visit_start_date IS NOT NULL
    OPTION (RECOMPILE, MAXDOP 4);

    SET @inserted_rows = @@ROWCOUNT;
END
ELSE
BEGIN
    WITH claims AS (
        SELECT
            COALESCE(
                CONVERT(VARCHAR(50), TRY_CAST(
                    NULLIF(LTRIM(RTRIM(CAST(c.member_id AS VARCHAR(100)))), '')
                    AS DECIMAL(38, 0)
                )),
                NULLIF(LTRIM(RTRIM(CAST(c.member_id AS VARCHAR(100)))), '')
            ) AS member_id_str,
            COALESCE(
                CONVERT(VARCHAR(50), TRY_CAST(
                    NULLIF(LTRIM(RTRIM(CAST(c.claim_id AS VARCHAR(100)))), '')
                    AS DECIMAL(38, 0)
                )),
                NULLIF(LTRIM(RTRIM(CAST(c.claim_id AS VARCHAR(100)))), '')
            ) AS claim_id_str,
            @cdm_database.fn_jmdc_date(c.admission_date) AS admission_date,
            @cdm_database.fn_jmdc_date(c.discharge_date) AS discharge_date,
            TRY_CONVERT(
                DATE,
                CONVERT(
                    VARCHAR(6),
                    TRY_CONVERT(INT, c.month_and_year_of_medical_care)
                ) + '01',
                112
            ) AS claim_month_start,
            c.type_of_claim
        FROM @raw_database.JP_CLAIMS c
    ),
    ready AS (
        SELECT
            member_id_str,
            claim_id_str,
            COALESCE(
                admission_date,
                discharge_date,
                claim_month_start
            ) AS visit_start_date,
            CASE
                WHEN COALESCE(
                         discharge_date,
                         admission_date,
                         EOMONTH(claim_month_start)
                     ) < COALESCE(
                         admission_date,
                         discharge_date,
                         claim_month_start
                     )
                THEN COALESCE(
                         admission_date,
                         discharge_date,
                         claim_month_start
                     )
                ELSE COALESCE(
                         discharge_date,
                         admission_date,
                         EOMONTH(claim_month_start)
                     )
            END AS visit_end_date,
            type_of_claim
        FROM claims
        WHERE member_id_str IS NOT NULL
          AND member_id_str <> ''
          AND claim_id_str IS NOT NULL
          AND claim_id_str <> ''
    )
    INSERT INTO @cdm_database.visit_occurrence (
        visit_occurrence_id, person_id, visit_concept_id, visit_start_date,
        visit_start_datetime, visit_end_date, visit_end_datetime,
        visit_type_concept_id, provider_id, care_site_id, visit_source_value,
        visit_source_concept_id, master_seq
    )
    SELECT
        sm.master_seq AS visit_occurrence_id,
        p.person_id,
        CASE
            WHEN r.type_of_claim IN ('inpatient', 'Inpatient', '1') THEN 9201
            WHEN r.type_of_claim IN ('outpatient', 'Outpatient', '2') THEN 9202
            ELSE 9202
        END AS visit_concept_id,
        r.visit_start_date,
        NULL AS visit_start_datetime,
        r.visit_end_date,
        NULL AS visit_end_datetime,
        44818517 AS visit_type_concept_id,
        NULL AS provider_id,
        NULL AS care_site_id,
        r.claim_id_str AS visit_source_value,
        NULL AS visit_source_concept_id,
        sm.master_seq
    FROM ready r
    INNER HASH JOIN @cdm_database.person p
      ON p.person_source_value = r.member_id_str
    INNER HASH JOIN @cdm_database.SEQ_MASTER sm
      ON sm.source_table = 'CLM'
     AND sm.member_id = r.member_id_str
     AND sm.claim_id = r.claim_id_str
     AND sm.statement_id IS NULL
    WHERE r.visit_start_date IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM @cdm_database.visit_occurrence vo
          WHERE vo.visit_occurrence_id = sm.master_seq
      )
    OPTION (RECOMPILE, MAXDOP 4);

    SET @inserted_rows = @@ROWCOUNT;
END;

SELECT CAST('visit_occurrence' AS VARCHAR(50)) AS _etl_table,
       @inserted_rows AS _etl_inserted_rows;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.visit_occurrence')
      AND name = N'UX_jmdc_visit_person_source'
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_jmdc_visit_person_source
        ON @cdm_database.visit_occurrence (person_id, visit_source_value)
        INCLUDE (visit_occurrence_id, master_seq)
        WHERE visit_source_value IS NOT NULL;
END;
