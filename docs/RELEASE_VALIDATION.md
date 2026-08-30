# Release Validation

Validation date: 2026-08-09

Package version: `0.1.1`

## Code Validation

- Python unit/static tests: 39 passed.
- SQL inventory: 21 Korea assets and 17 Japan assets.
- Rendered SQL batches: 124.
- SQL Server `PARSEONLY`: all 124 batches passed.
- Korea default post execution is limited to `cdm_source`; optional era,
  indexing, and constraint operations require explicit selection.

## Runtime Evidence

- Japan 500K final runtime: accepted in `JAPAN_FINAL_VALIDATION.md`.
- Korea full base-CDM runtime: accepted in `KOREA_FINAL_VALIDATION.md`.
- Korea table-specific full QA passed for every populated clinical and
  supporting output.
- `provider` and era-table emptiness is intentional and documented.

## Wheel

Artifact: `dist/korea_japan_omop_etl-0.1.1-py3-none-any.whl`

Size: 124,147 bytes

SHA-256:
`EA7C78C51D514EE8BA37A9F8B3AA3D157F8A2808B36F21BB2C3D5BDD2E932704`

The wheel was installed without dependency downloads into a fresh isolated
environment and tested from outside the source directory. All four entry
points passed. Archive inspection found 21 Korea SQL files and 17 Japan SQL
files among 50 total wheel entries. Deleted unsupported SQL was confirmed
absent after clearing stale build metadata.

The wheel includes all 38 SQL assets and exposes these entry points:

- `omop-etl-package-check`
- `omop-etl-korea`
- `omop-etl-japan`
- `omop-etl-qa`

## Revision

The `v0.1.1` tag identifies the validated initial public release.

The validated wheel was built from the `v0.1.1` code and packaged SQL content.
Runtime reports and the wheel remain ignored local artifacts; their accepted
counts and checksum are recorded in this repository.
