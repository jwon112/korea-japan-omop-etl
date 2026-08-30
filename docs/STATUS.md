# Closeout Status

Last updated: 2026-08-09

## Deliverable

The deliverable is a reproducible Python-orchestrated SQL Server ETL package,
not only a converted database. Korea NHIS-NSC and Japan JMDC transformations,
QA, storage guards, operating documentation, and packaged SQL are independent
of the sibling `legacy` archive. Runtime vocabulary files remain an external
licensed prerequisite.

## Accepted State

- Korea and Japan both have accepted relational CDM runtimes.
- Korea base domains and `cdm_source` completed in
  `korea_cohort_cdm_final`; see `KOREA_FINAL_VALIDATION.md`.
- Japan enabled domains completed in `japan_cohort_cdm_500k_final`; see
  `JAPAN_FINAL_VALIDATION.md`.
- MDF, LDF, and active `tempdb` files used for final processing are on F:.
- Mapping-rate expansion is frozen. Unmapped source events remain concept ID
  `0` when no reviewed standard bridge exists.
- Table-specific full QA passed for every populated Korea output and the
  accepted Japan outputs.
- Offline acceptance covers 39 tests, 21 Korea SQL assets, 17 Japan SQL
  assets, and 124 rendered batches.
- SQL Server `PARSEONLY` accepts all 124 batches.

## Intentional Omissions

- Korea `provider` is empty because a stable individual-provider identifier
  is unavailable in the reviewed source model.
- Korea `drug_era` and `condition_era` are optional. No `dose_era`
  transformation is packaged because normalized dose units are absent.
- Japan source-dependent and policy-deferred empty tables are documented in
  `JAPAN_FINAL_VALIDATION.md`.
- Physical `indexing` and `constraints` SQL is packaged and parser-validated
  but was not run on the accepted SATA-HDD databases. It requires explicit
  selection and is deployment-specific.
- The obsolete destructive `data_cleansing` script is not packaged.

## Handoff Position

The cleanup release, final wheel, clean-install validation, package
content audit, and runtime documentation are complete. No required ETL or QA
stage remains. Optional physical indexes, constraints, and Korea era outputs
may be run later only when a deployment explicitly requires them.
