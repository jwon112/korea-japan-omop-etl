"""
Python orchestrator for the NHIS-NSC SQL Server ETL.

The original domain SQL is preserved. This module replaces the R/SqlRender
execution layer with explicit configuration, dry-run rendering, preflight
checks, safe fresh-database creation, row-count logging, and resumable stages.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime
import os
from pathlib import Path
import re
import sys
import time
from typing import Iterable

import pyodbc

from .power import prevent_idle_sleep


@dataclass(frozen=True)
class Step:
    key: str
    sql_file: str
    target_table: str | None
    creates_target: bool = False
    requires_nonempty: tuple[str, ...] = ()
    additional_targets: tuple[str, ...] = ()


@dataclass
class Config:
    server: str
    raw_database: str
    target_database: str
    mapping_database: str
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
    table_20: str = "NHID_20"
    table_30: str = "NHID_30"
    table_40: str = "NHID_40"
    table_60: str = "NHID_60"
    table_gj: str = "NHID_GJ"
    table_jk: str = "NHID_JK"
    table_yk: str = "NHID_YK"


MASTER_STEP = Step(
    "master_table", "010.Master_table.sql", "SEQ_MASTER", creates_target=True
)

DOMAIN_STEPS = (
    Step("location", "020.Location.sql", "location"),
    Step("care_site", "030.Care_site.sql", "care_site"),
    Step(
        "person",
        "040.Person.sql",
        "person",
        requires_nonempty=("location",),
    ),
    Step("death", "050.Death.sql", "death", requires_nonempty=("person",)),
    Step(
        "observation_period",
        "060.Observation_period.sql",
        "observation_period",
        requires_nonempty=("person",),
    ),
    Step(
        "visit_occurrence",
        "070.Visit_occurrence.sql",
        "visit_occurrence",
        requires_nonempty=("person", "care_site", "SEQ_MASTER"),
    ),
    Step(
        "condition_occurrence",
        "080.Condition_occurrence.sql",
        "condition_occurrence",
        requires_nonempty=(
            "person",
            "SEQ_MASTER",
            "observation_period",
            "visit_occurrence",
        ),
    ),
    Step(
        "observation",
        "090.Observation.sql",
        "observation",
        requires_nonempty=("person", "SEQ_MASTER", "visit_occurrence"),
    ),
    Step(
        "drug_exposure",
        "100.Drug_exposure.sql",
        "drug_exposure",
        requires_nonempty=("person", "SEQ_MASTER", "visit_occurrence"),
    ),
    Step(
        "procedure_occurrence",
        "110.Procedure_occurrence.sql",
        "procedure_occurrence",
        requires_nonempty=("person", "SEQ_MASTER", "visit_occurrence"),
    ),
    Step(
        "device_exposure",
        "120.Device_exposure.sql",
        "device_exposure",
        requires_nonempty=("person", "SEQ_MASTER", "visit_occurrence"),
    ),
    Step(
        "measurement",
        "130.Measurement.sql",
        "measurement",
        requires_nonempty=(
            "person",
            "SEQ_MASTER",
            "GJ_VERTICAL",
            "observation",
            "visit_occurrence",
        ),
    ),
    Step(
        "payer_plan_period",
        "140.Payer_plan_period.sql",
        "payer_plan_period",
        requires_nonempty=("person", "observation_period"),
    ),
    Step(
        "cost",
        "150.Cost.sql",
        "cost",
        requires_nonempty=(
            "person",
            "SEQ_MASTER",
            "visit_occurrence",
            "drug_exposure",
            "procedure_occurrence",
            "device_exposure",
            "payer_plan_period",
        ),
    ),
)

POST_STEPS = (
    Step(
        "generate_era",
        "300.GenerateEra.sql",
        "drug_era",
        requires_nonempty=("drug_exposure", "condition_occurrence"),
        additional_targets=("condition_era",),
    ),
    Step("cdm_source", "320.CDM_source.sql", "cdm_source"),
    Step("indexing", "400.Indexing.sql", None),
    Step("constraints", "500.Constraints.sql", None),
)

# Only source metadata is part of the default closeout path. Derived eras and
# large physical-design operations require an explicit --only selection.
DEFAULT_POST_STEP_KEYS = {"cdm_source"}

REQUIRED_RAW_TABLES = (
    "NHID_20",
    "NHID_30",
    "NHID_40",
    "NHID_60",
    "NHID_GJ",
    "NHID_JK",
    "NHID_YK",
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
TOKEN_PATTERN = re.compile(r"(?<!@)@[A-Za-z_][A-Za-z0-9_]*")
BLOCK_COMMENT_PATTERN = re.compile(r"/\*.*?\*/", re.DOTALL)
LINE_COMMENT_PATTERN = re.compile(r"--[^\r\n]*")
REQUIRED_STORAGE_DRIVE = "F:"


def default_config() -> Config:
    script_dir = Path(__file__).resolve().parent
    return Config(
        server=os.environ.get(
            "SQLSERVER_SERVER", r"localhost\SQLEXPRESS"
        ),
        raw_database=os.environ.get("KOREA_RAW_DB", "nhisnsc2013original"),
        target_database=os.environ.get(
            "KOREA_CDM_DB", "korea_cohort_cdm_final"
        ),
        mapping_database=os.environ.get(
            "KOREA_MAPPING_DB", "korea_cohort_cdm_final"
        ),
        sql_dir=script_dir / "sql" / "korea",
        vocabulary_folder=Path(
            os.environ.get("VOCAB_FOLDER", str(Path.cwd() / "vocabulary"))
        ),
        data_dir=Path(os.environ.get("SQLSERVER_DATA_DIR", r"F:\database\data")),
        log_dir=Path(os.environ.get("SQLSERVER_LOG_DIR", r"F:\database\log")),
        initial_data_mb=int(
            os.environ.get("KOREA_INITIAL_DATA_MB", "153600")
        ),
        initial_log_mb=int(
            os.environ.get("KOREA_INITIAL_LOG_MB", "51200")
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
    for label, value in (
        ("raw database", config.raw_database),
        ("target database", config.target_database),
        ("mapping database", config.mapping_database),
        ("schema", config.schema),
        ("NHID_20 table", config.table_20),
        ("NHID_30 table", config.table_30),
        ("NHID_40 table", config.table_40),
        ("NHID_60 table", config.table_60),
        ("NHID_GJ table", config.table_gj),
        ("NHID_JK table", config.table_jk),
        ("NHID_YK table", config.table_yk),
    ):
        _validate_identifier(value, label)
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
            "SQL authentication requires SQLSERVER_USERNAME and SQLSERVER_PASSWORD."
        )
    return base + f"UID={username};PWD={password};"


def _connect(config: Config, database: str, autocommit: bool = True):
    connection = pyodbc.connect(
        _connection_string(config, database), autocommit=autocommit
    )
    connection.timeout = 0
    return connection


def _qualified(database: str, schema: str) -> str:
    return f"{database}.{schema}"


def _replacements(config: Config, sql_file: str) -> dict[str, str]:
    database_only_files = {
        "000.OMOP CDM sql server ddl.sql",
        "001.Import_voca.sql",
        "400.Indexing.sql",
        "500.Constraints.sql",
    }
    target_value = (
        config.target_database
        if sql_file in database_only_files
        else _qualified(config.target_database, config.schema)
    )
    mapping_value = (
        config.mapping_database
        if sql_file in {"001.Import_voca.sql", "500.Constraints.sql"}
        else _qualified(config.mapping_database, config.schema)
    )
    return {
        "@NHISNSC_rawdata": _qualified(config.raw_database, config.schema),
        "@NHISNSC_database": target_value,
        "@Mapping_database": mapping_value,
        "@NHIS_20T": config.table_20,
        "@NHIS_30T": config.table_30,
        "@NHIS_40T": config.table_40,
        "@NHIS_60T": config.table_60,
        "@NHIS_GJ": config.table_gj,
        "@NHIS_JK": config.table_jk,
        "@NHIS_YK": config.table_yk,
        "@vocaFolder": str(config.vocabulary_folder.resolve()),
    }


def _active_sql(sql: str) -> str:
    without_blocks = BLOCK_COMMENT_PATTERN.sub("", sql)
    return LINE_COMMENT_PATTERN.sub("", without_blocks)


def render_sql(config: Config, sql_file: str) -> str:
    path = config.sql_dir / sql_file
    if not path.is_file():
        raise FileNotFoundError(f"SQL file not found: {path}")
    rendered = path.read_text(encoding="utf-8")

    replacements = _replacements(config, sql_file)
    for token in sorted(replacements, key=len, reverse=True):
        value = replacements[token]
        rendered = rendered.replace("@" + token, value)
        rendered = rendered.replace(token, value)

    active = _active_sql(rendered)
    declared = {
        token.lower()
        for token in re.findall(
            r"\bDECLARE\s+(@[A-Za-z_][A-Za-z0-9_]*)",
            active,
            flags=re.IGNORECASE,
        )
    }
    unresolved = sorted(
        {
            token
            for token in TOKEN_PATTERN.findall(active)
            if token.lower() not in declared
        }
    )
    if unresolved:
        raise RuntimeError(
            f"{sql_file} has unresolved active placeholders: {', '.join(unresolved)}"
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


def _fast_table_rows(config: Config, database: str, table: str) -> int | None:
    sql = """
    SELECT SUM(p.rows)
    FROM sys.tables t
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    JOIN sys.partitions p
      ON p.object_id = t.object_id
     AND p.index_id IN (0, 1)
    WHERE s.name = ?
      AND t.name = ?
    """
    with _connect(config, database) as conn:
        row = conn.cursor().execute(sql, config.schema, table).fetchone()
    return None if not row or row[0] is None else int(row[0])


def create_target_database(
    config: Config, allow_existing: bool = False
) -> bool:
    if _database_exists(config, config.target_database):
        _validate_target_storage(config)
        if not allow_existing:
            raise RuntimeError(
                f"Target database {config.target_database} already exists. "
                "Use --allow-existing only for an intentional resume."
            )
        print(f"[database] using existing {config.target_database}", flush=True)
        return False

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
    return True


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
            f"Refusing to apply DDL to non-empty {config.target_database}. "
            "Use a fresh or empty target database."
        )
    execute_sql(
        config,
        render_sql(config, "000.OMOP CDM sql server ddl.sql"),
        "CDM DDL",
    )


def _vocabulary_counts(config: Config) -> dict[str, int]:
    names = tuple(VOCAB_MINIMUM_ROWS)
    placeholders = ",".join("?" for _ in names)
    sql = f"""
    SELECT UPPER(t.name), SUM(p.rows)
    FROM sys.tables t
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    JOIN sys.partitions p
      ON p.object_id = t.object_id
     AND p.index_id IN (0, 1)
    WHERE s.name = ?
      AND UPPER(t.name) IN ({placeholders})
    GROUP BY t.name
    """
    with _connect(config, config.mapping_database) as conn:
        cursor = conn.cursor()
        counts = {
            str(name).upper(): int(count or 0)
            for name, count in cursor.execute(sql, config.schema, *names)
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
        f"{table}={counts.get(table, 0):,} (required >= {minimum:,})"
        for table, minimum in VOCAB_MINIMUM_ROWS.items()
        if counts.get(table, 0) < minimum
    ]
    if counts["ACTIVE_MAPS_TO"] < 1:
        failures.append("active Maps to relationships=0")
    if failures:
        raise RuntimeError(
            f"Incomplete vocabulary in {config.mapping_database}: "
            + "; ".join(failures)
        )
    return counts


def configure_file_growth(config: Config) -> None:
    with _connect(config, config.target_database) as conn:
        files = conn.cursor().execute(
            "SELECT name FROM sys.database_files ORDER BY file_id"
        ).fetchall()
    for (logical_name,) in files:
        safe_name = str(logical_name).replace("'", "''")
        execute_sql(
            config,
            f"""
            ALTER DATABASE [{config.target_database}]
            MODIFY FILE (
                NAME = N'{safe_name}',
                FILEGROWTH = {config.filegrowth_mb}MB
            )
            """,
            f"configure file growth: {logical_name}",
            database="master",
        )


def run_vocabulary(config: Config) -> None:
    configure_file_growth(config)
    execute_sql(
        config,
        render_sql(config, "001.Import_voca.sql"),
        "Athena vocabulary import",
        database=config.target_database,
    )
    counts = validate_vocabulary(config)
    print(
        "[vocabulary] "
        + ", ".join(f"{name}={count:,}" for name, count in counts.items()),
        flush=True,
    )


def _step_targets(step: Step) -> tuple[str, ...]:
    return tuple(
        table
        for table in (step.target_table, *step.additional_targets)
        if table
    )


def _guard_step_target(config: Config, step: Step) -> None:
    targets = _step_targets(step)
    if not targets:
        return
    for table in targets:
        rows = _fast_table_rows(config, config.target_database, table)
        if rows is None:
            if step.creates_target and table == step.target_table:
                continue
            raise RuntimeError(
                f"Target table is missing for {step.key}: {table}"
            )
        if rows > 0:
            raise RuntimeError(
                f"Refusing {step.key}: {table} already has {rows:,} rows. "
                "Use a fresh target or explicitly clear only that failed stage "
                "after reviewing its partial state."
            )


def _guard_step_dependencies(config: Config, step: Step) -> None:
    failures: list[str] = []
    for table in step.requires_nonempty:
        rows = _fast_table_rows(config, config.target_database, table)
        if rows is None:
            failures.append(f"{table}=missing")
        elif rows < 1:
            failures.append(f"{table}=0")
    if failures:
        raise RuntimeError(
            f"Cannot run {step.key}; required predecessor output is unavailable: "
            + ", ".join(failures)
            + ". Run the prerequisite stages in pipeline order."
        )


def _reset_step_targets(config: Config, step: Step) -> None:
    targets = _step_targets(step)
    if not targets:
        raise RuntimeError(f"Step {step.key} has no resettable target table.")
    downstream: list[str] = []
    target_set = set(targets)
    for candidate in (*DOMAIN_STEPS, *POST_STEPS):
        if candidate.key == step.key:
            continue
        if not target_set.intersection(candidate.requires_nonempty):
            continue
        for table in _step_targets(candidate):
            rows = _fast_table_rows(config, config.target_database, table)
            if rows:
                downstream.append(f"{table}={rows:,}")
    if downstream:
        raise RuntimeError(
            f"Refusing reset of {step.key}; downstream output exists: "
            + ", ".join(downstream)
        )
    sql = "\n".join(
        f"TRUNCATE TABLE {config.schema}.{table};"
        for table in reversed(targets)
    )
    execute_sql(config, sql, f"reset {step.key}")


def run_step(config: Config, step: Step, reset: bool = False) -> None:
    _guard_step_dependencies(config, step)
    if reset:
        _reset_step_targets(config, step)
    _guard_step_target(config, step)
    execute_sql(config, render_sql(config, step.sql_file), step.key)
    for table in _step_targets(step):
        if table:
            rows = _fast_table_rows(config, config.target_database, table)
            print(f"[count] {table}={int(rows or 0):,}", flush=True)
            if not rows:
                raise RuntimeError(
                    f"Step {step.key} completed but {table} has no rows."
                )


def reset_master(config: Config) -> None:
    populated: list[str] = []
    for step in DOMAIN_STEPS:
        for table in _step_targets(step):
            rows = _fast_table_rows(config, config.target_database, table)
            if rows:
                populated.append(f"{table}={rows:,}")
    if populated:
        raise RuntimeError(
            "Refusing master reset because downstream tables contain rows: "
            + ", ".join(populated)
        )
    execute_sql(
        config,
        f"""
        IF OBJECT_ID('{config.schema}.SEQ_MASTER', 'U') IS NOT NULL
            DROP TABLE {config.schema}.SEQ_MASTER;
        IF OBJECT_ID('{config.schema}.NHIS_CLAIM_PERSON', 'U') IS NOT NULL
            DROP TABLE {config.schema}.NHIS_CLAIM_PERSON;
        """,
        "reset master staging",
    )


def selected_steps(
    steps: Iterable[Step], only: set[str] | None
) -> list[Step]:
    if not only:
        return list(steps)
    return [step for step in steps if step.key in only]


def static_dry_run(config: Config) -> None:
    files = [
        "000.OMOP CDM sql server ddl.sql",
        "001.Import_voca.sql",
        MASTER_STEP.sql_file,
        *(step.sql_file for step in DOMAIN_STEPS),
        *(step.sql_file for step in POST_STEPS),
    ]
    for sql_file in files:
        rendered = render_sql(config, sql_file)
        print(
            f"[render] {sql_file}: {len(split_batches(rendered))} batch(es), "
            f"{len(rendered):,} chars",
            flush=True,
        )
    print(f"[dry-run] rendered {len(files)} SQL files successfully.", flush=True)


def preflight(
    config: Config,
    require_vocabulary_files: bool = False,
    require_tempdb_on_f: bool = False,
) -> None:
    if not config.sql_dir.is_dir():
        raise FileNotFoundError(f"SQL directory not found: {config.sql_dir}")
    if require_vocabulary_files:
        missing_vocab = [
            name
            for name in REQUIRED_VOCAB_FILES
            if not (config.vocabulary_folder / name).is_file()
        ]
        if missing_vocab:
            raise FileNotFoundError(
                f"Vocabulary files missing: {', '.join(missing_vocab)}"
            )
    if not _database_exists(config, config.raw_database):
        raise RuntimeError(f"Raw database not found: {config.raw_database}")

    table_config = {
        config.table_20,
        config.table_30,
        config.table_40,
        config.table_60,
        config.table_gj,
        config.table_jk,
        config.table_yk,
    }
    placeholders = ",".join("?" for _ in table_config)
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
            *sorted(table_config),
        ).fetchall()
    actual = {str(name): int(count or 0) for name, count in rows}
    missing_tables = sorted(table_config - set(actual))
    if missing_tables:
        raise RuntimeError(f"Raw tables missing: {', '.join(missing_tables)}")

    print(
        f"[preflight] server={config.server}, raw={config.raw_database}, "
        f"target={config.target_database}",
        flush=True,
    )
    for name, count in actual.items():
        print(f"  {name}={count:,}", flush=True)
    if _database_exists(config, config.target_database):
        _validate_target_storage(config)
        print(f"  target database exists: {config.target_database}", flush=True)
    else:
        print(
            f"  target database will be created on {config.data_dir} / {config.log_dir}",
            flush=True,
        )
    _validate_tempdb_storage(config, strict=require_tempdb_on_f)


def _parse_only(value: str | None) -> set[str] | None:
    if not value:
        return None
    return {item.strip() for item in value.split(",") if item.strip()}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--stage",
        choices=("preflight", "ddl", "vocabulary", "master", "domains", "post", "all"),
        default="preflight",
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Permit database-changing stages. Without this flag only checks run.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Render every SQL file and verify placeholders without connecting.",
    )
    parser.add_argument(
        "--only",
        help=(
            "Comma-separated domain or post step keys. Domain order: "
            + ", ".join(step.key for step in DOMAIN_STEPS)
            + ". Post order: "
            + ", ".join(step.key for step in POST_STEPS)
        ),
    )
    parser.add_argument("--raw-db")
    parser.add_argument("--target-db")
    parser.add_argument("--mapping-db")
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
    parser.add_argument("--allow-existing", action="store_true")
    parser.add_argument(
        "--reset",
        action="store_true",
        help=(
            "Explicitly clear one failed master/domain/post step before rerun. "
            "Domains and post stages require exactly one --only key."
        ),
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    config = default_config()
    if args.server:
        config.server = args.server
    if args.raw_db:
        config.raw_database = args.raw_db
    if args.target_db:
        config.target_database = args.target_db
    if args.mapping_db:
        config.mapping_database = args.mapping_db
    elif args.target_db:
        config.mapping_database = args.target_db
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

    if args.dry_run:
        static_dry_run(config)
        return 0

    preflight(
        config,
        require_vocabulary_files=args.stage in {"vocabulary", "all"},
        require_tempdb_on_f=args.execute and args.stage != "preflight",
    )
    if args.stage == "preflight":
        return 0
    if not args.execute:
        raise RuntimeError(
            "Database-changing stages require --execute. Run --dry-run first."
        )

    only = _parse_only(args.only)
    if only:
        known = {
            MASTER_STEP.key,
            *(step.key for step in DOMAIN_STEPS),
            *(step.key for step in POST_STEPS),
        }
        unknown = only - known
        if unknown:
            raise ValueError(f"Unknown step(s): {', '.join(sorted(unknown))}")
    if args.reset:
        if args.stage not in {"master", "domains", "post"}:
            raise ValueError(
                "--reset is allowed only with master, domains, or post."
            )
        if args.stage in {"domains", "post"} and (
            not only or len(only) != 1
        ):
            raise ValueError(
                "--reset for domains/post requires exactly one --only step."
            )

    if args.stage in {"ddl", "all"}:
        create_target_database(config, allow_existing=args.allow_existing)
        run_ddl(config)
    if args.stage in {"vocabulary", "all"}:
        run_vocabulary(config)
    elif args.stage in {"master", "domains", "post"}:
        counts = validate_vocabulary(config)
        print(
            f"[vocabulary] validated before {args.stage}: "
            f"CONCEPT={counts['CONCEPT']:,}, "
            f"CONCEPT_RELATIONSHIP={counts['CONCEPT_RELATIONSHIP']:,}",
            flush=True,
        )
    if args.stage in {"master", "all"}:
        if args.reset:
            reset_master(config)
        run_step(config, MASTER_STEP)
    if args.stage in {"domains", "all"}:
        for step in selected_steps(DOMAIN_STEPS, only):
            run_step(config, step, reset=args.reset)
    if args.stage in {"post", "all"}:
        post_selection = only if only is not None else DEFAULT_POST_STEP_KEYS
        for step in selected_steps(POST_STEPS, post_selection):
            run_step(config, step, reset=args.reset)
    print(
        f"[complete] {datetime.now().isoformat(timespec='seconds')} "
        f"stage={args.stage}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr, flush=True)
        raise
