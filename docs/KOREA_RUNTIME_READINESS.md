# Korea Runtime Readiness

Review date: 2026-08-09

RAW database: `nhisnsc2013original`

Accepted CDM database: `korea_cohort_cdm_final`

## Position

The complete required Korea pipeline has passed staged runtime and
table-specific full QA. Final row counts, mapping coverage, intentional empty
tables, and QA evidence are recorded in `KOREA_FINAL_VALIDATION.md`.

The package uses explicit `ddl`, `vocabulary`, `master`, `domains`, and `post`
stages. Database-changing operations require `--execute`; targeted recovery
requires one `--only` key and `--reset`. Windows idle sleep is inhibited only
while SQL batch groups or full QA are active.

## Proven Runtime Corrections

- Fresh target creation, log/data growth, and `tempdb` placement are guarded
  for F-drive storage.
- The complete Athena vocabulary is loaded before mapping-dependent stages.
- `SEQ_MASTER` preserves source-detail cost and has unique source-key access.
- Person rollup avoids the legacy repeated scans that previously ran for more
  than 40 hours.
- Visits and downstream clinical events are bounded by accepted observation
  and visit periods.
- Condition, drug, procedure, and device mappings accept only active standard
  concepts in the expected domain.
- Health-check staging uses typed indexed keys; observation and measurement
  use non-throwing conversion.
- Drug, procedure, and device read 30T/60T directly without large tempdb claim
  staging.
- Cost is written once per source event, excludes amountless rows, and does
  not duplicate amounts across mapping expansions.
- Payer periods are contained within observation periods.

## Operational Constraints

- The RAW database remains on C:. Future clean rebuilds should run large
  stages separately from normal desktop work.
- F: is a SATA HDD. Do not overlap ETL, full QA, optional era generation,
  indexing, or constraints.
- `provider` is intentionally empty; source claims identify facilities rather
  than reviewed individual providers.
- The default post stage runs only `cdm_source`.
- `generate_era`, `indexing`, and `constraints` require explicit `--only`.
  No `dose_era` transformation is packaged because normalized dose values and
  units are unavailable. The OMOP DDL table remains empty.
- The obsolete destructive `data_cleansing` step is not packaged.

## Validation Baseline

- Python unit/static tests: 39 passed.
- Packaged SQL: 21 Korea and 17 Japan files.
- Rendered SQL: 124 batches.
- SQL Server `PARSEONLY`: 124 batches passed.
- Final Korea quick snapshot:
  `reports/korea-final-quick-20260809.json`.
