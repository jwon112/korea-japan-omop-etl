# Korea Final Validation

Acceptance date: 2026-08-09

Source database: `nhisnsc2013original`

Target database: `korea_cohort_cdm_final`

## Storage And Vocabulary

- Data file: `F:\database\data\korea_cohort_cdm_final.mdf`
- Log file: `F:\database\log\korea_cohort_cdm_final_log.ldf`
- SQL Server `tempdb`: F drive
- `CONCEPT`: 9,904,290
- `CONCEPT_RELATIONSHIP`: 54,749,168
- `CONCEPT_ANCESTOR`: 85,502,418
- `SOURCE_TO_CONCEPT_MAP`: 7,285,101

## Accepted Outputs

| Output | Rows | Standard mapped |
| --- | ---: | ---: |
| `location` | 312 | n/a |
| `care_site` | 131,401 | n/a |
| `person` | 1,125,691 | n/a |
| `observation_period` | 1,256,091 | n/a |
| `death` | 55,940 | n/a |
| `visit_occurrence` | 14,467,184 | 100.00% |
| `condition_occurrence` | 31,462,215 | 12.41% |
| `drug_exposure` | 46,414,103 | 99.95% |
| `procedure_occurrence` | 45,429,830 | 35.37% |
| `device_exposure` | 1,020,545 | 93.65% |
| `measurement` | 33,440,451 | 100.00% |
| `observation` | 33,218,599 | 87.06% |
| `payer_plan_period` | 12,132,529 | n/a |
| `cost` | 105,006,032 | n/a |
| `cdm_source` | 1 | n/a |

Mapping percentages describe output rows with a positive, active standard
concept in the expected domain. Low condition and procedure coverage is not
hidden by assigning unsupported concepts; unmapped source events remain
concept ID `0` according to the mapping policy.

## Full QA Evidence

Table-specific full QA JSON exists for person, death, observation period,
visit, condition, drug, procedure, device, measurement, observation, payer,
cost, and CDM source. Across those reports:

- required dates, date order, future dates, and death boundaries passed;
- person, visit, care-site, payer, and cost-event references passed;
- mapped concepts were active standards in their expected domains;
- observation and payer coverage boundaries passed;
- no duplicate primary keys were found;
- cost contained no mapping-expansion duplicates or amountless rows.

The final catalog snapshot is
`reports/korea-final-quick-20260809.json`. Reports are local runtime evidence
and are excluded from the distributable repository.

## Intentional Empty Tables

- `provider`: NHIS claim data used here identifies facilities but does not
  provide a stable, reviewed individual-provider identifier. Event
  `provider_id` fields therefore remain null.
- `drug_era` and `condition_era`: optional derived outputs, not required for
  base CDM acceptance. A window-based implementation is available through the
  explicit `generate_era` post step.
- `dose_era`: intentionally empty because claim quantity is not a normalized
  dose and no standard dose unit is available. No transformation is packaged.

## Optional Physical Steps

`indexing` and `constraints` are packaged and pass SQL Server parser
validation, but were not executed against the accepted database. They are
deployment-specific physical design operations and would require long scans
of tables containing up to 105 million rows on the current SATA HDD. Logical
integrity was instead demonstrated by table-specific full QA. Both operations
require explicit `--only` selection.

The obsolete destructive `data_cleansing` script is not packaged. Accepted
ETL rules enforce the reviewed date and relational boundaries during insert.
