"""Offline and SQL Server parser validation for the packaged ETL assets."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import sys
from typing import Callable

import pyodbc

from omop_etl import japan, korea


@dataclass(frozen=True)
class SqlAsset:
    country: str
    filename: str
    sql: str
    split_batches: Callable[[str], list[str]]

    @property
    def label(self) -> str:
        return f"{self.country}/{self.filename}"


def korea_sql_files() -> tuple[str, ...]:
    return (
        "000.OMOP CDM sql server ddl.sql",
        "001.Import_voca.sql",
        korea.MASTER_STEP.sql_file,
        *(step.sql_file for step in korea.DOMAIN_STEPS),
        *(step.sql_file for step in korea.POST_STEPS),
    )


def japan_sql_files() -> tuple[str, ...]:
    return (
        "000.OMOP CDM sql server ddl.sql",
        "001.Import_voca.sql",
        japan.MASTER_SQL,
        *(step.sql_file for step in japan.DOMAIN_STEPS),
    )


def _assert_asset_set(sql_dir: Path, expected: tuple[str, ...]) -> None:
    actual = {path.name for path in sql_dir.glob("*.sql")}
    expected_set = set(expected)
    missing = sorted(expected_set - actual)
    unmanaged = sorted(actual - expected_set)
    if missing or unmanaged:
        details: list[str] = []
        if missing:
            details.append("missing=" + ", ".join(missing))
        if unmanaged:
            details.append("unmanaged=" + ", ".join(unmanaged))
        raise RuntimeError(f"SQL asset mismatch in {sql_dir}: " + "; ".join(details))


def collect_assets(
    korea_config: korea.Config | None = None,
    japan_config: japan.Config | None = None,
) -> list[SqlAsset]:
    korea_config = korea_config or korea.default_config()
    japan_config = japan_config or japan.default_config()
    korea._validate_config(korea_config)
    japan._validate_config(japan_config)

    korea_files = korea_sql_files()
    japan_files = japan_sql_files()
    _assert_asset_set(korea_config.sql_dir, korea_files)
    _assert_asset_set(japan_config.sql_dir, japan_files)

    assets = [
        SqlAsset(
            "korea",
            filename,
            korea.render_sql(korea_config, filename),
            korea.split_batches,
        )
        for filename in korea_files
    ]
    for filename in japan_files:
        if filename == "000.OMOP CDM sql server ddl.sql":
            rendered = japan.render_ddl_sql(japan_config)
        elif filename == "001.Import_voca.sql":
            rendered = japan.render_vocabulary_sql(japan_config)
        else:
            rendered = japan.render_domain_sql(japan_config, filename)
        assets.append(
            SqlAsset("japan", filename, rendered, japan.split_batches)
        )
    return assets


def run_offline_check(
    korea_config: korea.Config | None = None,
    japan_config: japan.Config | None = None,
) -> list[SqlAsset]:
    assets = collect_assets(korea_config, japan_config)
    counts = {"korea": 0, "japan": 0}
    total_batches = 0
    for asset in assets:
        batches = asset.split_batches(asset.sql)
        if not batches:
            raise RuntimeError(f"Rendered SQL has no batches: {asset.label}")
        counts[asset.country] += 1
        total_batches += len(batches)
    print(
        "[package] offline validation ok: "
        f"korea_sql={counts['korea']}, japan_sql={counts['japan']}, "
        f"batches={total_batches}",
        flush=True,
    )
    return assets


def _connection_string(server: str) -> str:
    base = (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={server};DATABASE=master;"
        "Encrypt=no;Connection Timeout=30;"
    )
    if os.environ.get("SQLSERVER_WINDOWS_AUTH", "1") != "0":
        return base + "Trusted_Connection=Yes;"
    username = os.environ.get("SQLSERVER_USERNAME")
    password = os.environ.get("SQLSERVER_PASSWORD")
    if not username or not password:
        raise RuntimeError(
            "SQL authentication requires SQLSERVER_USERNAME and "
            "SQLSERVER_PASSWORD."
        )
    return base + f"UID={username};PWD={password};"


def _drain_results(cursor) -> None:
    while True:
        if cursor.description:
            cursor.fetchall()
        if not cursor.nextset():
            return


def run_sqlserver_parse_check(server: str, assets: list[SqlAsset]) -> None:
    parsed_batches = 0
    with pyodbc.connect(
        _connection_string(server),
        autocommit=True,
        timeout=30,
    ) as connection:
        cursor = connection.cursor()
        cursor.execute("SET PARSEONLY ON;")
        for asset in assets:
            batches = asset.split_batches(asset.sql)
            for index, batch in enumerate(batches, start=1):
                try:
                    cursor.execute(batch)
                    _drain_results(cursor)
                except Exception as exc:
                    raise RuntimeError(
                        f"SQL Server parse failed: {asset.label} "
                        f"batch {index}/{len(batches)}: {exc}"
                    ) from exc
                parsed_batches += 1
        cursor.execute("SET PARSEONLY OFF;")
    print(
        f"[package] SQL Server PARSEONLY ok: {parsed_batches} batches",
        flush=True,
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--sqlserver-parse",
        action="store_true",
        help="Ask SQL Server to parse every rendered batch without executing it.",
    )
    parser.add_argument(
        "--server",
        default=os.environ.get("SQLSERVER_SERVER", r"localhost\SQLEXPRESS"),
    )
    parser.add_argument("--vocab-folder", type=Path)
    parser.add_argument(
        "--korea-target-db",
        help="Existing database name used to render Korea USE statements.",
    )
    parser.add_argument(
        "--korea-mapping-db",
        help="Existing Korea mapping DB; defaults to --korea-target-db.",
    )
    parser.add_argument(
        "--japan-target-db",
        help="Existing database name used to render Japan USE statements.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    korea_config = korea.default_config()
    japan_config = japan.default_config()
    if args.vocab_folder:
        korea_config.vocabulary_folder = args.vocab_folder
        japan_config.vocabulary_folder = args.vocab_folder
    if args.korea_target_db:
        korea_config.target_database = args.korea_target_db
        korea_config.mapping_database = (
            args.korea_mapping_db or args.korea_target_db
        )
    elif args.korea_mapping_db:
        korea_config.mapping_database = args.korea_mapping_db
    if args.japan_target_db:
        japan_config.target_database = args.japan_target_db
    assets = run_offline_check(korea_config, japan_config)
    if args.sqlserver_parse:
        run_sqlserver_parse_check(args.server, assets)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr, flush=True)
        raise
