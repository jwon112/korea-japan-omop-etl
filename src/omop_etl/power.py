"""Windows power-state guard for long-running ETL batches."""

from __future__ import annotations

from contextlib import contextmanager
import ctypes
import os
from typing import Iterator


ES_CONTINUOUS = 0x80000000
ES_SYSTEM_REQUIRED = 0x00000001


@contextmanager
def prevent_idle_sleep(label: str) -> Iterator[None]:
    """Prevent Windows idle sleep while a SQL batch group is running."""
    active = False
    if os.name == "nt":
        result = ctypes.windll.kernel32.SetThreadExecutionState(
            ES_CONTINUOUS | ES_SYSTEM_REQUIRED
        )
        active = bool(result)
        if active:
            print(
                f"[power] idle sleep inhibited while running {label}",
                flush=True,
            )
        else:
            print(
                f"[power] warning: could not inhibit idle sleep for {label}",
                flush=True,
            )

    try:
        yield
    finally:
        if active:
            ctypes.windll.kernel32.SetThreadExecutionState(ES_CONTINUOUS)
            print("[power] idle sleep policy restored", flush=True)
