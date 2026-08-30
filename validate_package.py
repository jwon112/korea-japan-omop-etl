"""Repository entry point for ETL package validation."""

from pathlib import Path
import sys


SRC = Path(__file__).resolve().parent / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from omop_etl.package_check import main


if __name__ == "__main__":
    raise SystemExit(main())
