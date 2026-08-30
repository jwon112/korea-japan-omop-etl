"""
Read-only OMOP CDM QA for the Korea and Japan pipelines.

Quick mode reads catalog row counts and vocabulary status:
  python validate_cdm.py --country korea
  python validate_cdm.py --country japan

Full mode scans populated clinical tables and can be I/O intensive:
  python validate_cdm.py --country japan --full --confirm-full-scan
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime
import json
import os
from pathlib import Path
import re
import sys
from typing import Any

import pyodbc

from .power import prevent_idle_sleep


@dataclass(frozen=True)
class AuxConceptSpec:
    column: str
    expected_domain: str | None
    require_standard: bool = True


@dataclass(frozen=True)
class DomainSpec:
    table: str
    primary_key: str
    concept_column: str | None = None
    expected_domain: str | None = None
    required_date: str | None = None
    has_person: bool = False
    has_visit: bool = False
    auxiliary_concepts: tuple[AuxConceptSpec, ...] = ()
    end_date: str | None = None
    has_location: bool = False
    has_care_site: bool = False
    has_payer_plan: bool = False


DOMAIN_SPECS = (
    DomainSpec("location", "location_id"),
    DomainSpec(
        "care_site",
        "care_site_id",
        has_location=True,
    ),
    DomainSpec(
        "provider",
        "provider_id",
        has_care_site=True,
    ),
    DomainSpec(
        "person",
        "person_id",
        auxiliary_concepts=(
            AuxConceptSpec("gender_concept_id", "Gender"),
            AuxConceptSpec("race_concept_id", "Race"),
            AuxConceptSpec("ethnicity_concept_id", "Ethnicity"),
        ),
        has_location=True,
        has_care_site=True,
    ),
    DomainSpec(
        "observation_period",
        "observation_period_id",
        required_date="observation_period_start_date",
        has_person=True,
        auxiliary_concepts=(
            AuxConceptSpec("period_type_concept_id", "Type Concept", False),
        ),
        end_date="observation_period_end_date",
    ),
    DomainSpec(
        "death",
        "person_id",
        required_date="death_date",
        has_person=True,
        auxiliary_concepts=(
            AuxConceptSpec("death_type_concept_id", "Type Concept", False),
            AuxConceptSpec("cause_concept_id", "Condition"),
        ),
    ),
    DomainSpec(
        "visit_occurrence",
        "visit_occurrence_id",
        "visit_concept_id",
        "Visit",
        "visit_start_date",
        True,
        auxiliary_concepts=(
            AuxConceptSpec("visit_type_concept_id", "Type Concept", False),
        ),
        end_date="visit_end_date",
        has_care_site=True,
    ),
    DomainSpec(
        "condition_occurrence",
        "condition_occurrence_id",
        "condition_concept_id",
        "Condition",
        "condition_start_date",
        True,
        True,
        (
            AuxConceptSpec("condition_type_concept_id", "Type Concept", False),
        ),
        end_date="condition_end_date",
    ),
    DomainSpec(
        "drug_exposure",
        "drug_exposure_id",
        "drug_concept_id",
        "Drug",
        "drug_exposure_start_date",
        True,
        True,
        (
            AuxConceptSpec("drug_type_concept_id", "Type Concept", False),
            AuxConceptSpec("route_concept_id", "Route"),
        ),
        end_date="drug_exposure_end_date",
    ),
    DomainSpec(
        "procedure_occurrence",
        "procedure_occurrence_id",
        "procedure_concept_id",
        "Procedure",
        "procedure_date",
        True,
        True,
        (
            AuxConceptSpec("procedure_type_concept_id", "Type Concept", False),
        ),
    ),
    DomainSpec(
        "device_exposure",
        "device_exposure_id",
        "device_concept_id",
        "Device",
        "device_exposure_start_date",
        True,
        True,
        (
            AuxConceptSpec("device_type_concept_id", "Type Concept", False),
        ),
        end_date="device_exposure_end_date",
    ),
    DomainSpec(
        "measurement",
        "measurement_id",
        "measurement_concept_id",
        "Measurement",
        "measurement_date",
        True,
        True,
        (
            AuxConceptSpec("measurement_type_concept_id", "Type Concept", False),
            AuxConceptSpec("unit_concept_id", "Unit"),
        ),
    ),
    DomainSpec(
        "observation",
        "observation_id",
        "observation_concept_id",
        "Observation",
        "observation_date",
        True,
        True,
        (
            AuxConceptSpec("observation_type_concept_id", "Type Concept", False),
            AuxConceptSpec("unit_concept_id", "Unit"),
            AuxConceptSpec("value_as_concept_id", None),
        ),
    ),
    DomainSpec(
        "payer_plan_period",
        "payer_plan_period_id",
        required_date="payer_plan_period_start_date",
        has_person=True,
        end_date="payer_plan_period_end_date",
    ),
    DomainSpec(
        "cost",
        "cost_id",
        auxiliary_concepts=(
            AuxConceptSpec("cost_type_concept_id", "Type Concept", False),
            AuxConceptSpec("currency_concept_id", "Currency"),
        ),
        has_payer_plan=True,
    ),
    DomainSpec(
        "drug_era",
        "drug_era_id",
        "drug_concept_id",
        "Drug",
        "drug_era_start_date",
        True,
        end_date="drug_era_end_date",
    ),
    DomainSpec(
        "dose_era",
        "dose_era_id",
        "drug_concept_id",
        "Drug",
        "dose_era_start_date",
        True,
        end_date="dose_era_end_date",
    ),
    DomainSpec(
        "condition_era",
        "condition_era_id",
        "condition_concept_id",
        "Condition",
        "condition_era_start_date",
        True,
        end_date="condition_era_end_date",
    ),
    DomainSpec("cdm_source", "cdm_source_name"),
)

VOCAB_TABLES = (
    "concept",
    "concept_relationship",
    "concept_ancestor",
    "vocabulary",
    "domain",
    "concept_class",
    "relationship",
    "source_to_concept_map",
)

STAGING_TABLES = (
    "SEQ_MASTER",
    "NHIS_CLAIM_PERSON",
    "GJ_VERTICAL",
    "JK_VERTICAL",
    "jmdc_claim_norm",
    "jmdc_condition_norm",
    "jmdc_drug_norm",
    "jmdc_proc_norm",
    "jmdc_proc_code_map",
)

COUNTRY_DEFAULTS = {
    "korea": ("nhisnsc2013original", "korea_cohort_cdm_final"),
    "japan": ("japan_cohort_raw_500k", "japan_cohort_cdm_500k_final"),
}


def validate_identifier(value: str, label: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9_]+", value or ""):
        raise ValueError(f"Unsafe {label}: {value!r}")


def connection_string(server: str, database: str) -> str:
    base = (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={server};DATABASE={database};Encrypt=no;Connection Timeout=30;"
    )
    if os.environ.get("SQLSERVER_WINDOWS_AUTH", "1") != "0":
        return base + "Trusted_Connection=Yes;"
    username = os.environ.get("SQLSERVER_USERNAME")
    password = os.environ.get("SQLSERVER_PASSWORD")
    if not username or not password:
        raise RuntimeError(
            "SQL authentication requires SQLSERVER_USERNAME and SQLSERVER_PASSWORD."
        )
    return base + f"UID={username};PWD={password};"


def connect(server: str, database: str):
    conn = pyodbc.connect(connection_string(server, database), autocommit=True)
    conn.timeout = 0
    return conn


def catalog_counts(cursor) -> dict[str, int]:
    rows = cursor.execute(
        """
        SELECT LOWER(t.name), SUM(p.rows)
        FROM sys.tables t
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        JOIN sys.partitions p
          ON p.object_id = t.object_id
         AND p.index_id IN (0, 1)
        WHERE s.name = N'dbo'
        GROUP BY t.name
        """
    ).fetchall()
    return {str(name).lower(): int(count or 0) for name, count in rows}


def database_files(server: str, database: str) -> list[dict[str, Any]]:
    with connect(server, "master") as conn:
        rows = conn.cursor().execute(
            """
            SELECT mf.type_desc, mf.physical_name,
                   CAST(mf.size * 8.0 / 1024 AS DECIMAL(18, 1))
            FROM sys.master_files mf
            WHERE mf.database_id = DB_ID(?)
            ORDER BY mf.file_id
            """,
            database,
        ).fetchall()
    return [
        {"type": str(row[0]), "path": str(row[1]), "size_mb": float(row[2])}
        for row in rows
    ]


def quick_report(
    server: str,
    country: str,
    raw_database: str,
    cdm_database: str,
) -> dict[str, Any]:
    with connect(server, "master") as conn:
        exists = conn.cursor().execute(
            "SELECT CASE WHEN DB_ID(?) IS NULL THEN 0 ELSE 1 END",
            cdm_database,
        ).fetchone()
    if not exists or not exists[0]:
        raise RuntimeError(f"CDM database not found: {cdm_database}")

    with connect(server, cdm_database) as conn:
        counts = catalog_counts(conn.cursor())

    report = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "mode": "quick",
        "country": country,
        "server": server,
        "raw_database": raw_database,
        "cdm_database": cdm_database,
        "files": database_files(server, cdm_database),
        "vocabulary": {name: counts.get(name, 0) for name in VOCAB_TABLES},
        "domains": {spec.table: counts.get(spec.table, 0) for spec in DOMAIN_SPECS},
        "staging": {
            name: counts.get(name.lower(), 0)
            for name in STAGING_TABLES
            if name.lower() in counts
        },
    }
    return report


def full_table_report(
    cursor,
    spec: DomainSpec,
    country: str,
) -> dict[str, Any]:
    joins: list[str] = []
    selects = ["COUNT_BIG(*) AS total_rows"]

    if spec.concept_column:
        joins.append(
            f"LEFT JOIN dbo.concept c ON c.concept_id = t.{spec.concept_column}"
        )
        selects.extend(
            [
                (
                    f"SUM(CASE WHEN t.{spec.concept_column} > 0 "
                    "THEN 1 ELSE 0 END) AS mapped_rows"
                ),
                (
                    f"SUM(CASE WHEN t.{spec.concept_column} > 0 AND ("
                    "c.concept_id IS NULL OR ISNULL(c.standard_concept, '') <> 'S' "
                    "OR c.invalid_reason IS NOT NULL "
                    f"OR LOWER(c.domain_id) <> LOWER('{spec.expected_domain}')"
                    ") THEN 1 ELSE 0 END) AS invalid_standard_or_domain_rows"
                ),
            ]
        )

    for index, auxiliary in enumerate(spec.auxiliary_concepts):
        alias = f"ac{index}"
        joins.append(
            f"LEFT JOIN dbo.concept {alias} "
            f"ON {alias}.concept_id = t.{auxiliary.column}"
        )
        standard_check = (
            f"OR ISNULL({alias}.standard_concept, '') <> 'S' "
            if auxiliary.require_standard
            else ""
        )
        domain_check = (
            f"OR LOWER({alias}.domain_id) <> LOWER('{auxiliary.expected_domain}') "
            if auxiliary.expected_domain
            else ""
        )
        selects.append(
            f"SUM(CASE WHEN ISNULL(t.{auxiliary.column}, 0) > 0 AND ("
            f"{alias}.concept_id IS NULL "
            f"OR {alias}.invalid_reason IS NOT NULL "
            f"{domain_check}"
            f"{standard_check}"
            f") THEN 1 ELSE 0 END) AS invalid_{auxiliary.column}_rows"
        )

    if spec.required_date:
        selects.append(
            f"SUM(CASE WHEN t.{spec.required_date} IS NULL THEN 1 ELSE 0 END) "
            "AS null_required_date_rows"
        )
        selects.append(
            f"SUM(CASE WHEN t.{spec.required_date} > CONVERT(DATE, GETDATE()) "
            "THEN 1 ELSE 0 END) AS future_required_date_rows"
        )
        if spec.end_date:
            selects.append(
                f"SUM(CASE WHEN t.{spec.end_date} IS NOT NULL "
                f"AND t.{spec.end_date} < t.{spec.required_date} "
                "THEN 1 ELSE 0 END) AS reversed_date_rows"
            )

    if spec.has_person:
        joins.append("LEFT JOIN dbo.person p ON p.person_id = t.person_id")
        selects.append(
            "SUM(CASE WHEN p.person_id IS NULL THEN 1 ELSE 0 END) "
            "AS missing_person_rows"
        )

    if spec.has_visit and spec.table != "visit_occurrence":
        joins.append(
            "LEFT JOIN dbo.visit_occurrence v "
            "ON v.visit_occurrence_id = t.visit_occurrence_id"
        )
        selects.append(
            "SUM(CASE WHEN t.visit_occurrence_id IS NOT NULL "
            "AND v.visit_occurrence_id IS NULL THEN 1 ELSE 0 END) "
            "AS missing_visit_rows"
        )

    if spec.table == "condition_occurrence":
        selects.append(
            "SUM(CASE WHEN t.condition_start_date < v.visit_start_date "
            "OR t.condition_start_date > v.visit_end_date "
            "OR (t.condition_end_date IS NOT NULL "
            "AND t.condition_end_date > v.visit_end_date) "
            "THEN 1 ELSE 0 END) AS condition_outside_visit_rows"
        )

    if spec.table == "drug_exposure":
        joins.append("LEFT JOIN dbo.death d ON d.person_id = t.person_id")
        selects.append(
            "SUM(CASE WHEN t.drug_exposure_start_date < v.visit_start_date "
            "OR t.drug_exposure_start_date > v.visit_end_date "
            "THEN 1 ELSE 0 END) AS drug_start_outside_visit_rows"
        )
        selects.append(
            "SUM(CASE WHEN d.death_date IS NOT NULL AND ("
            "t.drug_exposure_start_date > d.death_date "
            "OR t.drug_exposure_end_date > d.death_date) "
            "THEN 1 ELSE 0 END) AS drug_after_death_rows"
        )

    if spec.table == "procedure_occurrence":
        selects.append(
            "SUM(CASE WHEN t.procedure_date < v.visit_start_date "
            "OR t.procedure_date > v.visit_end_date "
            "THEN 1 ELSE 0 END) AS procedure_outside_visit_rows"
        )

    if spec.table == "device_exposure":
        joins.append("LEFT JOIN dbo.death dd ON dd.person_id = t.person_id")
        selects.append(
            "SUM(CASE WHEN t.device_exposure_start_date < v.visit_start_date "
            "OR t.device_exposure_start_date > v.visit_end_date "
            "THEN 1 ELSE 0 END) AS device_start_outside_visit_rows"
        )
        selects.append(
            "SUM(CASE WHEN dd.death_date IS NOT NULL AND ("
            "t.device_exposure_start_date > dd.death_date "
            "OR t.device_exposure_end_date > dd.death_date) "
            "THEN 1 ELSE 0 END) AS device_after_death_rows"
        )

    if spec.table == "measurement":
        selects.append(
            "SUM(CASE WHEN t.measurement_date < v.visit_start_date "
            "OR t.measurement_date > v.visit_end_date "
            "THEN 1 ELSE 0 END) AS measurement_outside_visit_rows"
        )

    if spec.table == "payer_plan_period":
        joins.append(
            "LEFT JOIN dbo.observation_period pop "
            "ON pop.person_id = t.person_id "
            "AND t.payer_plan_period_start_date "
            ">= pop.observation_period_start_date "
            "AND t.payer_plan_period_end_date "
            "<= pop.observation_period_end_date"
        )
        selects.append(
            "SUM(CASE WHEN pop.observation_period_id IS NULL "
            "THEN 1 ELSE 0 END) AS payer_outside_observation_period_rows"
        )

    if country == "korea" and spec.table in {
        "condition_occurrence",
        "drug_exposure",
        "procedure_occurrence",
        "device_exposure",
    }:
        selects.append(
            f"SUM(CASE WHEN t.{spec.primary_key} % 100 = 1 "
            "THEN 1 ELSE 0 END) AS source_event_rows"
        )

    if spec.has_location:
        joins.append("LEFT JOIN dbo.location l ON l.location_id = t.location_id")
        selects.append(
            "SUM(CASE WHEN t.location_id IS NOT NULL "
            "AND l.location_id IS NULL THEN 1 ELSE 0 END) "
            "AS missing_location_rows"
        )

    if spec.has_care_site:
        joins.append(
            "LEFT JOIN dbo.care_site cs ON cs.care_site_id = t.care_site_id"
        )
        selects.append(
            "SUM(CASE WHEN t.care_site_id IS NOT NULL "
            "AND cs.care_site_id IS NULL THEN 1 ELSE 0 END) "
            "AS missing_care_site_rows"
        )

    if spec.has_payer_plan:
        joins.append(
            "LEFT JOIN dbo.payer_plan_period pp "
            "ON pp.payer_plan_period_id = t.payer_plan_period_id"
        )
        selects.append(
            "SUM(CASE WHEN t.payer_plan_period_id IS NOT NULL "
            "AND pp.payer_plan_period_id IS NULL THEN 1 ELSE 0 END) "
            "AS missing_payer_plan_rows"
        )
        selects.append(
            "SUM(CASE WHEN t.payer_plan_period_id IS NULL "
            "THEN 1 ELSE 0 END) AS null_payer_plan_rows"
        )

    if spec.table == "person":
        selects.extend(
            [
                "MIN(t.year_of_birth) AS min_year_of_birth",
                "MAX(t.year_of_birth) AS max_year_of_birth",
                (
                    "SUM(CASE WHEN t.year_of_birth IS NULL "
                    "THEN 1 ELSE 0 END) AS null_year_of_birth_rows"
                ),
                (
                    "SUM(CASE WHEN t.year_of_birth < 1800 "
                    "OR t.year_of_birth > YEAR(GETDATE()) "
                    "THEN 1 ELSE 0 END) AS invalid_year_of_birth_rows"
                ),
                (
                    "SUM(CASE WHEN t.person_source_value IS NULL "
                    "THEN 1 ELSE 0 END) AS null_person_source_value_rows"
                ),
            ]
        )

    if spec.table == "death":
        selects.append(
            "SUM(CASE WHEN t.death_date < "
            "DATEFROMPARTS(p.year_of_birth, 1, 1) "
            "THEN 1 ELSE 0 END) AS death_before_birth_year_rows"
        )

    if spec.table == "observation_period":
        joins.append("LEFT JOIN dbo.death d ON d.person_id = t.person_id")
        selects.extend(
            [
                (
                    "SUM(CASE WHEN t.observation_period_start_date < "
                    "DATEFROMPARTS(p.year_of_birth, 1, 1) "
                    "THEN 1 ELSE 0 END) AS period_before_birth_year_rows"
                ),
                (
                    "SUM(CASE WHEN d.death_date IS NOT NULL "
                    "AND t.observation_period_end_date > d.death_date "
                    "THEN 1 ELSE 0 END) AS period_after_death_rows"
                ),
            ]
        )

    if spec.table == "cost":
        joins.extend(
            [
                "LEFT JOIN dbo.visit_occurrence cv "
                "ON t.cost_domain_id = 'Visit' "
                "AND cv.visit_occurrence_id = t.cost_event_id",
                "LEFT JOIN dbo.drug_exposure cd "
                "ON t.cost_domain_id = 'Drug' "
                "AND cd.drug_exposure_id = t.cost_event_id",
                "LEFT JOIN dbo.procedure_occurrence cp "
                "ON t.cost_domain_id = 'Procedure' "
                "AND cp.procedure_occurrence_id = t.cost_event_id",
                "LEFT JOIN dbo.device_exposure cde "
                "ON t.cost_domain_id = 'Device' "
                "AND cde.device_exposure_id = t.cost_event_id",
            ]
        )
        selects.extend(
            [
                (
                    "SUM(CASE WHEN t.cost_domain_id NOT IN "
                    "('Visit', 'Drug', 'Procedure', 'Device') "
                    "THEN 1 ELSE 0 END) AS invalid_cost_domain_rows"
                ),
                (
                    "SUM(CASE "
                    "WHEN t.cost_domain_id = 'Visit' "
                    "AND cv.visit_occurrence_id IS NULL THEN 1 "
                    "WHEN t.cost_domain_id = 'Drug' "
                    "AND cd.drug_exposure_id IS NULL THEN 1 "
                    "WHEN t.cost_domain_id = 'Procedure' "
                    "AND cp.procedure_occurrence_id IS NULL THEN 1 "
                    "WHEN t.cost_domain_id = 'Device' "
                    "AND cde.device_exposure_id IS NULL THEN 1 "
                    "ELSE 0 END) AS missing_cost_event_rows"
                ),
                (
                    "SUM(CASE WHEN t.cost_domain_id <> 'Visit' "
                    "AND t.cost_event_id % 100 <> 1 "
                    "THEN 1 ELSE 0 END) AS mapping_expansion_cost_rows"
                ),
                (
                    "SUM(CASE WHEN t.total_charge IS NULL "
                    "AND t.total_cost IS NULL "
                    "AND t.total_paid IS NULL "
                    "AND t.paid_by_payer IS NULL "
                    "AND t.paid_by_patient IS NULL "
                    "AND t.paid_patient_copay IS NULL "
                    "AND t.paid_patient_coinsurance IS NULL "
                    "AND t.paid_patient_deductible IS NULL "
                    "AND t.paid_by_primary IS NULL "
                    "AND t.paid_ingredient_cost IS NULL "
                    "AND t.paid_dispensing_fee IS NULL "
                    "AND t.amount_allowed IS NULL "
                    "THEN 1 ELSE 0 END) AS empty_cost_amount_rows"
                ),
            ]
        )

    sql = (
        "SELECT "
        + ", ".join(selects)
        + f" FROM dbo.{spec.table} t "
        + " ".join(joins)
        + " OPTION (HASH JOIN, RECOMPILE, MAXDOP 4)"
    )
    print(f"[full]   integrity metrics: dbo.{spec.table}", flush=True)
    row = cursor.execute(sql).fetchone()
    columns = [str(item[0]) for item in cursor.description]
    metrics = {
        name: int(value or 0)
        for name, value in zip(columns, row, strict=True)
    }
    if "source_event_rows" in metrics:
        metrics["mapping_expansion_rows"] = (
            metrics["total_rows"] - metrics["source_event_rows"]
        )

    print(f"[full]   duplicate keys: dbo.{spec.table}", flush=True)
    duplicate_row = cursor.execute(
        f"""
        SELECT COUNT_BIG(*)
        FROM (
            SELECT t.{spec.primary_key}
            FROM dbo.{spec.table} t
            GROUP BY t.{spec.primary_key}
            HAVING COUNT_BIG(*) > 1
        ) duplicated_keys
        OPTION (HASH GROUP, RECOMPILE, MAXDOP 4)
        """
    ).fetchone()
    metrics["duplicate_primary_keys"] = int(
        (duplicate_row[0] if duplicate_row else 0) or 0
    )
    if spec.table == "observation_period":
        print("[full]   overlapping periods: dbo.observation_period", flush=True)
        overlap_row = cursor.execute(
            """
            SELECT COUNT_BIG(*)
            FROM (
                SELECT
                    person_id,
                    observation_period_start_date,
                    LAG(observation_period_end_date) OVER (
                        PARTITION BY person_id
                        ORDER BY observation_period_start_date,
                                 observation_period_end_date,
                                 observation_period_id
                    ) AS previous_end_date
                FROM dbo.observation_period
            ) ordered_periods
            WHERE observation_period_start_date <= previous_end_date
            OPTION (RECOMPILE, MAXDOP 4)
            """
        ).fetchone()
        metrics["overlapping_period_rows"] = int(
            (overlap_row[0] if overlap_row else 0) or 0
        )
    if spec.table == "visit_occurrence":
        print("[full]   observation coverage: dbo.visit_occurrence", flush=True)
        coverage_row = cursor.execute(
            """
            SELECT COUNT_BIG(*)
            FROM dbo.visit_occurrence v
            WHERE NOT EXISTS (
                SELECT 1
                FROM dbo.observation_period op
                WHERE op.person_id = v.person_id
                  AND v.visit_start_date >= op.observation_period_start_date
                  AND v.visit_end_date <= op.observation_period_end_date
            )
            OPTION (HASH JOIN, RECOMPILE, MAXDOP 4)
            """
        ).fetchone()
        metrics["outside_observation_period_rows"] = int(
            (coverage_row[0] if coverage_row else 0) or 0
        )
    return metrics


def add_full_report(
    report: dict[str, Any],
    server: str,
    cdm_database: str,
    selected: set[str] | None,
) -> None:
    report["mode"] = "full"
    report["full_scan"] = {}
    with connect(server, cdm_database) as conn:
        cursor = conn.cursor()
        for spec in DOMAIN_SPECS:
            if selected and spec.table not in selected:
                continue
            if report["domains"].get(spec.table, 0) == 0:
                continue
            print(f"[full] scanning dbo.{spec.table}", flush=True)
            report["full_scan"][spec.table] = full_table_report(
                cursor,
                spec,
                report["country"],
            )


def print_report(report: dict[str, Any]) -> None:
    print(
        f"[qa] country={report['country']} db={report['cdm_database']} "
        f"mode={report['mode']}"
    )
    for item in report["files"]:
        print(
            f"  file {item['type']}: {item['path']} ({item['size_mb']:,.1f} MB)"
        )
    print("  vocabulary:")
    for name, count in report["vocabulary"].items():
        print(f"    {name}={count:,}")
    print("  domains:")
    for name, count in report["domains"].items():
        print(f"    {name}={count:,}")
    if report.get("staging"):
        print("  staging:")
        for name, count in report["staging"].items():
            print(f"    {name}={count:,}")
    for name, metrics in report.get("full_scan", {}).items():
        details = ", ".join(f"{key}={value:,}" for key, value in metrics.items())
        print(f"  full {name}: {details}")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--country", choices=tuple(COUNTRY_DEFAULTS), required=True)
    result.add_argument("--raw-db")
    result.add_argument("--cdm-db")
    result.add_argument("--server")
    result.add_argument(
        "--full",
        action="store_true",
        help="Run exact mapping, linkage, required-date, and duplicate scans.",
    )
    result.add_argument(
        "--confirm-full-scan",
        action="store_true",
        help="Required with --full because large tables can create heavy I/O.",
    )
    result.add_argument("--only", help="Comma-separated CDM tables for --full.")
    result.add_argument("--json", type=Path, help="Optional JSON report path.")
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    default_raw, default_cdm = COUNTRY_DEFAULTS[args.country]
    server = args.server or os.environ.get(
        "SQLSERVER_SERVER", r"localhost\SQLEXPRESS"
    )
    raw_database = args.raw_db or default_raw
    cdm_database = args.cdm_db or default_cdm
    validate_identifier(raw_database, "raw database")
    validate_identifier(cdm_database, "CDM database")

    if args.full and not args.confirm_full_scan:
        raise RuntimeError(
            "--full scans large tables. Add --confirm-full-scan after scheduling "
            "the workload."
        )
    selected = (
        {item.strip().lower() for item in args.only.split(",") if item.strip()}
        if args.only
        else None
    )
    known = {spec.table for spec in DOMAIN_SPECS}
    if selected and selected - known:
        raise ValueError(
            "Unknown --only table(s): " + ", ".join(sorted(selected - known))
        )

    report = quick_report(
        server, args.country, raw_database, cdm_database
    )
    if args.full:
        with prevent_idle_sleep("full CDM QA"):
            add_full_report(report, server, cdm_database, selected)
    print_report(report)

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(
            json.dumps(report, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        print(f"[qa] wrote {args.json.resolve()}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        raise
