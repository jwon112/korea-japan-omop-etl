/**************************************
 Japan: Observation (no source yet)
 POLICY: NO-OP — See DOMAIN_ETL_POLICY.md (observation)
 근거: 검진·수치는 JP_ANNUAL_HEALTH_CHECKUP → measurement. observation 전용 원천 없음.
 - 현재 japan_cohort_raw 스키마(JP_PATIENT/JP_CLAIMS/JP_DIAGNOSIS/JP_DRUG/JP_PROCEDURE)에는
   observation에 해당하는 원천 테이블/컬럼이 없어 적재하지 않음(0행 유지).
 - 원천(예: vitals, 진단검사 결과, 관찰값) 테이블이 추가되면 이 파일에 매핑 로직을 구현할 것.
**************************************/

INSERT INTO @cdm_database.observation (
    observation_id, person_id, observation_concept_id, observation_date, observation_datetime,
    observation_type_concept_id, value_as_number, value_as_string, value_as_concept_id,
    qualifier_concept_id, unit_concept_id, provider_id, visit_occurrence_id, visit_detail_id,
    observation_source_value, observation_source_concept_id, unit_source_value, qualifier_source_value
)
SELECT
    NULL, NULL, 0, CAST('1900-01-01' AS DATE), NULL,
    0, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL
FROM (SELECT 1 AS x) d
WHERE 1 = 0;

