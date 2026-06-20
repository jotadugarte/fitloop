# [REQ-FIT-JOB-001] Atomic progress.json writer for CLI nesting runs.
from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

PROGRESS_SCHEMA_VERSION = 2

VALID_PHASE_IDS = frozenset(
    {
        "extracting",
        "fill",
        "optimizing",
        "consolidating",
        "refining",
        "writing_outputs",
    }
)

_THROTTLE_SECONDS = 1.0
_THROTTLE_PERCENT_DELTA = 1


class ProgressReporter:
    """Writes monotonic, throttled progress snapshots for Rails to poll."""

    def __init__(self, path: Path | str) -> None:
        self._path = Path(path)
        self._last_percent = -1
        self._last_write_monotonic = 0.0

    def report(
        self,
        phase_id: str,
        percent: int,
        *,
        pieces_total: int | None = None,
        pieces_placed: int | None = None,
        message_key: str | None = None,
        eta_sec: int | None = None,
    ) -> None:
        """[REQ-FIT-JOB-001] Record phase progress; skip invalid phase or throttled updates."""
        assert phase_id, "phase_id is required"
        if phase_id not in VALID_PHASE_IDS:
            return

        bounded = _validated_percent(percent)
        effective = max(bounded, self._last_percent)
        if not _should_write(self._last_write_monotonic, self._last_percent, effective):
            return

        payload = _build_payload(
            phase_id=phase_id,
            percent=effective,
            pieces_total=pieces_total,
            pieces_placed=pieces_placed,
            message_key=message_key,
            eta_sec=eta_sec,
        )
        _atomic_write_json(self._path, payload)
        self._last_percent = effective
        self._last_write_monotonic = time.monotonic()


def _validated_percent(percent: int) -> int:
    assert isinstance(percent, int), "percent must be int"
    if percent < 0 or percent > 100:
        raise ValueError(f"percent must be 0..100, got {percent}")
    return percent


def _should_write(last_write_monotonic: float, last_percent: int, percent: int) -> bool:
    if last_percent < 0:
        return True
    elapsed = time.monotonic() - last_write_monotonic
    if elapsed >= _THROTTLE_SECONDS:
        return True
    if abs(percent - last_percent) >= _THROTTLE_PERCENT_DELTA:
        return True
    return False


def _build_payload(
    *,
    phase_id: str,
    percent: int,
    pieces_total: int | None,
    pieces_placed: int | None,
    message_key: str | None,
    eta_sec: int | None = None,
) -> dict[str, Any]:
    assert 0 <= percent <= 100
    payload: dict[str, Any] = {
        "version": PROGRESS_SCHEMA_VERSION,
        "phase_id": phase_id,
        "percent": percent,
        "message_key": message_key,
    }
    if pieces_total is not None:
        payload["pieces_total"] = pieces_total
    if pieces_placed is not None:
        payload["pieces_placed"] = pieces_placed
    if eta_sec is not None:
        payload["eta_sec"] = int(eta_sec)
    return payload


def _atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    assert path.suffix == ".json", "progress path must end with .json"
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_name(f"{path.name}.tmp")
    tmp_path.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
    tmp_path.replace(path)
    assert path.is_file(), "progress.json must exist after atomic rename"
