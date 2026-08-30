# ETL Runbook

## 1. Prepare the Environment

Install Python dependencies:

```powershell
python -m pip install -r requirements.txt
```

Set the workstation-specific values. The defaults already target the current
SQL Server instance and F drive, but explicit values make the run auditable.

```powershell
$env:SQLSERVER_SERVER = 'HOST\INSTANCE'
$env:SQLSERVER_WINDOWS_AUTH = '1'
$env:SQLSERVER_DATA_DIR = 'F:\database\data'
$env:SQLSERVER_LOG_DIR = 'F:\database\log'
$env:SQLSERVER_FILEGROWTH_MB = '4096'
$env:VOCAB_FOLDER = 'C:\path\to\athena-vocabulary'
```

For SQL authentication, set `SQLSERVER_WINDOWS_AUTH=0`,
`SQLSERVER_USERNAME`, and `SQLSERVER_PASSWORD`.

The Athena directory must contain the standard CSV files listed by the
preflight checks. SQL Server's service account must be able to read that
directory because the SQL uses `BULK INSERT`.

For the current development workspace, the previously downloaded Athena files
are archived outside this repository under `../legacy/vocabulary`. They can be
reused without creating a code dependency on `legacy`:

```powershell
$env:VOCAB_FOLDER = (Resolve-Path '..\legacy\vocabulary').Path
```

Release environments must provide their own licensed Athena folder.

### Storage Safety

Both runners require new MDF/LDF paths to be on `F:`. They reject a C-drive
environment variable or CLI override before connecting, verify existing target
files during preflight/resume, and verify new target files immediately after
database creation. `--allow-non-f-storage` is an explicit emergency/portable
deployment override and must not be used on the current workstation.

The target guard does not relocate SQL Server system databases or existing RAW
databases. Database-changing runs also stop when `tempdb` is outside F:.
`--allow-tempdb-off-f` bypasses only that system-database check; it does not
weaken the F-drive target guard. On the validated workstation, active `tempdb`
files have been moved to `F:\database\data` and `F:\database\log`, so this
override is not needed.

Fresh Korea and Japan targets default to a 150 GB data file, 50 GB log file,
and 4 GB growth increment. These values avoid repeated autogrowth during the
large master and clinical-domain loads and can be overridden with
`--initial-data-mb`, `--initial-log-mb`, and `--filegrowth-mb` or the
country-specific environment variables in `.env.example`. Confirm adequate F:
free space before creating both final targets.

The Korea RAW database currently remains on C:. Even with the target and
`tempdb` on F:, its source reads can affect normal desktop work. Never overlap
large stages or full QA scans.

## 2. Offline Validation

These commands do not connect to SQL Server:

```powershell
python run_korea.py --dry-run
python run_japan.py
python validate_package.py
python -m unittest discover -s tests -v
```

Optional read-only SQL Server parser validation:

```powershell
python validate_package.py `
  --sqlserver-parse `
  --server 'HOST\INSTANCE' `
  --korea-target-db korea_cohort_cdm `
  --japan-target-db japan_cohort_cdm_500k `
  --vocab-folder $env:VOCAB_FOLDER
```

`PARSEONLY` validates T-SQL grammar but does not execute transformation SQL or
prove source-column or mapping semantics. Cross-batch DDL means SQL Server
`NOEXEC` is not a reliable substitute for a staged fresh run. The target
options must name existing databases because SQL Server validates `USE`
targets even in `PARSEONLY` mode.

## 3. Read-Only Preflight

```powershell
python run_korea.py --stage preflight
python run_japan.py --preflight
```

Preflight checks database existence, expected source tables, source row
counts, SQL assets, and fresh-run vocabulary prerequisites.

## 4. Korea Fresh Run

The Korea source defaults to `nhisnsc2013original`. Keep the target name
constant across staged commands:

```powershell
$env:KOREA_CDM_DB = 'korea_cohort_cdm_final'
$env:KOREA_MAPPING_DB = 'korea_cohort_cdm_final'

python run_korea.py --stage ddl --execute
python run_korea.py --stage vocabulary --execute
python run_korea.py --stage master --execute
```

`master` can build roughly 138 million rows. It logs seven source-specific
batches, preserves 30T/60T source `AMT` for the later cost step, and creates
unique source-key indexes. Schedule it while normal desktop work is paused.
Then execute domains one at a time in runner order:

```powershell
python run_korea.py --stage domains --only location --execute
python run_korea.py --stage domains --only care_site --execute
python run_korea.py --stage domains --only person --execute
python run_korea.py --stage domains --only death --execute
python run_korea.py --stage domains --only observation_period --execute
python run_korea.py --stage domains --only visit_occurrence --execute
```

Continue in this order: `condition_occurrence`, `observation`,
`drug_exposure`, `procedure_occurrence`, `device_exposure`, `measurement`,
`payer_plan_period`, and `cost`. Run post stages only after domain QA.

For a reviewed partial failure, reset exactly one step. A master reset is
refused once any downstream table has rows. Domain and post resets are refused
when a populated downstream dependency exists:

```powershell
python run_korea.py --stage master --reset --execute

python run_korea.py --stage domains `
  --only drug_exposure --reset --execute

python run_korea.py --stage post `
  --only generate_era --reset --execute
```

The Korea cost step requires completed visit, drug, procedure, device, and
payer outputs. It reuses `SEQ_MASTER.total_cost`; it does not rescan 30T/60T or
infer source table from a drug type concept.

The default Korea post command runs only the required `cdm_source` metadata
step:

```powershell
python run_korea.py --stage post --execute
```

`generate_era`, `indexing`, and `constraints` are optional, potentially long
operations and must be selected explicitly with `--only`. No `dose_era` step
is packaged because the source does not provide normalized dose units. The
obsolete destructive cleanup script is also excluded. Do not run optional
post steps concurrently with desktop work or with each other.

## 5. Japan Fresh Run

The Japan source defaults to `japan_cohort_raw_500k`. Use staged commands so
each long phase can be validated before the next one:

```powershell
$env:JAPAN_CDM_DB = 'japan_cohort_cdm_500k_final'

python run_japan.py --preflight
python run_japan.py --stage ddl --execute
python run_japan.py --stage vocabulary --execute
python run_japan.py --stage master --execute
python run_japan.py --stage domains --execute
```

The default set excludes source-dependent or policy-deferred domains:
`location`, `care_site`, `observation`, `device_exposure`, and `measurement`.
They can be selected explicitly with `--only` when their source tables exist.
Japan era tables are optional derived outputs and are not generated by this
release.

For a large relational source, prefer one domain per command. This makes
recovery and workstation scheduling explicit:

```powershell
python run_japan.py --stage domains --only person --execute
python run_japan.py --stage domains --only observation_period --execute
python run_japan.py --stage domains --only visit_occurrence --execute
python run_japan.py --stage domains --only condition_occurrence --execute
python run_japan.py --stage domains --only drug_exposure --execute
python run_japan.py --stage domains --only procedure_occurrence --execute
python run_japan.py --stage domains --only payer_plan_period --execute
python run_japan.py --stage domains --only death --execute
python run_japan.py --stage domains --only cost --execute
```

The observation period uses valid `JP_PATIENT` enrollment start/end dates for
claim-backed persons, with claims months only as a fallback. Payer plan periods
reuse that span. The cost step depends on completed visit, drug, and procedure
outputs and their deterministic staging tables. In the accepted 500K run,
`cost` produced about 116 million rows and took about 29 minutes; schedule it
as a standalone stage.

Resume a reviewed failed domain only:

```powershell
python run_japan.py `
  --target-db japan_cohort_cdm_500k_final `
  --stage domains --only procedure_occurrence --reset --execute
```

`--resume` remains an alias for `--stage domains`. `--reset` is never implicit
and is accepted only with the domains stage.

## 6. QA and Acceptance

Quick QA uses catalog row counts and is read-only:

```powershell
python validate_cdm.py --country korea --cdm-db korea_cohort_cdm_final
python validate_cdm.py --country japan --cdm-db japan_cohort_cdm_500k_final
```

Quick output includes ETL domains, supporting tables, and country-specific
staging tables that exist in the target.

Full QA scans populated tables and can create heavy I/O:

```powershell
python validate_cdm.py --country japan `
  --cdm-db japan_cohort_cdm_500k_final `
  --full --confirm-full-scan --only person `
  --json reports\japan-final.json
```

Run large tables one at a time by changing `--only` to
`condition_occurrence`, `drug_exposure`, `procedure_occurrence`, or `cost`.
The command prints separate progress messages for integrity and duplicate-key
phases. A large shared query can still take materially longer than the ETL's
targeted QA, so stop and review a scan that is harming workstation
responsiveness instead of starting another workload beside it.

Do not run two full ETLs, an ETL and full QA, or two full QA scans
simultaneously. Record the exact code revision, environment variables,
commands, row counts, and QA JSON used for final acceptance. The accepted
Japan 500K record is in `docs/JAPAN_FINAL_VALIDATION.md`.

## 7. Build the Release Artifact

Build without downloading an isolated build environment:

```powershell
$root = (Resolve-Path '.').Path
@('build', 'dist', 'src\korea_japan_omop_etl.egg-info') |
  ForEach-Object {
    $path = Join-Path $root $_
    if (Test-Path -LiteralPath $path) {
      Remove-Item -LiteralPath $path -Recurse -Force
    }
  }

python -m pip wheel . `
  --no-deps --no-build-isolation --no-cache-dir `
  -w dist
```

Cleaning generated metadata first is required after SQL files are removed;
otherwise an old `SOURCES.txt` can reintroduce deleted assets into the wheel.

Install the wheel in a clean virtual environment and run
`omop-etl-package-check`, `omop-etl-korea --dry-run`, `omop-etl-japan`, and
`omop-etl-qa --help`. The wheel must contain all 38 SQL assets and all four
console entry points.
