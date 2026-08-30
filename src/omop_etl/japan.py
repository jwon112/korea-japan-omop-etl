"""
Safe Python runner for the relational JMDC-to-OMOP SQL Server ETL.

Examples:
  python run_japan.py
  python run_japan.py --preflight
  python run_japan.py --target-db japan_cohort_cdm_500k_final --execute
  python run_japan.py --target-db japan_cohort_cdm_500k_final
      --resume --only procedure_occurrence --reset --execute

Without --execute, the runner performs only static or read-only checks.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Iterable

import pyodbc

from .power import prevent_idle_sleep


@dataclass(frozen=True)
class Step:
    key: str
    sql_file: str
    target_table: str
    required_raw: tuple[str, ...] = ()
    requires_nonempty: tuple[str, ...] = ()
    enabled_by_default: bool = True


@dataclass
class Config:
    server: str
    raw_database: str
    target_database: str
    sql_dir: Path
    vocabulary_folder: Path
    data_dir: Path
    log_dir: Path
    initial_data_mb: int = 153_600
    initial_log_mb: int = 51_200
    filegrowth_mb: int = 4_096
    windows_auth: bool = True
    allow_non_f_storage: bool = False
    allow_tempdb_off_f: bool = False
    schema: str = "dbo"


MASTER_SQL = "010.Master_table_japan.sql"
STAGES = ("preflight", "ddl", "vocabulary", "master", "domains", "all")

CORE_RAW_TABLES = (
    "JP_PATIENT",
    "JP_CLAIMS",
    "JP_DIAGNOSIS",
    "JP_DRUG",
    "JP_PROCEDURE",
    "JP_DIAGNOSIS_MASTER",
    "JP_DRUG_MASTER",
    "JP_PROCEDURE_MASTER",
)

DOMAIN_STEPS = (
    Step("person", "040.Person_japan.sql", "person", CORE_RAW_TABLES),
    Step(
        "observation_period",
        "060.Observation_period_japan.sql",
        "observation_period",
        ("JP_CLAIMS",),
        ("person",),
    ),
    Step(
        "visit_occurrence",
        "070.Visit_occurrence_japan.sql",
        "visit_occurrence",
        ("JP_CLAIMS", "JP_DIAGNOSIS", "JP_DRUG", "JP_PROCEDURE"),
        ("person", "SEQ_MASTER"),
    ),
    Step(
        "care_site",
        "130.Care_site_japan.sql",
        "care_site",
        ("JP_MEDICAL_FACILITY", "JP_CLAIMS"),
        ("visit_occurrence",),
        False,
    ),
    Step(
        "condition_occurrence",
        "080.Condition_occurrence_japan.sql",
        "condition_occurrence",
        ("JP_DIAGNOSIS", "JP_DIAGNOSIS_MASTER"),
        ("person", "visit_occurrence", "SEQ_MASTER"),
    ),
    Step(
        "drug_exposure",
        "100.Drug_exposure_japan.sql",
        "drug_exposure",
        ("JP_DRUG", "JP_DRUG_MASTER"),
        ("person", "visit_occurrence", "SEQ_MASTER"),
    ),
    Step(
        "procedure_occurrence",
        "110.Procedure_occurrence_japan.sql",
        "procedure_occurrence",
        ("JP_PROCEDURE", "JP_PROCEDURE_MASTER"),
        ("person", "visit_occurrence", "SEQ_MASTER"),
    ),
    Step(
        "location",
        "120.Location_japan.sql",
        "location",
        enabled_by_default=False,
    ),
    Step(
        "observation",
        "140.Observation_japan.sql",
        "observation",
        enabled_by_default=False,
    ),
    Step(
        "device_exposure",
        "150.Device_exposure_japan.sql",
        "device_exposure",
        enabled_by_default=False,
    ),
    Step(
        "measurement",
        "160.Measurement_japan.sql",
        "measurement",
        ("JP_ANNUAL_HEALTH_CHECKUP",),
        ("person",),
        False,
    ),
    Step(
        "payer_plan_period",
        "170.Payer_plan_period_japan.sql",
        "payer_plan_period",
        ("JP_CLAIMS",),
        ("person",),
    ),
    Step(
        "death",
        "050.Death_japan.sql",
        "death",
        ("JP_PATIENT",),
        ("person",),
    ),
    Step(
        "cost",
        "180.Cost_japan.sql",
        "cost",
        ("JP_CLAIMS", "JP_DRUG", "JP_PROCEDURE"),
        (
            "visit_occurrence",
            "drug_exposure",
            "procedure_occurrence",
            "SEQ_MASTER",
            "jmdc_drug_norm",
            "jmdc_proc_norm",
        ),
    ),
)

REQUIRED_VOCAB_FILES = (
    "CONCEPT.csv",
    "CONCEPT_SYNONYM.csv",
    "CONCEPT_RELATIONSHIP.csv",
    "CONCEPT_ANCESTOR.csv",
    "DRUG_STRENGTH.csv",
    "VOCABULARY.csv",
    "DOMAIN.csv",
    "CONCEPT_CLASS.csv",
    "RELATIONSHIP.csv",
)

VOCAB_MINIMUM_ROWS = {
    "CONCEPT": 1_000_000,
    "CONCEPT_RELATIONSHIP": 1_000_000,
    "CONCEPT_ANCESTOR": 1_000_000,
    "VOCABULARY": 1,
    "DOMAIN": 1,
    "CONCEPT_CLASS": 1,
    "RELATIONSHIP": 1,
    "SOURCE_TO_CONCEPT_MAP": 1,
}

GO_PATTERN = re.compile(r"^\s*GO\s*(?:--.*)?$", re.IGNORECASE | re.MULTILINE)
BLOCK_COMMENT_PATTERN = re.compile(r"/\*.*?\*/", re.DOTALL)
LINE_COMMENT_PATTERN = re.compile(r"--[^\r\n]*")
REQUIRED_STORAGE_DRIVE = "F:"


def default_config() -> Config:
    package_dir = Path(__file__).resolve().parent
    return Config(
        server=os.environ.get(
            "SQLSERVER_SERVER", r"localhost\SQLEXPRESS"
        ),
        raw_database=os.environ.get(
            "JAPAN_RAW_DB", "japan_cohort_raw_500k"
        ),
        target_database=os.environ.get(
            "JAPAN_CDM_DB", "japan_cohort_cdm_500k_final"
        ),
        sql_dir=package_dir / "sql" / "japan",
        vocabulary_folder=Path(
            os.environ.get("VOCAB_FOLDER", str(Path.cwd() / "vocabulary"))
        ),
        data_dir=Path(os.environ.get("SQLSERVER_DATA_DIR", r"F:\database\data")),
        log_dir=Path(os.environ.get("SQLSERVER_LOG_DIR", r"F:\database\log")),
        initial_data_mb=int(
            os.environ.get("JAPAN_INITIAL_DATA_MB", "153600")
        ),
        initial_log_mb=int(
            os.environ.get("JAPAN_INITIAL_LOG_MB", "51200")
        ),
        filegrowth_mb=int(
            os.environ.get("SQLSERVER_FILEGROWTH_MB", "4096")
        ),
        windows_auth=os.environ.get("SQLSERVER_WINDOWS_AUTH", "1") != "0",
    )


def _validate_identifier(value: str, label: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9_]+", value or ""):
        raise ValueError(f"Unsafe {label}: {value!r}")


def _validate_config(config: Config) -> None:
    _validate_identifier(config.raw_database, "raw database")
    _validate_identifier(config.target_database, "target database")
    _validate_identifier(config.schema, "schema")
    for label, value in (
        ("initial_data_mb", config.initial_data_mb),
        ("initial_log_mb", config.initial_log_mb),
        ("filegrowth_mb", config.filegrowth_mb),
    ):
        if value <= 0:
            raise ValueError(f"{label} must be positive, got {value}.")
    _validate_storage_paths(config)


def _validate_storage_paths(config: Config) -> None:
    if config.allow_non_f_storage:
        return
    invalid = [
        f"{label}={path}"
        for label, path in (
            ("data_dir", config.data_dir),
            ("log_dir", config.log_dir),
        )
        if path.drive.upper() != REQUIRED_STORAGE_DRIVE
    ]
    if invalid:
        raise RuntimeError(
            "Refusing non-F SQL Server storage: "
            + ", ".join(invalid)
            + ". This project requires F: for new MDF/LDF files. "
            "Use --allow-non-f-storage only after explicit storage review."
        )


def _connection_string(config: Config, database: str) -> str:
    base = (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={config.server};DATABASE={database};"
        "Encrypt=no;Connection Timeout=30;"
    )
    if config.windows_auth:
        return base + "Trusted_Connection=Yes;"

    username = os.environ.get("SQLSERVER_USERNAME")
    password = os.environ.get("SQLSERVER_PASSWORD")
    if not username or not password:
        raise RuntimeError(
            "SQL authentication requires SQLSERVER_USERNAME and "
            "SQLSERVER_PASSWORD."
        )
    return base + f"UID={username};PWD={password};"


def _connect(config: Config, database: str, autocommit: bool = True):
    connection = pyodbc.connect(
        _connection_string(config, database), autocommit=autocommit
    )
    connection.timeout = 0
    return connection


def _active_sql(sql: str) -> str:
    return LINE_COMMENT_PATTERN.sub("", BLOCK_COMMENT_PATTERN.sub("", sql))


def _read_sql(config: Config, sql_file: str) -> str:
    path = config.sql_dir / sql_file
    if not path.is_file():
        raise FileNotFoundError(f"SQL file not found: {path}")
    return path.read_text(encoding="utf-8", errors="replace")


def _assert_resolved(sql_file: str, rendered: str, tokens: Iterable[str]) -> None:
    active = _active_sql(rendered)
    unresolved = [token for token in tokens if token.lower() in active.lower()]
    if unresolved:
        raise RuntimeError(
            f"{sql_file} has unresolved placeholders: {', '.join(unresolved)}"
        )


def render_domain_sql(config: Config, sql_file: str) -> str:
    rendered = _read_sql(config, sql_file)
    rendered = rendered.replace(
        "@raw_database", f"{config.raw_database}.{config.schema}"
    )
    rendered = rendered.replace(
        "@cdm_database", f"{config.target_database}.{config.schema}"
    )
    _assert_resolved(
        sql_file, rendered, ("@raw_database", "@cdm_database")
    )
    return rendered


def render_ddl_sql(config: Config) -> str:
    sql_file = "000.OMOP CDM sql server ddl.sql"
    rendered = _read_sql(config, sql_file).replace(
        "@cdm_database", config.target_database
    )
    _assert_resolved(sql_file, rendered, ("@cdm_database",))
    return rendered


def render_vocabulary_sql(config: Config) -> str:
    sql_file = "001.Import_voca.sql"
    rendered = _read_sql(config, sql_file)
    rendered = rendered.replace("@Mapping_database", config.target_database)
    rendered = rendered.replace(
        "@vocaFolder", str(config.vocabulary_folder.resolve())
    )
    _assert_resolved(
        sql_file, rendered, ("@Mapping_database", "@vocaFolder")
    )
    return rendered


def split_batches(sql: str) -> list[str]:
    return [batch.strip() for batch in GO_PATTERN.split(sql) if batch.strip()]


def _consume_results(cursor) -> None:
    while True:
        if cursor.description:
            cursor.fetchall()
        if not cursor.nextset():
            return


def execute_sql(
    config: Config,
    sql: str,
    label: str,
    database: str | None = None,
) -> None:
    batches = split_batches(sql)
    started = time.perf_counter()
    print(f"[run] {label}: {len(batches)} batch(es)", flush=True)
    with prevent_idle_sleep(label):
        with _connect(config, database or config.target_database) as conn:
            cursor = conn.cursor()
            for index, batch in enumerate(batches, start=1):
                batch_started = time.perf_counter()
                cursor.execute(batch)
                _consume_results(cursor)
                print(
                    f"  [{index}/{len(batches)}] ok "
                    f"({time.perf_counter() - batch_started:.1f}s)",
                    flush=True,
                )
    print(
        f"[done] {label} ({time.perf_counter() - started:.1f}s)",
        flush=True,
    )


def _database_exists(config: Config, database: str) -> bool:
    with _connect(config, "master") as conn:
        row = conn.cursor().execute(
            "SELECT CASE WHEN DB_ID(?) IS NULL THEN 0 ELSE 1 END", database
        ).fetchone()
    return bool(row and row[0])


def _database_file_paths(config: Config, database: str) -> list[str]:
    with _connect(config, "master") as conn:
        rows = conn.cursor().execute(
            """
            SELECT mf.physical_name
            FROM sys.master_files mf
            JOIN sys.databases d ON d.database_id = mf.database_id
            WHERE d.name = ?
            ORDER BY mf.file_id
            """,
            database,
        ).fetchall()
    return [str(row[0]) for row in rows]


def _validate_target_storage(config: Config) -> list[str]:
    paths = _database_file_paths(config, config.target_database)
    if not paths:
        raise RuntimeError(
            f"SQL Server returned no files for {config.target_database}."
        )
    invalid = [
        path
        for path in paths
        if Path(path).drive.upper() != REQUIRED_STORAGE_DRIVE
    ]
    if invalid and not config.allow_non_f_storage:
        raise RuntimeError(
            f"Refusing target {config.target_database}: database files are "
            f"outside F: {', '.join(invalid)}"
        )
    print(
        "[storage] target files: " + ", ".join(paths),
        flush=True,
    )
    return paths


def _validate_tempdb_storage(config: Config, strict: bool) -> list[str]:
    paths = _database_file_paths(config, "tempdb")
    invalid = [
        path
        for path in paths
        if Path(path).drive.upper() != REQUIRED_STORAGE_DRIVE
    ]
    if not invalid:
        print("[storage] tempdb files are on F:", flush=True)
        return paths
    message = (
        "tempdb files are outside F: "
        + ", ".join(invalid)
        + ". Large ETL operations can grow tempdb and consume that drive."
    )
    if strict and not config.allow_tempdb_off_f:
        raise RuntimeError(
            "Refusing database-changing ETL because "
            + message
            + " Move tempdb to F:, or use --allow-tempdb-off-f only after "
            "checking C: free space."
        )
    print(f"[storage warning] {message}", flush=True)
    return paths


def create_target_database(config: Config) -> None:
    if _database_exists(config, config.target_database):
        raise RuntimeError(
            f"Fresh target already exists: {config.target_database}. "
            "Choose another --target-db. Use a reviewed domains-stage "
            "recovery command only for an existing target."
        )

    data_file = config.data_dir / f"{config.target_database}.mdf"
    log_file = config.log_dir / f"{config.target_database}_log.ldf"
    sql = f"""
    CREATE DATABASE [{config.target_database}]
    ON PRIMARY (
      NAME = N'{config.target_database}',
      FILENAME = N'{str(data_file).replace("'", "''")}',
      SIZE = {config.initial_data_mb}MB,
      FILEGROWTH = {config.filegrowth_mb}MB
    )
    LOG ON (
      NAME = N'{config.target_database}_log',
      FILENAME = N'{str(log_file).replace("'", "''")}',
      SIZE = {config.initial_log_mb}MB,
      FILEGROWTH = {config.filegrowth_mb}MB
    )
    """
    execute_sql(config, sql, "create target database", database="master")
    _validate_target_storage(config)


def _target_has_tables(config: Config) -> bool:
    with _connect(config, config.target_database) as conn:
        row = conn.cursor().execute(
            """
            SELECT COUNT(*)
            FROM sys.tables t
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            WHERE s.name = ?
            """,
            config.schema,
        ).fetchone()
    return bool(row and row[0])


def run_ddl(config: Config) -> None:
    if _target_has_tables(config):
        raise RuntimeError(
            f"Refusing to apply DDL to non-empty {config.target_database}."
        )
    execute_sql(config, render_ddl_sql(config), "CDM DDL")


def _vocabulary_counts(config: Config) -> dict[str, int]:
    names = tuple(VOCAB_MINIMUM_ROWS)
    placeholders = ",".join("?" for _ in names)
    with _connect(config, config.target_database) as conn:
        cursor = conn.cursor()
        counts = {
            str(name).upper(): int(count or 0)
            for name, count in cursor.execute(
                f"""
                SELECT UPPER(t.name), SUM(p.rows)
                FROM sys.tables t
                JOIN sys.schemas s ON s.schema_id = t.schema_id
                JOIN sys.partitions p
                  ON p.object_id = t.object_id
                 AND p.index_id IN (0, 1)
                WHERE s.name = ?
                  AND UPPER(t.name) IN ({placeholders})
                GROUP BY t.name
                """,
                config.schema,
                *names,
            )
        }
        maps_row = cursor.execute(
            f"""
            SELECT COUNT_BIG(*)
            FROM {config.schema}.CONCEPT_RELATIONSHIP
            WHERE relationship_id = 'Maps to'
              AND invalid_reason IS NULL
            """
        ).fetchone()
    counts["ACTIVE_MAPS_TO"] = int((maps_row[0] if maps_row else 0) or 0)
    return counts


def validate_vocabulary(config: Config) -> dict[str, int]:
    counts = _vocabulary_counts(config)
    failures = [
        f"{name}={counts.get(name, 0):,} (required >= {minimum:,})"
        for name, minimum in VOCAB_MINIMUM_ROWS.items()
        if counts.get(name, 0) < minimum
    ]
    if counts["ACTIVE_MAPS_TO"] < 1:
        failures.append("active Maps to relationships=0")
    if failures:
        raise RuntimeError(
            f"Incomplete vocabulary in {config.target_database}: "
            + "; ".join(failures)
        )
    return counts


def _validate_vocabulary_files(config: Config) -> None:
    missing = [
        name
        for name in REQUIRED_VOCAB_FILES
        if not (config.vocabulary_folder / name).is_file()
    ]
    if missing:
        raise FileNotFoundError(
            f"Vocabulary files missing from {config.vocabulary_folder}: "
            + ", ".join(missing)
        )
    if shutil.which("sqlcmd") is None:
        raise FileNotFoundError("sqlcmd was not found on PATH.")


def _sqlcmd_args(config: Config, sql_path: str) -> list[str]:
    args = [
        "sqlcmd",
        "-S",
        config.server,
        "-d",
        config.target_database,
        "-b",
        "-r",
        "1",
        "-f",
        "65001",
        "-C",
        "-i",
        sql_path,
    ]
    if config.windows_auth:
        args[3:3] = ["-E"]
    else:
        username = os.environ.get("SQLSERVER_USERNAME")
        password = os.environ.get("SQLSERVER_PASSWORD")
        if not username or not password:
            raise RuntimeError(
                "SQL authentication requires SQLSERVER_USERNAME and "
                "SQLSERVER_PASSWORD."
            )
        args[3:3] = ["-U", username, "-P", password]
    return args


def run_vocabulary(config: Config) -> None:
    concept_rows = _fast_table_rows(config, "concept")
    if concept_rows is None:
        raise RuntimeError(
            "Target CDM tables are missing. Run --stage ddl first."
        )
    if concept_rows > 0:
        raise RuntimeError(
            f"Refusing vocabulary reload: concept already has "
            f"{concept_rows:,} rows. Use a fresh target database."
        )
    _validate_vocabulary_files(config)
    rendered = render_vocabulary_sql(config)
    temp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            suffix=".sql",
            prefix="omop_vocabulary_",
            delete=False,
        ) as temp:
            temp.write(rendered)
            temp_path = Path(temp.name)
        print(
            f"[vocabulary] loading {config.vocabulary_folder} into "
            f"{config.target_database}",
            flush=True,
        )
        subprocess.check_call(_sqlcmd_args(config, str(temp_path)))
    finally:
        if temp_path:
            temp_path.unlink(missing_ok=True)

    counts = validate_vocabulary(config)
    print(
        "[vocabulary] "
        + ", ".join(f"{name}={count:,}" for name, count in counts.items()),
        flush=True,
    )


def _fast_table_rows(config: Config, table: str) -> int | None:
    with _connect(config, config.target_database) as conn:
        row = conn.cursor().execute(
            """
            SELECT SUM(p.rows)
            FROM sys.tables t
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            JOIN sys.partitions p
              ON p.object_id = t.object_id
             AND p.index_id IN (0, 1)
            WHERE s.name = ?
              AND t.name = ?
            """,
            config.schema,
            table,
        ).fetchone()
    return None if not row or row[0] is None else int(row[0])


def _guard_dependencies(config: Config, step: Step) -> None:
    failures: list[str] = []
    for table in step.requires_nonempty:
        rows = _fast_table_rows(config, table)
        if rows is None:
            failures.append(f"{table}=missing")
        elif rows < 1:
            failures.append(f"{table}=0")
    if failures:
        raise RuntimeError(
            f"Cannot run {step.key}; predecessor output is unavailable: "
            + ", ".join(failures)
        )


def run_step(config: Config, step: Step, reset: bool = False) -> None:
    _guard_dependencies(config, step)
    rows = _fast_table_rows(config, step.target_table)
    if rows is None:
        raise RuntimeError(f"Target table is missing: {step.target_table}")
    if rows > 0 and not reset:
        raise RuntimeError(
            f"Refusing {step.key}: {step.target_table} already has "
            f"{rows:,} rows. Use --resume --reset for intentional replacement."
        )
    if reset:
        execute_sql(
            config,
            f"TRUNCATE TABLE {config.schema}.{step.target_table};",
            f"reset {step.target_table}",
        )
    execute_sql(
        config,
        render_domain_sql(config, step.sql_file),
        step.key,
    )
    after = _fast_table_rows(config, step.target_table)
    print(f"[count] {step.target_table}={int(after or 0):,}", flush=True)


def run_master(config: Config) -> None:
    rows = _fast_table_rows(config, "SEQ_MASTER")
    if rows is not None and rows > 0:
        raise RuntimeError(
            f"Refusing master rebuild: SEQ_MASTER already has {rows:,} rows."
        )
    execute_sql(
        config,
        render_domain_sql(config, MASTER_SQL),
        "master_table",
    )
    rows = _fast_table_rows(config, "SEQ_MASTER")
    print(f"[count] SEQ_MASTER={int(rows or 0):,}", flush=True)


def selected_steps(only: str | None) -> list[Step]:
    if not only:
        return [step for step in DOMAIN_STEPS if step.enabled_by_default]
    requested = {item.strip() for item in only.split(",") if item.strip()}
    known = {step.key for step in DOMAIN_STEPS}
    unknown = requested - known
    if unknown:
        raise ValueError(f"Unknown domain step(s): {', '.join(sorted(unknown))}")
    return [step for step in DOMAIN_STEPS if step.key in requested]


def static_dry_run(config: Config, steps: Iterable[Step]) -> None:
    rendered_ddl = render_ddl_sql(config)
    print(
        f"[render] 000.OMOP CDM sql server ddl.sql: "
        f"{len(split_batches(rendered_ddl))} batch(es), "
        f"{len(rendered_ddl):,} chars",
        flush=True,
    )
    rendered_vocab = render_vocabulary_sql(config)
    print(
        f"[render] 001.Import_voca.sql: "
        f"{len(split_batches(rendered_vocab))} batch(es), "
        f"{len(rendered_vocab):,} chars",
        flush=True,
    )
    files = [(MASTER_SQL, render_domain_sql(config, MASTER_SQL))]
    files.extend(
        (step.sql_file, render_domain_sql(config, step.sql_file))
        for step in steps
    )
    for sql_file, rendered in files:
        print(
            f"[render] {sql_file}: {len(split_batches(rendered))} batch(es), "
            f"{len(rendered):,} chars",
            flush=True,
        )
    print(f"[dry-run] rendered {len(files) + 2} SQL files.", flush=True)


def preflight(
    config: Config,
    steps: Iterable[Step],
    require_vocabulary_files: bool,
    require_target: bool,
    require_tempdb_on_f: bool,
) -> None:
    if not config.sql_dir.is_dir():
        raise FileNotFoundError(f"SQL directory not found: {config.sql_dir}")
    if require_vocabulary_files:
        _validate_vocabulary_files(config)
    if not _database_exists(config, config.raw_database):
        raise RuntimeError(f"Raw database not found: {config.raw_database}")

    required_raw = {
        table for step in steps for table in step.required_raw
    }
    required_raw.update(
        ("JP_CLAIMS", "JP_DIAGNOSIS", "JP_DRUG", "JP_PROCEDURE")
    )
    placeholders = ",".join("?" for _ in required_raw)
    with _connect(config, config.raw_database) as conn:
        rows = conn.cursor().execute(
            f"""
            SELECT t.name, SUM(p.rows)
            FROM sys.tables t
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            JOIN sys.partitions p
              ON p.object_id = t.object_id
             AND p.index_id IN (0, 1)
            WHERE s.name = ?
              AND t.name IN ({placeholders})
            GROUP BY t.name
            ORDER BY t.name
            """,
            config.schema,
            *sorted(required_raw),
        ).fetchall()
    actual = {str(name): int(count or 0) for name, count in rows}
    missing = sorted(required_raw - set(actual))
    if missing:
        raise RuntimeError(f"Raw tables missing: {', '.join(missing)}")

    target_exists = _database_exists(config, config.target_database)
    if require_target and not target_exists:
        raise RuntimeError(f"Resume target not found: {config.target_database}")
    if target_exists:
        _validate_target_storage(config)
    print(
        f"[preflight] server={config.server}, raw={config.raw_database}, "
        f"target={config.target_database}, target_exists={target_exists}",
        flush=True,
    )
    for name, count in actual.items():
        print(f"  {name}={count:,}", flush=True)
    if not target_exists:
        print(
            f"  target will be created on {config.data_dir} / {config.log_dir}",
            flush=True,
        )
    _validate_tempdb_storage(config, strict=require_tempdb_on_f)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--stage",
        choices=STAGES,
        help=(
            "Run one pipeline stage. With --execute and no --stage, a fresh "
            "run defaults to all; --resume defaults to domains."
        ),
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Permit database-changing ETL. The default is static dry-run.",
    )
    parser.add_argument(
        "--preflight",
        action="store_true",
        help="Run read-only source, target, and prerequisite checks.",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Skip database creation, DDL, vocabulary import, and master build.",
    )
    parser.add_argument(
        "--only",
        help=(
            "Comma-separated domain steps in pipeline order: "
            + ", ".join(step.key for step in DOMAIN_STEPS)
        ),
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help="TRUNCATE selected domain tables before rebuilding them.",
    )
    parser.add_argument("--raw-db")
    parser.add_argument("--target-db")
    parser.add_argument("--server")
    parser.add_argument("--vocab-folder", type=Path)
    parser.add_argument("--data-dir", type=Path)
    parser.add_argument("--log-dir", type=Path)
    parser.add_argument("--initial-data-mb", type=int)
    parser.add_argument("--initial-log-mb", type=int)
    parser.add_argument("--filegrowth-mb", type=int)
    parser.add_argument(
        "--allow-non-f-storage",
        action="store_true",
        help="Allow MDF/LDF files outside F: after explicit storage review.",
    )
    parser.add_argument(
        "--allow-tempdb-off-f",
        action="store_true",
        help="Permit execution while SQL Server tempdb is outside F:.",
    )
    return parser


def _resolve_stage(
    stage: str | None,
    resume: bool,
    execute: bool,
    preflight_only: bool,
) -> str | None:
    if resume:
        if stage not in (None, "domains"):
            raise ValueError("--resume can be combined only with --stage domains.")
        return "domains"
    if preflight_only and stage not in (None, "preflight"):
        raise ValueError("--preflight cannot be combined with a changing stage.")
    if stage:
        return stage
    if preflight_only:
        return "preflight"
    return "all" if execute else None


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    stage = _resolve_stage(
        args.stage,
        args.resume,
        args.execute,
        args.preflight,
    )
    if args.reset and stage != "domains":
        raise ValueError("--reset is allowed only with the domains stage.")

    config = default_config()
    if args.server:
        config.server = args.server
    if args.raw_db:
        config.raw_database = args.raw_db
    if args.target_db:
        config.target_database = args.target_db
    if args.vocab_folder:
        config.vocabulary_folder = args.vocab_folder
    if args.data_dir:
        config.data_dir = args.data_dir
    if args.log_dir:
        config.log_dir = args.log_dir
    if args.initial_data_mb is not None:
        config.initial_data_mb = args.initial_data_mb
    if args.initial_log_mb is not None:
        config.initial_log_mb = args.initial_log_mb
    if args.filegrowth_mb is not None:
        config.filegrowth_mb = args.filegrowth_mb
    config.allow_non_f_storage = args.allow_non_f_storage
    config.allow_tempdb_off_f = args.allow_tempdb_off_f
    _validate_config(config)

    steps = selected_steps(args.only)
    static_dry_run(config, steps)

    if stage == "preflight" or args.execute:
        preflight(
            config,
            steps,
            require_vocabulary_files=stage in {"vocabulary", "all"},
            require_target=stage in {"vocabulary", "master", "domains"},
            require_tempdb_on_f=args.execute,
        )
    if stage == "preflight" or not args.execute:
        return 0

    if stage == "ddl":
        create_target_database(config)
        run_ddl(config)
    elif stage == "vocabulary":
        run_vocabulary(config)
    elif stage == "master":
        counts = validate_vocabulary(config)
        print(
            f"[vocabulary] validated before master: "
            f"CONCEPT={counts['CONCEPT']:,}, "
            f"CONCEPT_RELATIONSHIP={counts['CONCEPT_RELATIONSHIP']:,}",
            flush=True,
        )
        run_master(config)
    elif stage == "domains":
        counts = validate_vocabulary(config)
        print(
            f"[vocabulary] validated before domains: "
            f"CONCEPT={counts['CONCEPT']:,}, "
            f"CONCEPT_RELATIONSHIP={counts['CONCEPT_RELATIONSHIP']:,}",
            flush=True,
        )
        for step in steps:
            run_step(config, step, reset=args.reset)
    elif stage == "all":
        create_target_database(config)
        run_ddl(config)
        run_vocabulary(config)
        run_master(config)
        for step in steps:
            run_step(config, step, reset=args.reset)
    else:
        raise RuntimeError(f"Unsupported stage: {stage}")

    print(
        f"[complete] {datetime.now().isoformat(timespec='seconds')} "
        f"stage={stage} target={config.target_database}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr, flush=True)
        raise
