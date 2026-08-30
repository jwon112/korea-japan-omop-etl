# Japan Final Validation

Validation date: 2026-07-31

Server: `DESKTOP-HBA9S76\SQLEXPRESS01`

RAW database: `japan_cohort_raw_500k`

CDM database: `japan_cohort_cdm_500k_final`

## Accepted Output

| Output | Rows |
| --- | ---: |
| `SEQ_MASTER` | 187,964,411 |
| `person` | 483,968 |
| `observation_period` | 483,968 |
| `death` | 940 |
| `visit_occurrence` | 26,884,608 |
| `condition_occurrence` | 66,173,943 |
| `drug_exposure` | 60,141,860 |
| `procedure_occurrence` | 34,764,000 |
| `payer_plan_period` | 483,968 |
| `cost` | 115,917,144 |

Vocabulary row counts:

| Table | Rows |
| --- | ---: |
| `concept` | 9,904,290 |
| `concept_relationship` | 54,749,168 |
| `concept_ancestor` | 85,502,418 |
| `source_to_concept_map` | 7,285,101 |
| `vocabulary` | 130 |
| `domain` | 50 |
| `concept_class` | 433 |
| `relationship` | 722 |

## Mapping Coverage

| Domain | Mapped | Total | Coverage |
| --- | ---: | ---: | ---: |
| Condition | 65,302,567 | 66,173,943 | 98.68% |
| Drug | 59,021,673 | 60,141,860 | 98.14% |
| Procedure, all source events | 2,389,279 | 34,764,000 | 6.87% |
| Procedure, clinical subset | 2,389,279 | 13,600,924 | 17.57% |

The other 21,163,076 procedure rows are administrative fees identified by the
reviewed policy. They are retained for source fidelity with
`procedure_concept_id = 0`; none was incorrectly marked as mapped.

## Integrity Results

- Person, observation period, death, visit, and payer plan period passed the
  shared full QA checks for required values, dates, person links, active
  concepts, and duplicate primary keys.
- All 483,968 claim-backed persons have one observation period and one payer
  plan period. Their spans match exactly.
- All 940 death records fall inside the observation period, and death date
  equals the source enrollment end date for those death-flagged members.
- Condition targeted QA found zero null required fields, missing visits,
  reversed dates, missing `master_seq`, ID mismatches, and invalid mapped
  Condition concepts.
- Drug targeted QA found zero null required fields, missing visits, reversed
  dates, missing `master_seq`, ID mismatches, source-null rows, end-date rule
  mismatches, and invalid mapped Drug concepts.
- Procedure targeted QA found zero null required fields, missing visits,
  missing `master_seq`, ID mismatches, source-null rows, policy mismatches,
  administrative mapping violations, and invalid mapped Procedure concepts.
- Cost has exactly 55,821,252 Drug, 33,211,284 Procedure, and 26,884,608 Visit
  rows. Required values, event links, total-cost values, charge/cost equality,
  and currency policy all passed. Zero-value source costs are retained; eight
  negative Visit adjustments are retained.

Source-key audits and exact stage-to-target row counts support the
deterministic `master_seq` primary-key policy for visit, condition, drug,
procedure, and cost outputs.

## Performance Record

- Drug mapping: 188.3 seconds; final insert: 1,892.2 seconds.
- Procedure staging: 1,020.7 seconds; mapping: 61.5 seconds; final insert:
  802.6 seconds.
- Cost total: 1,742.8 seconds, including claim staging and all three domains.

These timings are workstation observations, not service-level guarantees.

## Qualified Limitation

The generic shared condition full scan was stopped after 30 minutes because it
was consuming workstation I/O. It was read-only and made no database changes.
The earlier targeted whole-table condition QA completed in about 182 seconds
and passed the checks listed above. Shared QA now applies hash/recompile hints
and reports integrity and duplicate phases separately, but that revised generic
condition query was not rerun during this acceptance window.

## Intentional Empty Tables

`location`, `care_site`, `observation`, `device_exposure`, `measurement`,
`drug_era`, `dose_era`, and `condition_era` are empty by source availability or
documented release policy. They are not failed ETL outputs.
