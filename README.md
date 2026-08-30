# Korea-Japan OMOP ETL

한국 국민건강보험공단 표본코호트(NHIS-NSC)와 일본 JMDC 관계형 청구
데이터를 OMOP CDM v5.3.1 형식으로 변환하는 Python 기반 SQL Server ETL
패키지입니다.

이 저장소의 핵심 산출물은 일회성 변환 결과가 아니라 다음 환경에서도
재실행할 수 있는 **ETL 코드, 매핑 정책, 실행 순서, 안전장치, QA 도구**입니다.
원천 의료데이터, 변환된 데이터베이스, Athena vocabulary 파일은 포함하지
않습니다.

## 프로젝트 상태

- 릴리스: `v0.1.1`
- 한국 ETL: 필수 기본 도메인과 `cdm_source` 런타임 및 테이블별 QA 완료
- 일본 ETL: JMDC 500K 관계형 샘플의 지원 도메인 런타임 및 QA 완료
- 정적 테스트: 39개 통과
- 패키지 SQL: 한국 21개, 일본 17개
- SQL Server `PARSEONLY`: 124개 렌더링 배치 통과
- 배포 wheel: `dist/korea_japan_omop_etl-0.1.1-py3-none-any.whl`

최종 행 수와 매핑률은
[한국 검증 보고서](docs/KOREA_FINAL_VALIDATION.md)와
[일본 검증 보고서](docs/JAPAN_FINAL_VALIDATION.md)에서 확인할 수 있습니다.

## 지원 범위

| 구분 | 한국 NHIS-NSC | 일본 JMDC |
| --- | --- | --- |
| 실행 엔진 | Python + pyodbc + SQL Server | Python + pyodbc/sqlcmd + SQL Server |
| 코호트 기준 | 자격, 청구, 검진 테이블 | `JP_CLAIMS` 기반 관계형 코호트 |
| Vocabulary | Athena vocabulary를 target DB에 적재 | Athena vocabulary를 target DB에 적재 |
| 주요 도메인 | Person, Visit, Condition, Drug, Procedure, Device, Measurement, Observation, Payer, Cost | Person, Visit, Condition, Drug, Procedure, Payer, Death, Cost |
| 매핑 원칙 | 활성 표준 concept과 국내 원천 규칙 | 활성 표준 concept과 JMDC 교차표 |
| 미매핑 행 | 근거가 없으면 concept ID `0`으로 보존 | 근거가 없으면 concept ID `0`으로 보존 |
| QA | 공통 quick/full QA | 공통 quick/full QA |

원천에 안정적인 개인 의료진 식별자가 없는 한국 `provider`, 표준화된 dose
unit이 없는 `dose_era`, 필요한 원천 테이블이 없는 일부 일본 도메인은
의도적으로 비어 있습니다. 자세한 근거는
[매핑 정책](docs/MAPPING_POLICY.md)에 기록되어 있습니다.

## 전체 처리 구조

```text
RAW databases
  |  Korea NHIS-NSC / Japan JMDC
  v
Preflight
  |  source table, row count, storage, vocabulary prerequisite checks
  v
Target DDL and Athena vocabulary
  |  OMOP CDM schema + standard concepts and relationships
  v
Master / normalized staging
  |  deterministic source keys and reusable relational spine
  v
Domain ETL
  |  person -> observation/visit -> clinical events -> payer/cost
  v
Post stage
  |  required source metadata, optional era/index/constraints
  v
Quick QA + table-specific Full QA
  |  counts, concepts, dates, links, boundaries, duplicate keys
  v
Release evidence
```

Python runner가 SQL 파일의 데이터베이스 placeholder를 렌더링하고, 단계
의존성, 기존 target 보호, F 드라이브 저장 위치, `tempdb` 위치, 명시적
`--execute`, 선택적 `--reset`을 검사합니다. 실제 대용량 변환은 SQL Server가
수행하며, 장시간 실행 중에는 Windows 유휴 절전만 일시적으로 억제합니다.

## 디렉터리 구조

```text
korea-japan-omop-etl/
|-- README.md                 프로젝트 소개와 빠른 사용법
|-- pyproject.toml            패키지 메타데이터와 CLI entry point
|-- requirements.txt          Python 런타임 의존성
|-- .env.example              환경변수 예시
|-- run_korea.py              저장소에서 실행하는 한국 CLI wrapper
|-- run_japan.py              저장소에서 실행하는 일본 CLI wrapper
|-- validate_package.py       SQL 자산 렌더링 및 parser 검증 wrapper
|-- validate_cdm.py           공통 CDM QA wrapper
|-- src/omop_etl/
|   |-- korea.py              한국 단계, 의존성, 저장공간, 실행 제어
|   |-- japan.py              일본 단계, vocabulary 적재, 실행 제어
|   |-- qa.py                 공통 quick/full QA
|   |-- package_check.py      패키지 SQL 누락/잉여/문법 검사
|   |-- power.py              장시간 실행 중 Windows 유휴 절전 방지
|   `-- sql/
|       |-- korea/            한국 변환 SQL 21개
|       `-- japan/            일본 변환 SQL 17개
|-- tests/
|   `-- test_static.py        렌더링, 정책, 안전장치 회귀 테스트
`-- docs/
    |-- RUNBOOK.md            전체 운영 절차와 복구 방법
    |-- MAPPING_POLICY.md     한일 매핑 및 미지원 정책
    |-- STATUS.md             현재 완료 상태
    |-- KOREA_FINAL_VALIDATION.md
    |-- JAPAN_FINAL_VALIDATION.md
    |-- RELEASE_VALIDATION.md
    `-- STORAGE_AUDIT.md
```

다음 디렉터리는 실행 중 생성되지만 Git에는 포함되지 않습니다.

| 디렉터리 | 용도 |
| --- | --- |
| `dist/` | 배포 wheel |
| `reports/` | `validate_cdm.py --json` QA 결과 |
| `logs/` | 로컬 실행 로그 |
| `build/`, `*.egg-info/`, `__pycache__/` | 재생성 가능한 빌드/캐시 파일 |

`legacy/`는 이 패키지의 상위 디렉터리에 보관된 과거 참고 코드입니다. 현재
패키지의 Python과 SQL은 `legacy/` 코드에 의존하지 않습니다. 다만 개발
장비에서는 기존에 내려받은 Athena vocabulary 폴더만 외부 입력으로 재사용할
수 있습니다.

## 요구사항

- Windows 및 PowerShell
- Python 3.11 이상
- Microsoft ODBC Driver 18 for SQL Server
- SQL Server와 데이터베이스 생성/변경 권한
- 일본 vocabulary 적재 시 `PATH`에서 실행 가능한 `sqlcmd`
- 라이선스에 따라 별도로 내려받은 완전한 Athena vocabulary 폴더
- 원천 스키마에 맞는 한국 NHIS-NSC 또는 일본 JMDC 데이터베이스

대용량 운영 환경에서는 MDF, LDF, `tempdb` 여유 공간과 디스크 I/O를 먼저
확인해야 합니다. 검증 장비의 기본값은 `F:\database\data`와
`F:\database\log`이며, runner는 명시적 override 없이는 F 이외의 신규
target 위치를 거부합니다.

## 설치

저장소에서 직접 실행하려면:

```powershell
cd C:\path\to\korea-japan-omop-etl
python -m pip install -r requirements.txt
```

검증된 wheel로 설치하려면:

```powershell
python -m pip install `
  .\dist\korea_japan_omop_etl-0.1.1-py3-none-any.whl
```

wheel 설치 후에는 다음 명령을 사용할 수 있습니다.

```text
omop-etl-korea
omop-etl-japan
omop-etl-qa
omop-etl-package-check
```

## 환경 설정

`.env.example`은 설명용이며 자동 로드되지 않습니다. PowerShell 세션이나
배포 환경에서 직접 설정합니다.

```powershell
$env:SQLSERVER_SERVER = 'HOST\INSTANCE'
$env:SQLSERVER_WINDOWS_AUTH = '1'
$env:SQLSERVER_DATA_DIR = 'F:\database\data'
$env:SQLSERVER_LOG_DIR = 'F:\database\log'
$env:SQLSERVER_FILEGROWTH_MB = '4096'
$env:VOCAB_FOLDER = 'C:\path\to\athena-vocabulary'

$env:KOREA_RAW_DB = 'nhisnsc2013original'
$env:KOREA_CDM_DB = 'korea_cohort_cdm_final'
$env:KOREA_MAPPING_DB = 'korea_cohort_cdm_final'

$env:JAPAN_RAW_DB = 'japan_cohort_raw_500k'
$env:JAPAN_CDM_DB = 'japan_cohort_cdm_500k_final'
```

SQL 인증을 사용하면 `SQLSERVER_WINDOWS_AUTH=0`과 함께
`SQLSERVER_USERNAME`, `SQLSERVER_PASSWORD`를 설정합니다. 자격정보는 파일에
커밋하지 않습니다.

## 가장 먼저 할 검증

아래 명령은 데이터베이스를 변경하지 않습니다.

```powershell
python run_korea.py --dry-run
python run_japan.py
python validate_package.py
python -m unittest discover -s tests -v
```

SQL Server가 모든 렌더링 배치를 문법적으로 해석하는지 확인하려면:

```powershell
python validate_package.py `
  --sqlserver-parse `
  --server 'HOST\INSTANCE' `
  --korea-target-db korea_cohort_cdm_final `
  --korea-mapping-db korea_cohort_cdm_final `
  --japan-target-db japan_cohort_cdm_500k_final `
  --vocab-folder $env:VOCAB_FOLDER
```

`PARSEONLY`는 데이터를 변경하지 않지만, 실제 원천 값과 런타임 성능까지
보장하지는 않습니다.

## 한국 ETL 사용법

한국 runner는 단계별 실행을 기본으로 합니다. `--execute`가 없으면
데이터베이스 변경 단계가 실행되지 않습니다.

### 1. 사전 점검

```powershell
python run_korea.py `
  --stage preflight `
  --server 'HOST\INSTANCE' `
  --raw-db nhisnsc2013original `
  --target-db korea_cohort_cdm_final `
  --mapping-db korea_cohort_cdm_final `
  --vocab-folder $env:VOCAB_FOLDER
```

### 2. 기반 단계

```powershell
python run_korea.py --stage ddl --execute
python run_korea.py --stage vocabulary --execute
python run_korea.py --stage master --execute
```

실제 운영에서는 각 명령에 동일한 `--server`, `--raw-db`, `--target-db`,
`--mapping-db`, `--vocab-folder`, `--data-dir`, `--log-dir` 값을 명시하는 것이
좋습니다.

### 3. 도메인 단계

대용량 테이블은 한 번에 하나씩 실행하고 바로 QA하는 것을 권장합니다.

```powershell
python run_korea.py `
  --stage domains `
  --only person `
  --execute
```

도메인 순서는 다음과 같습니다.

```text
location
care_site
person
death
observation_period
visit_occurrence
condition_occurrence
observation
drug_exposure
procedure_occurrence
device_exposure
measurement
payer_plan_period
cost
```

runner가 필요한 선행 테이블을 검사하므로 순서를 건너뛴 실행은 거부됩니다.

### 4. 필수 post 단계

```powershell
python run_korea.py --stage post --execute
```

기본 post는 `cdm_source`만 실행합니다. `generate_era`, `indexing`,
`constraints`는 선택적 대형 작업이며 필요할 때만 `--only`로 명시합니다.
`dose_era`와 과거의 파괴적 data cleansing은 지원 실행 경로에 포함되지
않습니다.

## 일본 ETL 사용법

일본 runner는 인자 없이 실행하면 정적 dry-run을 수행합니다.

```powershell
python run_japan.py
python run_japan.py --preflight
```

신규 target은 다음 순서로 실행합니다.

```powershell
python run_japan.py --stage ddl --execute
python run_japan.py --stage vocabulary --execute
python run_japan.py --stage master --execute
python run_japan.py --stage domains --execute
```

대용량 환경에서는 일본도 도메인별 실행을 권장합니다.

```powershell
python run_japan.py `
  --stage domains `
  --only condition_occurrence `
  --execute
```

기본 지원 순서와 원천 의존 도메인은
[운영 Runbook](docs/RUNBOOK.md)에 정리되어 있습니다.

## QA 사용법

### Quick QA

카탈로그 기반 행 수, vocabulary와 staging 상태를 빠르게 확인합니다.

```powershell
python validate_cdm.py `
  --country korea `
  --server 'HOST\INSTANCE' `
  --cdm-db korea_cohort_cdm_final
```

### Full QA

concept domain, 필수 날짜, person/visit/payer 연결, 기간 경계, 중복 키를
실제 테이블 전체에서 검사합니다.

```powershell
python validate_cdm.py `
  --country korea `
  --server 'HOST\INSTANCE' `
  --cdm-db korea_cohort_cdm_final `
  --full `
  --confirm-full-scan `
  --only drug_exposure `
  --json reports\korea-drug-exposure.json
```

Full QA는 대형 I/O를 발생시키므로 테이블별로 실행하고 다른 ETL이나 QA와
겹치지 않게 합니다.

## 실패 복구

부분 실패 후에는 자동으로 데이터를 지우지 않습니다. 실패 원인과 부분 적재
상태를 확인한 다음 정확히 한 단계만 `--reset`으로 초기화합니다.

```powershell
python run_korea.py `
  --stage domains `
  --only drug_exposure `
  --reset `
  --execute

python run_japan.py `
  --stage domains `
  --only procedure_occurrence `
  --reset `
  --execute
```

한국 master reset은 하위 도메인에 데이터가 있으면 거부됩니다. 같은 장비에서
두 ETL, ETL과 Full QA, 두 Full QA를 동시에 실행하지 마십시오.

## 안전 및 재현성 원칙

- 데이터 변경은 항상 `--execute`를 명시해야 합니다.
- 기존 target과 단계별 선행 산출물을 실행 전에 검사합니다.
- `--reset`은 명시한 실패 단계에만 제한됩니다.
- 신규 target MDF/LDF와 `tempdb` 위치를 검사합니다.
- 날짜와 수치 변환은 가능한 경우 non-throwing 변환을 사용합니다.
- 표준 근거가 없는 행은 잘못된 domain concept으로 채우지 않습니다.
- source value와 deterministic event ID를 보존해 역추적할 수 있게 합니다.
- QA JSON, 실행 명령, 코드 태그, vocabulary 버전을 함께 기록합니다.

## 문서 안내

| 문서 | 내용 |
| --- | --- |
| [RUNBOOK.md](docs/RUNBOOK.md) | 전체 실행 명령, 저장공간, 복구, 릴리스 절차 |
| [MAPPING_POLICY.md](docs/MAPPING_POLICY.md) | 한일 매핑 원칙과 의도적 미지원 정책 |
| [STATUS.md](docs/STATUS.md) | 현재 완료 상태와 선택 작업 |
| [KOREA_FINAL_VALIDATION.md](docs/KOREA_FINAL_VALIDATION.md) | 한국 행 수, 매핑률, QA 결과 |
| [JAPAN_FINAL_VALIDATION.md](docs/JAPAN_FINAL_VALIDATION.md) | 일본 행 수, 매핑률, QA 결과 |
| [RELEASE_VALIDATION.md](docs/RELEASE_VALIDATION.md) | 테스트, SQL 파싱, wheel 해시 |
| [STORAGE_AUDIT.md](docs/STORAGE_AUDIT.md) | SQL Server 파일 위치와 디스크 주의사항 |
| [MIGRATION_MANIFEST.md](docs/MIGRATION_MANIFEST.md) | legacy에서 독립 패키지로 옮긴 범위 |

## 라이선스

이 저장소는 [Apache License 2.0](LICENSE)에 따라 배포됩니다. 제3자 저작권과
라이선스 고지가 포함된 소스 파일은 해당 고지를 그대로 유지합니다.

Athena vocabulary와 원천 의료데이터는 각각의 라이선스와 접근 통제를 따르며
이 저장소의 배포 대상이 아닙니다.
