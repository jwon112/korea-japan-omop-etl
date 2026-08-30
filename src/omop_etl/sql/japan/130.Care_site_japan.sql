/**************************************
 JMDC sample: Medical_facility → CARE_SITE
 POLICY: LOAD — See DOMAIN_ETL_POLICY.md (care_site)
 근거: JP_MEDICAL_FACILITY + JP_CLAIMS.medical_facility_id → visit_occurrence.care_site_id

 [Place of service — JMDC hpgp → CMS Place of Service (CONCEPT)]
   GP → concept_code 49 (Independent Clinic)  ※ 현재 샘플 vocab에 11(Office)이 없어 49로 대체
   HP → concept_code 21 (Inpatient Hospital, e.g. concept_id 9201)
   근거: JMDC facility type + OMOP CMS Place of Service vocabulary.

 care_site_name: RAW에 병원명 없음 → NULL 유지.
**************************************/

;WITH pos_hpgp_map AS (
    SELECT hpgp_prefix, cms_pos_code
    FROM (VALUES
        (N'GP', N'49'),
        (N'HP', N'21')
    ) AS t(hpgp_prefix, cms_pos_code)
),
pos_std AS (
    SELECT pm.hpgp_prefix, c.concept_id AS place_of_service_concept_id
    FROM pos_hpgp_map pm
    LEFT JOIN @cdm_database.CONCEPT c
      ON c.vocabulary_id = N'CMS Place of Service'
     AND c.concept_code = pm.cms_pos_code
     AND c.standard_concept = 'S'
     AND GETDATE() >= c.valid_start_date
     AND GETDATE() < ISNULL(c.valid_end_date, DATEFROMPARTS(2099, 12, 31))
),
to_insert AS (
    SELECT DISTINCT
        NULLIF(LTRIM(RTRIM(mf.medical_facility_id)), '') AS medical_facility_id,
        NULLIF(LTRIM(RTRIM(mf.hpgp)), '') AS hpgp,
        NULLIF(LTRIM(RTRIM(mf.number_of_beds)), '') AS number_of_beds
    FROM @raw_database.JP_MEDICAL_FACILITY mf
    WHERE NULLIF(LTRIM(RTRIM(mf.medical_facility_id)), '') IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM @cdm_database.care_site cs
          WHERE cs.care_site_source_value = mf.medical_facility_id
      )
)
INSERT INTO @cdm_database.care_site (
    care_site_id, care_site_name, place_of_service_concept_id, location_id,
    care_site_source_value, place_of_service_source_value
)
SELECT
    (SELECT ISNULL(MAX(care_site_id), 0) FROM @cdm_database.care_site)
    + ROW_NUMBER() OVER (ORDER BY t.medical_facility_id) AS care_site_id,
    NULL AS care_site_name,
    COALESCE(ps.place_of_service_concept_id, 0) AS place_of_service_concept_id,
    NULL AS location_id,
    t.medical_facility_id AS care_site_source_value,
    CASE
        WHEN t.hpgp IS NULL AND t.number_of_beds IS NULL THEN NULL
        WHEN t.hpgp IS NULL THEN t.number_of_beds
        WHEN t.number_of_beds IS NULL THEN t.hpgp
        ELSE t.hpgp + N'/' + t.number_of_beds
    END AS place_of_service_source_value
FROM to_insert t
LEFT JOIN pos_std ps ON ps.hpgp_prefix = t.hpgp;
GO

-- visit_occurrence.care_site_id (claim에 medical_facility_id 있는 경우)
UPDATE v
SET v.care_site_id = cs.care_site_id
FROM @cdm_database.visit_occurrence v
JOIN @raw_database.JP_CLAIMS c
OUTER APPLY (
    SELECT NULLIF(LTRIM(RTRIM(CAST(c.claim_id AS VARCHAR(100)))),'') AS claim_id_str
) cid
  ON cid.claim_id_str = v.visit_source_value
JOIN @cdm_database.care_site cs
  ON cs.care_site_source_value = NULLIF(LTRIM(RTRIM(CAST(c.medical_facility_id AS VARCHAR(100)))),'')
WHERE v.care_site_id IS NULL;
GO

/* Backfill place_of_service_concept_id on existing care_site rows */
;WITH pos_hpgp_map AS (
    SELECT hpgp_prefix, cms_pos_code
    FROM (VALUES
        (N'GP', N'49'),
        (N'HP', N'21')
    ) AS t(hpgp_prefix, cms_pos_code)
),
pos_std AS (
    SELECT pm.hpgp_prefix, c.concept_id AS place_of_service_concept_id
    FROM pos_hpgp_map pm
    LEFT JOIN @cdm_database.CONCEPT c
      ON c.vocabulary_id = N'CMS Place of Service'
     AND c.concept_code = pm.cms_pos_code
     AND c.standard_concept = 'S'
     AND GETDATE() >= c.valid_start_date
     AND GETDATE() < ISNULL(c.valid_end_date, DATEFROMPARTS(2099, 12, 31))
)
UPDATE cs
SET cs.place_of_service_concept_id = COALESCE(ps.place_of_service_concept_id, cs.place_of_service_concept_id)
FROM @cdm_database.care_site cs
JOIN @raw_database.JP_MEDICAL_FACILITY mf
  ON cs.care_site_source_value = NULLIF(LTRIM(RTRIM(mf.medical_facility_id)), '')
LEFT JOIN pos_std ps ON ps.hpgp_prefix = NULLIF(LTRIM(RTRIM(mf.hpgp)), '')
WHERE cs.place_of_service_concept_id = 0
  AND ps.place_of_service_concept_id IS NOT NULL;
GO
SELECT CAST('care_site_pos_mapped' AS VARCHAR(50)) AS _etl_table,
       SUM(CASE WHEN place_of_service_concept_id > 0 THEN 1 ELSE 0 END) AS _etl_mapped_rows,
       COUNT(*) AS _etl_total_rows
FROM @cdm_database.care_site;
