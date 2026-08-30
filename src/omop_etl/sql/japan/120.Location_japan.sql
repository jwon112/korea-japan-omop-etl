/**************************************
 Japan: Location (no-op)
 POLICY: NO-OP — See DOMAIN_ETL_POLICY.md (location)
 근거: JMDC payer-based RAW에 주소/지역 컬럼 없음. care_site로 시설 수준만 표현.
 - 현재 RAW 스키마에는 주소/지역 컬럼이 없어 location 적재를 수행하지 않음(0행 유지).
**************************************/

-- Intentionally no rows inserted.
INSERT INTO @cdm_database.location (
    location_id, address_1, address_2, city, state, zip, county, location_source_value
)
SELECT
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
WHERE 1 = 0;

