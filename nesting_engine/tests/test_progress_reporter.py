# [REQ-FIT-JOB-001] CLI progress.json reporter: atomic writes, throttle, monotonic percent.
from __future__ import annotations

import json
import time
from pathlib import Path

import pytest

from nesting_engine.progress_reporter import (
    PROGRESS_SCHEMA_VERSION,
    VALID_PHASE_IDS,
    ProgressReporter,
)


def _read_progress(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def test_report_writes_schema_v1_json(tmp_path: Path) -> None:
    path = tmp_path / "progress.json"
    reporter = ProgressReporter(path)

    reporter.report("extracting", 8, pieces_total=10)

    assert path.is_file()
    data = _read_progress(path)
    assert data["version"] == PROGRESS_SCHEMA_VERSION
    assert data["phase_id"] == "extracting"
    assert data["percent"] == 8
    assert data["pieces_total"] == 10
    assert data.get("pieces_placed") is None
    assert data.get("message_key") is None


def test_atomic_write_uses_rename_not_partial_visible_file(tmp_path: Path) -> None:
    path = tmp_path / "output" / "progress.json"
    reporter = ProgressReporter(path)

    reporter.report("fill", 20)

    assert path.is_file()
    assert not path.with_suffix(".json.tmp").exists()
    assert list(path.parent.glob("*.tmp")) == []


def test_report_rejects_percent_below_zero(tmp_path: Path) -> None:
    path = tmp_path / "progress.json"
    reporter = ProgressReporter(path)

    with pytest.raises(ValueError, match="percent"):
        reporter.report("fill", -1)


def test_report_rejects_percent_above_hundred(tmp_path: Path) -> None:
    path = tmp_path / "progress.json"
    reporter = ProgressReporter(path)

    with pytest.raises(ValueError, match="percent"):
        reporter.report("fill", 101)


def test_percent_is_monotonic_non_decreasing(tmp_path: Path) -> None:
    path = tmp_path / "progress.json"
    reporter = ProgressReporter(path)

    reporter.report("fill", 30)
    reporter.report("fill", 25)

    assert _read_progress(path)["percent"] == 30


def test_invalid_phase_id_is_ignored(tmp_path: Path) -> None:
    path = tmp_path / "progress.json"
    reporter = ProgressReporter(path)

    reporter.report("not_a_real_phase", 10)

    assert not path.exists()


def test_throttle_skips_writes_within_one_second_for_small_delta(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    path = tmp_path / "progress.json"
    now = {"t": 1000.0}

    def fake_monotonic() -> float:
        return now["t"]

    monkeypatch.setattr(time, "monotonic", fake_monotonic)
    reporter = ProgressReporter(path)

    reporter.report("fill", 10)
    mtime_first = path.stat().st_mtime_ns
    now["t"] = 1000.5
    reporter.report("fill", 10)
    assert path.stat().st_mtime_ns == mtime_first


def test_throttle_allows_write_when_percent_delta_at_least_one(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    path = tmp_path / "progress.json"
    now = {"t": 2000.0}

    monkeypatch.setattr(time, "monotonic", lambda: now["t"])
    reporter = ProgressReporter(path)

    reporter.report("fill", 10)
    now["t"] = 2000.2
    reporter.report("fill", 11)

    assert _read_progress(path)["percent"] == 11


def test_throttle_allows_write_after_one_second_elapsed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    path = tmp_path / "progress.json"
    now = {"t": 3000.0}

    monkeypatch.setattr(time, "monotonic", lambda: now["t"])
    reporter = ProgressReporter(path)

    reporter.report("optimizing", 60)
    now["t"] = 3001.0
    reporter.report("optimizing", 61)

    assert _read_progress(path)["percent"] == 61


def test_valid_phase_ids_cover_pipeline_phases() -> None:
    expected = {
        "extracting",
        "fill",
        "optimizing",
        "consolidating",
        "refining",
        "writing_outputs",
    }
    assert expected <= VALID_PHASE_IDS


# [REQ-FIT-JOB-001] Step 1: eta_sec field in progress.json (schema v2)


def test_schema_version_is_2() -> None:
    # Fails until PROGRESS_SCHEMA_VERSION is bumped to 2.
    assert PROGRESS_SCHEMA_VERSION == 2


def test_report_without_eta_sec_omits_field(tmp_path: Path) -> None:
    # eta_sec must be absent from the JSON when not provided (backward compat).
    path = tmp_path / "progress.json"
    reporter = ProgressReporter(path)
    reporter.report("optimizing", 30)
    data = _read_progress(path)
    assert "eta_sec" not in data


def test_report_with_eta_sec_none_omits_field(tmp_path: Path) -> None:
    # Explicit None must also produce no eta_sec key.
    path = tmp_path / "progress.json"
    reporter = ProgressReporter(path)
    reporter.report("optimizing", 30, eta_sec=None)
    data = _read_progress(path)
    assert "eta_sec" not in data


def test_report_with_eta_sec_integer_includes_field(tmp_path: Path) -> None:
    # Positive integer ETA must appear in the JSON payload.
    path = tmp_path / "progress.json"
    reporter = ProgressReporter(path)
    reporter.report("optimizing", 45, eta_sec=120)
    data = _read_progress(path)
    assert data["eta_sec"] == 120
    assert isinstance(data["eta_sec"], int)


def test_report_with_eta_sec_zero_includes_field(tmp_path: Path) -> None:
    # Zero ETA (just finished) must also be included.
    path = tmp_path / "progress.json"
    reporter = ProgressReporter(path)
    reporter.report("optimizing", 99, eta_sec=0)
    data = _read_progress(path)
    assert data["eta_sec"] == 0
