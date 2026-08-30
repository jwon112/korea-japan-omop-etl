/**************************************
 JMDC sample: Annual_health_checkup → MEASUREMENT
 POLICY: LOAD — See DOMAIN_ETL_POLICY.md (measurement)
 근거: JP_ANNUAL_HEALTH_CHECKUP + OHDSI LOINC/UCUM (CONCEPT vocabulary).

 [Measurement mapping — JMDC column → LOINC concept_code]
   bmi → 39156-5 | abdominal_circumference → 8280-0 | systolic_bp → 8480-6
   diastolic_bp → 8462-4 | triglyceride → 2571-8 | hdl_cholesterol → 2085-9
   ldl_cholesterol → 2089-1 | fasting_blood_sugar → 1558-6 | casual_blood_sugar → 2339-0
   hba1c → 4548-4
 [Unit mapping — unit_source_value → UCUM concept_code]
   kg/m2 → kg/m2 | cm → cm | mmHg → mm[Hg] | mg/dl → mg/dL | % → %

 vocabulary 미로드 시 concept_id=0 폴백. 재실행 시 하단 UPDATE로 기존 행 backfill.
**************************************/

DECLARE @TYPE_CONCEPT_ID INT = 44818702; -- Measurement recorded (Lab/clinical)

;WITH jmdc_meas_map AS (
    SELECT measurement_source_value, loinc_code, ucum_code
    FROM (VALUES
        (N'bmi',                    N'39156-5', N'kg/m2'),
        (N'abdominal_circumference', N'8280-0',  N'cm'),
        (N'systolic_bp',            N'8480-6',  N'mm[Hg]'),
        (N'diastolic_bp',           N'8462-4',  N'mm[Hg]'),
        (N'triglyceride',           N'2571-8',  N'mg/dL'),
        (N'hdl_cholesterol',        N'2085-9',  N'mg/dL'),
        (N'ldl_cholesterol',        N'2089-1',  N'mg/dL'),
        (N'fasting_blood_sugar',    N'1558-6',  N'mg/dL'),
        (N'casual_blood_sugar',     N'2339-0',  N'mg/dL'),
        (N'hba1c',                  N'4548-4',  N'%')
    ) AS t(measurement_source_value, loinc_code, ucum_code)
),
loinc_std AS (
    SELECT m.measurement_source_value, m.ucum_code, c.concept_id AS measurement_concept_id
    FROM jmdc_meas_map m
    LEFT JOIN @cdm_database.CONCEPT c
      ON c.vocabulary_id = N'LOINC'
     AND c.concept_code = m.loinc_code
     AND c.standard_concept = 'S'
     AND GETDATE() >= c.valid_start_date
     AND GETDATE() < ISNULL(c.valid_end_date, DATEFROMPARTS(2099, 12, 31))
),
ucum_std AS (
    SELECT m.ucum_code, c.concept_id AS unit_concept_id
    FROM (SELECT DISTINCT ucum_code FROM jmdc_meas_map) m
    LEFT JOIN @cdm_database.CONCEPT c
      ON c.vocabulary_id = N'UCUM'
     AND c.concept_code = m.ucum_code
     AND c.standard_concept = 'S'
     AND GETDATE() >= c.valid_start_date
     AND GETDATE() < ISNULL(c.valid_end_date, DATEFROMPARTS(2099, 12, 31))
),
base AS (
    SELECT
        p.person_id,
        ah.member_id,
        ah.health_checkup_id,
        TRY_CONVERT(DATE, ah.date_of_health_checkup) AS m_date,
        ah.bmi,
        ah.abdominal_circumference,
        ah.systolic_bp,
        ah.diastolic_bp,
        ah.triglyceride,
        ah.hdl_cholesterol,
        ah.ldl_cholesterol,
        ah.fasting_blood_sugar,
        ah.casual_blood_sugar,
        ah.hba1c
    FROM @raw_database.JP_ANNUAL_HEALTH_CHECKUP ah
    JOIN @cdm_database.person p
      ON p.person_source_value = NULLIF(LTRIM(RTRIM(CAST(ah.member_id AS VARCHAR(100)))),'')
)
INSERT INTO @cdm_database.measurement (
    measurement_id, person_id, measurement_concept_id, measurement_date, measurement_datetime, measurement_time,
    measurement_type_concept_id, operator_concept_id, value_as_number, value_as_concept_id, unit_concept_id,
    range_low, range_high, provider_id, visit_occurrence_id, visit_detail_id,
    measurement_source_value, measurement_source_concept_id, unit_source_value, value_source_value
)
SELECT
    (SELECT ISNULL(MAX(measurement_id), 0) FROM @cdm_database.measurement)
    + ROW_NUMBER() OVER (ORDER BY b.person_id, b.health_checkup_id, v.measurement_source_value) AS measurement_id,
    b.person_id,
    COALESCE(ls.measurement_concept_id, 0) AS measurement_concept_id,
    b.m_date AS measurement_date,
    NULL AS measurement_datetime,
    NULL AS measurement_time,
    @TYPE_CONCEPT_ID AS measurement_type_concept_id,
    NULL AS operator_concept_id,
    v.value_as_number,
    NULL AS value_as_concept_id,
    COALESCE(us.unit_concept_id, 0) AS unit_concept_id,
    NULL AS range_low,
    NULL AS range_high,
    NULL AS provider_id,
    NULL AS visit_occurrence_id,
    NULL AS visit_detail_id,
    v.measurement_source_value,
    NULL AS measurement_source_concept_id,
    v.unit_source_value,
    v.value_source_value
FROM base b
CROSS APPLY (
    VALUES
      (N'bmi',                    TRY_CONVERT(FLOAT, b.bmi),                    N'kg/m2', b.bmi),
      (N'abdominal_circumference', TRY_CONVERT(FLOAT, b.abdominal_circumference), N'cm',   b.abdominal_circumference),
      (N'systolic_bp',            TRY_CONVERT(FLOAT, b.systolic_bp),            N'mmHg', b.systolic_bp),
      (N'diastolic_bp',           TRY_CONVERT(FLOAT, b.diastolic_bp),           N'mmHg', b.diastolic_bp),
      (N'triglyceride',           TRY_CONVERT(FLOAT, b.triglyceride),           N'mg/dl',b.triglyceride),
      (N'hdl_cholesterol',        TRY_CONVERT(FLOAT, b.hdl_cholesterol),        N'mg/dl',b.hdl_cholesterol),
      (N'ldl_cholesterol',        TRY_CONVERT(FLOAT, b.ldl_cholesterol),        N'mg/dl',b.ldl_cholesterol),
      (N'fasting_blood_sugar',    TRY_CONVERT(FLOAT, b.fasting_blood_sugar),    N'mg/dl',b.fasting_blood_sugar),
      (N'casual_blood_sugar',     TRY_CONVERT(FLOAT, b.casual_blood_sugar),     N'mg/dl',b.casual_blood_sugar),
      (N'hba1c',                  TRY_CONVERT(FLOAT, b.hba1c),                  N'%',    b.hba1c)
) v(measurement_source_value, value_as_number, unit_source_value, value_source_value)
LEFT JOIN loinc_std ls ON ls.measurement_source_value = v.measurement_source_value
LEFT JOIN ucum_std us ON us.ucum_code = ls.ucum_code
WHERE b.m_date IS NOT NULL
  AND v.value_as_number IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM @cdm_database.measurement x
      WHERE x.person_id = b.person_id
        AND x.measurement_date = b.m_date
        AND x.measurement_source_value = v.measurement_source_value
  );
GO

/* Backfill LOINC/UCUM on rows loaded before mapping (idempotent) */
;WITH jmdc_meas_map AS (
    SELECT measurement_source_value, loinc_code, ucum_code
    FROM (VALUES
        (N'bmi',                    N'39156-5', N'kg/m2'),
        (N'abdominal_circumference', N'8280-0',  N'cm'),
        (N'systolic_bp',            N'8480-6',  N'mm[Hg]'),
        (N'diastolic_bp',           N'8462-4',  N'mm[Hg]'),
        (N'triglyceride',           N'2571-8',  N'mg/dL'),
        (N'hdl_cholesterol',        N'2085-9',  N'mg/dL'),
        (N'ldl_cholesterol',        N'2089-1',  N'mg/dL'),
        (N'fasting_blood_sugar',    N'1558-6',  N'mg/dL'),
        (N'casual_blood_sugar',     N'2339-0',  N'mg/dL'),
        (N'hba1c',                  N'4548-4',  N'%')
    ) AS t(measurement_source_value, loinc_code, ucum_code)
),
loinc_std AS (
    SELECT m.measurement_source_value, m.ucum_code, c.concept_id AS measurement_concept_id
    FROM jmdc_meas_map m
    LEFT JOIN @cdm_database.CONCEPT c
      ON c.vocabulary_id = N'LOINC'
     AND c.concept_code = m.loinc_code
     AND c.standard_concept = 'S'
     AND GETDATE() >= c.valid_start_date
     AND GETDATE() < ISNULL(c.valid_end_date, DATEFROMPARTS(2099, 12, 31))
),
ucum_std AS (
    SELECT m.ucum_code, c.concept_id AS unit_concept_id
    FROM (SELECT DISTINCT ucum_code FROM jmdc_meas_map) m
    LEFT JOIN @cdm_database.CONCEPT c
      ON c.vocabulary_id = N'UCUM'
     AND c.concept_code = m.ucum_code
     AND c.standard_concept = 'S'
     AND GETDATE() >= c.valid_start_date
     AND GETDATE() < ISNULL(c.valid_end_date, DATEFROMPARTS(2099, 12, 31))
)
UPDATE m
SET
    m.measurement_concept_id = COALESCE(ls.measurement_concept_id, m.measurement_concept_id),
    m.unit_concept_id = COALESCE(us.unit_concept_id, m.unit_concept_id)
FROM @cdm_database.measurement m
JOIN loinc_std ls ON ls.measurement_source_value = m.measurement_source_value
LEFT JOIN ucum_std us ON us.ucum_code = ls.ucum_code
WHERE (m.measurement_concept_id = 0 AND ls.measurement_concept_id IS NOT NULL)
   OR (m.unit_concept_id = 0 AND us.unit_concept_id IS NOT NULL);
GO
SELECT CAST('measurement_mapped' AS VARCHAR(50)) AS _etl_table,
       SUM(CASE WHEN measurement_concept_id > 0 THEN 1 ELSE 0 END) AS _etl_mapped_rows,
       COUNT(*) AS _etl_total_rows
FROM @cdm_database.measurement;
