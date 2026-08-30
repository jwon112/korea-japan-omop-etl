from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from omop_etl import japan, korea, package_check
from omop_etl import qa


class StaticPipelineTests(unittest.TestCase):
    def test_korea_all_sql_renders(self):
        config = korea.default_config()
        files = [
            "000.OMOP CDM sql server ddl.sql",
            "001.Import_voca.sql",
            korea.MASTER_STEP.sql_file,
            *(step.sql_file for step in korea.DOMAIN_STEPS),
            *(step.sql_file for step in korea.POST_STEPS),
        ]
        for sql_file in files:
            with self.subTest(sql_file=sql_file):
                self.assertTrue(korea.render_sql(config, sql_file).strip())

    def test_korea_master_preserves_detail_cost_and_source_uniqueness(self):
        config = korea.default_config()
        rendered = korea.render_sql(config, "010.Master_table.sql")
        self.assertIn("total_cost", rendered)
        self.assertIn("TRY_CONVERT(FLOAT, a.amt)", rendered)
        self.assertIn("UX_NHIS_CLAIM_PERSON_key_seq", rendered)
        self.assertIn("UX_SEQ_MASTER_130_source_key", rendered)
        self.assertIn("UX_SEQ_MASTER_160_source_key", rendered)
        self.assertGreater(len(korea.split_batches(rendered)), 5)

    def test_korea_person_uses_bounded_rollup_instead_of_legacy_branches(self):
        config = korea.default_config()
        rendered = korea.render_sql(config, "040.Person.sql")
        self.assertIn("#person_rollup", rendered)
        self.assertIn("MIN(CASE WHEN age_group = 0", rendered)
        self.assertIn("MAX(stnd_y) AS latest_year", rendered)
        self.assertIn("OPTION (MAXDOP 4, RECOMPILE)", rendered)
        self.assertEqual(rendered.upper().count("INSERT INTO"), 1)
        self.assertNotIn("NOT IN (", rendered.upper())

    def test_korea_visit_deduplicates_health_check_years(self):
        config = korea.default_config()
        rendered = korea.render_sql(config, "070.Visit_occurrence.sql")
        self.assertIn("SELECT DISTINCT", rendered)
        self.assertIn("TRY_CONVERT(DATE", rendered)
        self.assertIn("m.source_table = 'GJT'", rendered)
        self.assertIn("OBSERVATION_PERIOD op", rendered)
        self.assertIn("v.visit_end_date <= op.observation_period_end_date", rendered)
        self.assertIn("OPTION (HASH JOIN, RECOMPILE, MAXDOP 4)", rendered)
        self.assertEqual(len(korea.split_batches(rendered)), 2)

    def test_korea_cost_reuses_master_cost_without_type_filter(self):
        config = korea.default_config()
        rendered = korea.render_sql(config, "150.Cost.sql")
        self.assertIn("m.total_cost", rendered)
        self.assertIn("drug_exposure_id / CAST(100 AS BIGINT)", rendered)
        self.assertIn("procedure_occurrence_id / CAST(100 AS BIGINT)", rendered)
        self.assertNotIn("drug_type_concept_id=38000177", rendered)
        self.assertNotIn("left(a.drug_exposure_id, 10)", rendered.lower())
        self.assertIn("TRY_CONVERT(BIGINT, key_seq)", rendered)
        self.assertIn("TRY_CONVERT(INT, person_id)", rendered)
        self.assertIn("drug_exposure_id % CAST(100 AS BIGINT) = 1", rendered)
        self.assertIn(
            "procedure_occurrence_id % CAST(100 AS BIGINT) = 1",
            rendered,
        )
        self.assertIn("device_exposure_id % CAST(100 AS BIGINT) = 1", rendered)
        self.assertEqual(rendered.upper().count("INSERT INTO"), 4)
        self.assertGreaterEqual(len(korea.split_batches(rendered)), 6)

    def test_korea_observation_period_uses_safe_gap_islands(self):
        config = korea.default_config()
        rendered = korea.render_sql(config, "060.Observation_period.sql")
        self.assertIn("TRY_CONVERT(INT, stnd_y)", rendered)
        self.assertIn("LAG(end_date)", rendered)
        self.assertIn("start_date <= end_date", rendered)
        self.assertNotIn("convert(date, a.stnd_y", rendered.lower())

    def test_korea_manual_mappings_are_vocabulary_guarded(self):
        config = korea.default_config()
        death = korea.render_sql(config, "050.Death.sql")
        measurement = korea.render_sql(config, "130.Measurement.sql")
        self.assertIn("c.standard_concept", death)
        self.assertIn("c.domain_id <> 'Condition'", death)
        self.assertIn("c.domain_id <> 'Measurement'", measurement)
        self.assertIn("c.domain_id <> 'Unit'", measurement)

    def test_korea_event_id_allocation_is_guarded(self):
        config = korea.default_config()
        files = (
            "080.Condition_occurrence.sql",
            "100.Drug_exposure.sql",
            "110.Procedure_occurrence.sql",
            "120.Device_exposure.sql",
        )
        for sql_file in files:
            with self.subTest(sql_file=sql_file):
                rendered = korea.render_sql(config, sql_file)
                self.assertIn("COUNT_BIG(*) > 99", rendered)
                self.assertIn("THROW 5102", rendered)

    def test_korea_condition_is_single_pass_and_visit_anchored(self):
        config = korea.default_config()
        rendered = korea.render_sql(config, "080.Condition_occurrence.sql")
        self.assertEqual(rendered.upper().count("INSERT INTO"), 1)
        self.assertIn("VISIT_OCCURRENCE v", rendered)
        self.assertIn("v.visit_occurrence_id = sm.key_seq", rendered)
        self.assertIn("c.standard_concept = 'S'", rendered)
        self.assertIn("c.domain_id = 'Condition'", rendered)
        self.assertIn("COALESCE(m.target_concept_id, 0)", rendered)
        self.assertIn("OPTION (HASH JOIN, RECOMPILE, MAXDOP 4)", rendered)

    def test_korea_drug_is_single_pass_safe_and_visit_anchored(self):
        config = korea.default_config()
        rendered = korea.render_sql(config, "100.Drug_exposure.sql")
        target_insert = (
            f"INSERT INTO {config.target_database}.dbo.DRUG_EXPOSURE".upper()
        )
        self.assertEqual(rendered.count(f"FROM {config.raw_database}.dbo.NHID_30"), 1)
        self.assertEqual(rendered.count(f"FROM {config.raw_database}.dbo.NHID_60"), 1)
        self.assertNotIn("#drug_claim", rendered)
        self.assertNotIn("#drug_source", rendered)
        self.assertEqual(rendered.upper().count(target_insert), 2)
        self.assertIn(
            "s.drug_start_date BETWEEN s.visit_start_date AND s.visit_end_date",
            rendered,
        )
        self.assertIn("COALESCE(m.target_concept_id, 0)", rendered)
        self.assertIn("c.domain_id = 'Drug'", rendered)
        self.assertIn("c.standard_concept = 'S'", rendered)
        self.assertIn("TRY_CONVERT(", rendered)
        self.assertNotIn("ISNUMERIC", rendered.upper())
        self.assertNotIn("delete from", rendered.lower())

    def test_korea_procedure_is_single_pass_safe_and_visit_anchored(self):
        config = korea.default_config()
        rendered = korea.render_sql(config, "110.Procedure_occurrence.sql")
        target_insert = (
            f"INSERT INTO {config.target_database}.dbo.PROCEDURE_OCCURRENCE".upper()
        )
        self.assertEqual(rendered.upper().count(target_insert), 2)
        self.assertEqual(rendered.count(f"FROM {config.raw_database}.dbo.NHID_30"), 1)
        self.assertEqual(rendered.count(f"FROM {config.raw_database}.dbo.NHID_60"), 1)
        self.assertIn(
            "procedure_date BETWEEN visit_start_date AND visit_end_date",
            rendered,
        )
        self.assertIn("COALESCE(m.target_concept_id, 0)", rendered)
        self.assertIn("c.domain_id = 'Procedure'", rendered)
        self.assertIn("c.standard_concept = 'S'", rendered)
        self.assertIn("#device_code", rendered)
        self.assertNotIn("ISNUMERIC", rendered.upper())
        self.assertNotIn("#duplicated", rendered)

    def test_korea_device_is_single_pass_safe_and_visit_anchored(self):
        config = korea.default_config()
        rendered = korea.render_sql(config, "120.Device_exposure.sql")
        target_insert = (
            f"INSERT INTO {config.target_database}.dbo.DEVICE_EXPOSURE".upper()
        )
        self.assertEqual(rendered.upper().count(target_insert), 2)
        self.assertEqual(rendered.count(f"FROM {config.raw_database}.dbo.NHID_30"), 1)
        self.assertEqual(rendered.count(f"FROM {config.raw_database}.dbo.NHID_60"), 1)
        self.assertIn(
            "s.device_start_date BETWEEN s.visit_start_date AND s.visit_end_date",
            rendered,
        )
        self.assertIn("COALESCE(m.target_concept_id, 0)", rendered)
        self.assertIn("c.domain_id = 'Device'", rendered)
        self.assertIn("c.standard_concept = 'S'", rendered)
        self.assertIn("#procedure_code", rendered)
        self.assertIn("d.death_date", rendered)
        self.assertNotIn("ISNUMERIC", rendered.upper())
        self.assertNotIn("#duplicated", rendered)

    def test_korea_observation_is_staged_and_safely_dated(self):
        config = korea.default_config()
        rendered = korea.render_sql(config, "090.Observation.sql")
        self.assertGreaterEqual(len(korea.split_batches(rendered)), 8)
        self.assertIn("TRY_CONVERT(DATE, CONCAT(a.hchk_year, '0101'), 112)", rendered)
        self.assertNotIn("a.hchk_year+'0101'", rendered)
        self.assertIn("VISIT_OCCURRENCE v", rendered)
        self.assertIn("OBSERVATION_PERIOD op", rendered)
        self.assertIn("SET value_as_concept_id = NULL", rendered)
        self.assertIn("IX_GJ_VERTICAL_type_year_person", rendered)
        self.assertIn("TRY_CONVERT(varchar(4), hchk_year) as hchk_year", rendered)
        self.assertIn("TRY_CONVERT(varchar(4), STND_Y) as hchk_year", rendered)
        self.assertGreaterEqual(
            rendered.count("TRY_CONVERT(int, person_id) as person_id"), 2
        )
        self.assertNotIn("TRY_CONVERT(INT, a.person_id)", rendered)
        self.assertNotIn("TRY_CONVERT(INT, a.hchk_year)", rendered)
        self.assertNotIn("substring(a.meas_type", rendered)
        self.assertIn("(meas_type, hchk_year, person_id)", rendered)
        self.assertIn("WITH (MAXDOP = 1, SORT_IN_TEMPDB = OFF)", rendered)
        self.assertIn("OPTION (MAXDOP 2, RECOMPILE)", rendered)

    def test_korea_measurement_is_single_pass_safe_and_visit_anchored(self):
        config = korea.default_config()
        rendered = korea.render_sql(config, "130.Measurement.sql")
        target_insert = (
            f"INSERT INTO {config.target_database}.dbo.MEASUREMENT".upper()
        )
        self.assertEqual(rendered.upper().count(target_insert), 1)
        self.assertEqual(
            rendered.count(
                f"FROM {config.target_database}.dbo.GJ_VERTICAL"
            ),
            1,
        )
        self.assertIn("VISIT_OCCURRENCE v", rendered)
        self.assertIn("v.visit_occurrence_id = c.master_seq", rendered)
        self.assertIn(
            "BETWEEN v.visit_start_date AND v.visit_end_date",
            rendered,
        )
        self.assertIn(
            "TRY_CONVERT(DATE, CONCAT(a.hchk_year, '0101'), 112)",
            rendered,
        )
        self.assertIn("TRY_CONVERT(FLOAT, a.meas_value)", rendered)
        self.assertIn("c.master_seq * CONVERT(BIGINT, 100)", rendered)
        self.assertIn("OPTION (RECOMPILE, MAXDOP 2)", rendered)
        self.assertNotIn("a.hchk_year+'0101'", rendered)
        self.assertNotIn("TRY_CONVERT(INT, a.person_id)", rendered)
        self.assertNotIn("TRY_CONVERT(INT, a.hchk_year)", rendered)

    def test_korea_payer_period_is_observation_anchored(self):
        config = korea.default_config()
        rendered = korea.render_sql(config, "140.Payer_plan_period.sql")
        self.assertIn("OBSERVATION_PERIOD op", rendered)
        self.assertIn(
            "c.start_date >= op.observation_period_start_date",
            rendered,
        )
        self.assertIn("<= op.observation_period_end_date", rendered)
        steps = {step.key: step for step in korea.DOMAIN_STEPS}
        self.assertIn(
            "observation_period",
            steps["payer_plan_period"].requires_nonempty,
        )

    def test_korea_dependency_graph_protects_links_and_cost(self):
        steps = {step.key: step for step in korea.DOMAIN_STEPS}
        self.assertIn("location", steps["person"].requires_nonempty)
        self.assertIn("care_site", steps["visit_occurrence"].requires_nonempty)
        linked = {
            "condition_occurrence",
            "observation",
            "drug_exposure",
            "procedure_occurrence",
            "device_exposure",
            "measurement",
        }
        for key in linked:
            with self.subTest(step=key):
                self.assertIn(
                    "visit_occurrence",
                    steps[key].requires_nonempty,
                )
        self.assertTrue(
            {
                "drug_exposure",
                "procedure_occurrence",
                "device_exposure",
                "payer_plan_period",
            }.issubset(steps["cost"].requires_nonempty)
        )
        self.assertIn("observation", steps["measurement"].requires_nonempty)
        era = next(step for step in korea.POST_STEPS if step.key == "generate_era")
        self.assertIn("condition_era", era.additional_targets)

    def test_korea_post_defaults_are_closeout_safe(self):
        self.assertEqual(korea.DEFAULT_POST_STEP_KEYS, {"cdm_source"})
        selected = korea.selected_steps(
            korea.POST_STEPS,
            korea.DEFAULT_POST_STEP_KEYS,
        )
        self.assertEqual([step.key for step in selected], ["cdm_source"])

    def test_korea_era_generation_uses_running_intervals(self):
        config = korea.default_config()
        rendered = korea.render_sql(config, "300.GenerateEra.sql")
        self.assertIn("previous_max_end", rendered)
        self.assertIn("ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING", rendered)
        self.assertIn("SUM(CONVERT(BIGINT, b.starts_new_era)) OVER", rendered)
        self.assertIn("ingredient.standard_concept = 'S'", rendered)
        self.assertNotIn("E2.EVENT_DATE <= E1.EVENT_DATE", rendered)
        self.assertGreaterEqual(len(korea.split_batches(rendered)), 6)

    def test_korea_unsupported_destructive_steps_are_not_packaged(self):
        post_keys = {step.key for step in korea.POST_STEPS}
        self.assertNotIn("dose_era", post_keys)
        self.assertFalse(hasattr(korea, "DATA_CLEANSING_STEP"))
        sql_dir = korea.default_config().sql_dir
        self.assertFalse((sql_dir / "310.Dose_era.sql").exists())
        self.assertFalse((sql_dir / "900.data_cleansing.sql").exists())

    def test_korea_runner_exposes_guarded_reset(self):
        parser = korea.build_parser()
        args = parser.parse_args(
            [
                "--stage",
                "domains",
                "--only",
                "drug_exposure",
                "--reset",
                "--execute",
            ]
        )
        self.assertTrue(args.reset)
        self.assertEqual(args.only, "drug_exposure")

    def test_japan_all_sql_renders(self):
        config = japan.default_config()
        self.assertTrue(japan.render_ddl_sql(config).strip())
        self.assertTrue(japan.render_vocabulary_sql(config).strip())
        self.assertTrue(japan.render_domain_sql(config, japan.MASTER_SQL).strip())
        for step in japan.DOMAIN_STEPS:
            with self.subTest(sql_file=step.sql_file):
                self.assertTrue(
                    japan.render_domain_sql(config, step.sql_file).strip()
                )

    def test_japan_function_ddl_uses_schema_qualified_name(self):
        config = japan.default_config()
        rendered = japan.render_domain_sql(config, japan.MASTER_SQL)
        self.assertIn(
            "CREATE OR ALTER FUNCTION dbo.fn_jmdc_date",
            rendered,
        )
        self.assertNotIn(
            f"CREATE OR ALTER FUNCTION "
            f"{config.target_database}.{config.schema}.fn_jmdc_date",
            rendered,
        )
        self.assertNotIn(
            "RETURN DATEFROMPARTS(@year, @month, @day)",
            rendered,
        )

    def test_japan_visit_month_conversion_is_non_throwing(self):
        config = japan.default_config()
        rendered = japan.render_domain_sql(
            config,
            "070.Visit_occurrence_japan.sql",
        )
        self.assertNotIn(
            "CAST(CAST(c.month_and_year_of_medical_care AS INT)",
            rendered,
        )
        self.assertIn(
            "TRY_CONVERT(INT, c.month_and_year_of_medical_care)",
            rendered,
        )
        self.assertNotIn("1900-01-01", rendered)
        self.assertIn("r.visit_start_date IS NOT NULL", rendered)

    def test_japan_relational_spine_uses_claims_only(self):
        config = japan.default_config()
        person_sql = japan.render_domain_sql(
            config,
            "040.Person_japan.sql",
        )
        visit_sql = japan.render_domain_sql(
            config,
            "070.Visit_occurrence_japan.sql",
        )
        for rendered in (person_sql, visit_sql):
            self.assertIn("JP_CLAIMS", rendered)
            self.assertNotIn("FROM japan_cohort_raw_500k.dbo.JP_DIAGNOSIS", rendered)
            self.assertNotIn("FROM japan_cohort_raw_500k.dbo.JP_DRUG", rendered)
            self.assertNotIn("FROM japan_cohort_raw_500k.dbo.JP_PROCEDURE", rendered)

        self.assertIn("UX_jmdc_person_source_value", person_sql)
        self.assertIn("UX_jmdc_visit_person_source", visit_sql)
        self.assertIn("sm.master_seq AS visit_occurrence_id", visit_sql)
        self.assertIn("INNER HASH JOIN", visit_sql)
        self.assertIn("OPTION (RECOMPILE, MAXDOP 4)", visit_sql)

    def test_japan_condition_retains_deterministic_source_id(self):
        config = japan.default_config()
        rendered = japan.render_domain_sql(
            config,
            "080.Condition_occurrence_japan.sql",
        )
        self.assertIn("sm.master_seq", rendered)
        self.assertIn(
            "d.master_seq AS condition_occurrence_id",
            rendered,
        )
        self.assertIn("INNER HASH JOIN", rendered)
        self.assertNotIn(
            "ROW_NUMBER() OVER",
            rendered,
        )

    def test_japan_drug_retains_deterministic_source_id(self):
        config = japan.default_config()
        rendered = japan.render_domain_sql(
            config,
            "100.Drug_exposure_japan.sql",
        )
        self.assertIn("sm.master_seq", rendered)
        self.assertIn("r.master_seq AS drug_exposure_id", rendered)
        self.assertIn("AS total_cost", rendered)
        self.assertIn("INNER HASH JOIN", rendered)
        self.assertNotIn(
            "+ ROW_NUMBER() OVER (ORDER BY r.master_seq)",
            rendered,
        )

    def test_japan_procedure_resolves_mapping_before_event_load(self):
        config = japan.default_config()
        rendered = japan.render_domain_sql(
            config,
            "110.Procedure_occurrence_japan.sql",
        )
        self.assertIn("sm.master_seq", rendered)
        self.assertIn(
            "r.master_seq AS procedure_occurrence_id",
            rendered,
        )
        self.assertIn("jmdc_proc_code_map", rendered)
        self.assertIn("AS total_cost", rendered)
        self.assertIn("INNER HASH JOIN", rendered)
        self.assertNotIn("IX_po_etl_dedup_japan", rendered)
        self.assertNotIn(
            "+ ROW_NUMBER() OVER (ORDER BY sm.master_seq)",
            rendered,
        )

    def test_japan_payer_reuses_observation_span(self):
        config = japan.default_config()
        rendered = japan.render_domain_sql(
            config,
            "170.Payer_plan_period_japan.sql",
        )
        self.assertIn("observation_period", rendered)
        self.assertNotIn("JP_CLAIMS", rendered)
        self.assertIn(
            "op.person_id AS payer_plan_period_id",
            rendered,
        )

    def test_japan_observation_prefers_patient_enrollment_span(self):
        config = japan.default_config()
        rendered = japan.render_domain_sql(
            config,
            "060.Observation_period_japan.sql",
        )
        self.assertIn("pt.observation_start", rendered)
        self.assertIn("pt.observation_end", rendered)
        self.assertIn("JP_CLAIMS", rendered)
        self.assertIn("Fallback for a claim-backed person", rendered)
        self.assertIn(
            "op.observation_period_start_date = s.start_date",
            rendered,
        )

    def test_japan_death_rejects_invalid_dates(self):
        config = japan.default_config()
        rendered = japan.render_domain_sql(
            config,
            "050.Death_japan.sql",
        )
        self.assertIn("d.death_flag = '1'", rendered)
        self.assertIn("WHERE death_date IS NOT NULL", rendered)
        self.assertIn("GROUP BY person_id", rendered)

    def test_japan_cost_reuses_deterministic_event_staging(self):
        config = japan.default_config()
        rendered = japan.render_domain_sql(
            config,
            "180.Cost_japan.sql",
        )
        self.assertIn("jmdc_drug_norm", rendered)
        self.assertIn("jmdc_proc_norm", rendered)
        self.assertIn("c.master_seq AS cost_id", rendered)
        self.assertIn("c.master_seq AS cost_event_id", rendered)
        self.assertNotIn("ROW_NUMBER() OVER", rendered)
        self.assertNotIn("IX_drug_master_seq_500k", rendered)
        self.assertNotIn("IX_proc_master_seq_500k", rendered)

    def test_japan_stage_resolution(self):
        self.assertEqual(
            japan._resolve_stage(None, False, True, False),
            "all",
        )
        self.assertEqual(
            japan._resolve_stage(None, True, True, False),
            "domains",
        )
        self.assertEqual(
            japan._resolve_stage("master", False, True, False),
            "master",
        )
        with self.assertRaises(ValueError):
            japan._resolve_stage("master", True, True, False)

    def test_sql_assets_are_inside_package(self):
        package_dir = Path(korea.__file__).resolve().parent
        self.assertEqual(
            len(list((package_dir / "sql" / "korea").glob("*.sql"))),
            21,
        )
        self.assertEqual(
            len(list((package_dir / "sql" / "japan").glob("*.sql"))),
            17,
        )

    def test_default_database_storage_is_f_drive(self):
        for module in (korea, japan):
            with self.subTest(module=module.__name__):
                config = module.default_config()
                self.assertEqual(config.data_dir.drive.upper(), "F:")
                self.assertEqual(config.log_dir.drive.upper(), "F:")
                self.assertEqual(config.initial_data_mb, 153_600)
                self.assertEqual(config.initial_log_mb, 51_200)
                self.assertEqual(config.filegrowth_mb, 4_096)
                module._validate_config(config)

    def test_runners_guard_long_sql_against_idle_sleep(self):
        korea_source = Path(korea.__file__).read_text(encoding="utf-8")
        japan_source = Path(japan.__file__).read_text(encoding="utf-8")
        qa_source = Path(qa.__file__).read_text(encoding="utf-8")
        self.assertIn("with prevent_idle_sleep(label):", korea_source)
        self.assertIn("with prevent_idle_sleep(label):", japan_source)
        self.assertIn('with prevent_idle_sleep("full CDM QA"):', qa_source)

    def test_non_f_database_storage_is_rejected(self):
        for module in (korea, japan):
            with self.subTest(module=module.__name__):
                config = module.default_config()
                config.data_dir = Path(r"C:\database\data")
                with self.assertRaisesRegex(
                    RuntimeError, "Refusing non-F SQL Server storage"
                ):
                    module._validate_config(config)

                config.allow_non_f_storage = True
                module._validate_config(config)

    def test_package_check_manages_every_sql_asset(self):
        assets = package_check.collect_assets()
        self.assertEqual(
            len([asset for asset in assets if asset.country == "korea"]),
            21,
        )
        self.assertEqual(
            len([asset for asset in assets if asset.country == "japan"]),
            17,
        )

    def test_full_qa_checks_temporal_domains(self):
        expected = {
            "observation_period",
            "visit_occurrence",
            "condition_occurrence",
            "drug_exposure",
            "device_exposure",
            "payer_plan_period",
            "drug_era",
            "dose_era",
            "condition_era",
        }
        actual = {spec.table for spec in qa.DOMAIN_SPECS if spec.end_date}
        self.assertEqual(actual, expected)

    def test_qa_covers_supporting_and_cost_links(self):
        specs = {spec.table: spec for spec in qa.DOMAIN_SPECS}
        self.assertTrue(
            {"location", "care_site", "provider", "cdm_source"}.issubset(specs)
        )
        self.assertTrue(specs["person"].has_location)
        self.assertTrue(specs["visit_occurrence"].has_care_site)
        self.assertTrue(specs["cost"].has_payer_plan)
        self.assertIn("SEQ_MASTER", qa.STAGING_TABLES)
        qa_source = Path(qa.__file__).read_text(encoding="utf-8")
        self.assertIn("invalid_year_of_birth_rows", qa_source)
        self.assertIn("null_person_source_value_rows", qa_source)
        self.assertIn("future_required_date_rows", qa_source)
        self.assertIn("death_before_birth_year_rows", qa_source)
        self.assertIn("period_after_death_rows", qa_source)
        self.assertIn("overlapping_period_rows", qa_source)
        self.assertIn("outside_observation_period_rows", qa_source)
        self.assertIn("payer_outside_observation_period_rows", qa_source)
        self.assertIn("condition_outside_visit_rows", qa_source)
        self.assertIn("mapping_expansion_rows", qa_source)
        self.assertIn("mapping_expansion_cost_rows", qa_source)
        self.assertIn("empty_cost_amount_rows", qa_source)
        self.assertIn("null_payer_plan_rows", qa_source)


if __name__ == "__main__":
    unittest.main()
