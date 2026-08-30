"""Repository entry point for shared read-only CDM QA."""

from pathlib import Path
import sys


SRC = Path(__file__).resolve().parent / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from omop_etl.qa import main


if __name__ == "__main__":
    raise SystemExit(main())
