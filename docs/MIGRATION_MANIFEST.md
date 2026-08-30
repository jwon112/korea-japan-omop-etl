# Migration Manifest

Snapshot date: 2026-07-29

This repository was extracted from a larger project working directory. After
extraction, the original material was moved into the sibling `../legacy`
directory. That archive is not a runtime dependency of this package.

## Included

- Korea Python runner from
  `../legacy/ETL---Korean-NSC/etlKoreanNSC/scripts/execute_korean_etl.py`
- Korea active SQL set from
  `../legacy/ETL---Korean-NSC/etlKoreanNSC/inst/sql/sql_server`
- Japan relational JMDC SQL set from
  `../legacy/ETL---Japan-Cohort/etlJapanCohort/inst/sql/sql_server_jmdc_sample`
- Shared read-only QA from the former repository-level `validate_cdm.py`
- The upstream Korea ETL license and attribution
- New consolidated Japan runner and closeout documentation

The migrated SQL reflects the current working-tree versions, including
uncommitted closeout fixes that had not yet been packaged in the old layout.

## Deliberately Excluded

- Source health data and JMDC/NHIS extracts
- SQL Server MDF, LDF, backup, and converted result files
- Athena vocabulary CSV files
- Jupyter notebooks and exploratory outputs
- Legacy R/SqlRender orchestration
- 30K sample loaders and smoke-test-only entry points
- 500K CSV/SAS raw ingestion helpers
- Vocabulary copy and historical backfill/repair scripts
- Debug logs, temporary SQL, Office artifacts, and status snapshots that only
  describe obsolete intermediate databases

## Boundary

The packaged ETL starts from populated country-specific RAW SQL Server
databases. Raw-file ingestion is environment- and license-specific and is not
part of the release artifact. Athena vocabulary files are external licensed
inputs and must be supplied at runtime.
