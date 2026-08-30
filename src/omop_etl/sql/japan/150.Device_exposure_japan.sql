/**************************************
 REVIEW NOTE 2026-06-04:
 - JP_MATERIAL exists in sample RAW (28,939 rows) and includes device/material candidates
   such as oxygen tanks, dialyzers, cannulas, image films, catheters, and implants.
 - This SQL is currently NO-OP because JMDC material code -> OMOP Device concept mapping
   has not been defined yet. This is a deferred mapping task, not absence of source data.
 - Future implementation should add a jmdc_material_code_to_concept crosswalk/seed table.

 Japan: Device_exposure (no source yet)
 POLICY: NO-OP — See DOMAIN_ETL_POLICY.md (device_exposure)
 근거: JP_MATERIAL 등 device 매핑 정책 확정 전까지 미적재.
 - 현재 japan_cohort_raw 스키마에는 device_exposure로 변환할 기기/재료/장치 원천 테이블이 없어 적재하지 않음(0행 유지).
 - 원천 테이블이 추가되면(예: device code, 사용일, 수량) source_to_concept_map 기반으로 매핑 예정.
**************************************/

INSERT INTO @cdm_database.device_exposure (
    device_exposure_id, person_id, device_concept_id, device_exposure_start_date, device_exposure_start_datetime,
    device_exposure_end_date, device_exposure_end_datetime, device_type_concept_id, unique_device_id,
    quantity, provider_id, visit_occurrence_id, visit_detail_id, device_source_value, device_source_concept_id
)
SELECT
    NULL, NULL, 0, CAST('1900-01-01' AS DATE), NULL,
    NULL, NULL, 0, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL
FROM (SELECT 1 AS x) d
WHERE 1 = 0;
