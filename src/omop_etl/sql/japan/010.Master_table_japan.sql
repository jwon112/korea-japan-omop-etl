CREATE OR ALTER FUNCTION dbo.fn_jmdc_date (@value NVARCHAR(50))
RETURNS DATE
AS
BEGIN
    DECLARE @s NVARCHAR(50) = NULLIF(UPPER(LTRIM(RTRIM(@value))), N'');
    DECLARE @direct DATE = COALESCE(TRY_CONVERT(DATE, @s), TRY_CONVERT(DATE, @s, 112));
    IF @direct IS NOT NULL
        RETURN @direct;

    DECLARE @day INT = TRY_CONVERT(INT, LEFT(@s, 2));
    DECLARE @year INT = TRY_CONVERT(INT, RIGHT(@s, 4));
    DECLARE @month INT = CASE SUBSTRING(@s, 3, 3)
        WHEN N'JAN' THEN 1 WHEN N'FEB' THEN 2 WHEN N'MAR' THEN 3
        WHEN N'APR' THEN 4 WHEN N'MAY' THEN 5 WHEN N'JUN' THEN 6
        WHEN N'JUL' THEN 7 WHEN N'AUG' THEN 8 WHEN N'SEP' THEN 9
        WHEN N'OCT' THEN 10 WHEN N'NOV' THEN 11 WHEN N'DEC' THEN 12
    END;
    IF @year BETWEEN 1900 AND 2100 AND @month BETWEEN 1 AND 12 AND @day BETWEEN 1 AND 31
        RETURN TRY_CONVERT(
            DATE,
            CONVERT(VARCHAR(4), @year)
                + RIGHT('0' + CONVERT(VARCHAR(2), @month), 2)
                + RIGHT('0' + CONVERT(VARCHAR(2), @day), 2),
            112
        );

    RETURN COALESCE(
        TRY_CONVERT(DATE, @s),
        TRY_CONVERT(DATE, @s, 112)
    );
END;

GO

/*********************************************************************************
 Japan: SEQ_MASTER (중간 타협 — 원천 행 추적용)
 - 한국 NHIS처럼 CDM PK와 1:1로 묶지는 않되, 원천(청구/명세 행) 단위 계보를 남김.
 - source_table 코드: CLM=JP_CLAIMS, DIA=JP_DIAGNOSIS, DRG=JP_DRUG, PRC=JP_PROCEDURE
 - 도메인 INSERT에서 master_seq로 SEQ_MASTER와 연결 (visit / condition / drug / procedure).
 - SEQ_MASTER를 재생성하면 IDENTITY가 바뀌므로, 마스터 재실행 시 도메인 테이블 TRUNCATE 후
   전체 ETL 순서를 다시 밟는 것을 권장.
*********************************************************************************/

/* CDM 테이블에 master_seq 추가 (멱등, 기본 DB = japan_cohort_cdm 연결 전제) */
IF COL_LENGTH('dbo.visit_occurrence', 'master_seq') IS NULL
    ALTER TABLE dbo.visit_occurrence ADD master_seq BIGINT NULL;

IF COL_LENGTH('dbo.condition_occurrence', 'master_seq') IS NULL
    ALTER TABLE dbo.condition_occurrence ADD master_seq BIGINT NULL;

IF COL_LENGTH('dbo.drug_exposure', 'master_seq') IS NULL
    ALTER TABLE dbo.drug_exposure ADD master_seq BIGINT NULL;

IF COL_LENGTH('dbo.procedure_occurrence', 'master_seq') IS NULL
    ALTER TABLE dbo.procedure_occurrence ADD master_seq BIGINT NULL;

GO

IF OBJECT_ID('@cdm_database.SEQ_MASTER', 'U') IS NOT NULL
    DROP TABLE @cdm_database.SEQ_MASTER;

CREATE TABLE @cdm_database.SEQ_MASTER (
    master_seq          BIGINT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
    source_table        VARCHAR(10) NOT NULL,
    member_id           VARCHAR(50) NOT NULL,
    claim_id            VARCHAR(50) NULL,
    -- 원천 CSV 로딩 시 float로 들어오는 경우가 많아, 조인 안정성을 위해 정수형으로 통일
    statement_id        BIGINT NULL
);

GO

/* 청구 단위: visit_occurrence와 동일 grain (claim_id당 1행) */
INSERT INTO @cdm_database.SEQ_MASTER (source_table, member_id, claim_id, statement_id)
SELECT
    'CLM',
    CAST(c.member_id AS VARCHAR(50)),
    CAST(c.claim_id AS VARCHAR(50)),
    NULL
FROM @raw_database.JP_CLAIMS AS c;

GO

/* 진단 명세 행 */
INSERT INTO @cdm_database.SEQ_MASTER (source_table, member_id, claim_id, statement_id)
SELECT
    'DIA',
    CAST(d.member_id AS VARCHAR(50)),
    CAST(d.claim_id AS VARCHAR(50)),
    TRY_CAST(d.statement_id AS BIGINT)
FROM @raw_database.JP_DIAGNOSIS AS d;

GO

/* 처방/약제 명세 행 */
INSERT INTO @cdm_database.SEQ_MASTER (source_table, member_id, claim_id, statement_id)
SELECT
    'DRG',
    CAST(r.member_id AS VARCHAR(50)),
    CAST(r.claim_id AS VARCHAR(50)),
    TRY_CAST(r.statement_id AS BIGINT)
FROM @raw_database.JP_DRUG AS r;

GO

/* 시술 명세 행 */
INSERT INTO @cdm_database.SEQ_MASTER (source_table, member_id, claim_id, statement_id)
SELECT
    'PRC',
    CAST(pr.member_id AS VARCHAR(50)),
    CAST(pr.claim_id AS VARCHAR(50)),
    TRY_CAST(pr.statement_id AS BIGINT)
FROM @raw_database.JP_PROCEDURE AS pr;

GO

CREATE NONCLUSTERED INDEX IX_SEQ_MASTER_lookup
    ON @cdm_database.SEQ_MASTER (source_table, member_id, claim_id)
    INCLUDE (statement_id);
