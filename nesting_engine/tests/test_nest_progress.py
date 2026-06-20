# [REQ-FIT-JOB-001] [REQ-FIT-NEST-002] run_from_config writes phased progress.json.
from __future__ import annotations

import json
from pathlib import Path

import pytest

from nesting_engine.nest import run_from_config
from nesting_engine.progress_reporter import ProgressReporter

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "sample_piece.dxf"

_PHASE_ORDER = (
    "extracting",
    "fill",
    "optimizing",
    "consolidating",
    "refining",
    "writing_outputs",
)


@pytest.fixture
def capture_progress_reports(monkeypatch: pytest.MonkeyPatch) -> list[tuple[str, int]]:
    captured: list[tuple[str, int]] = []
    original = ProgressReporter.report

    def tracking_report(
        self: ProgressReporter,
        phase_id: str,
        percent: int,
        **kwargs: object,
    ) -> None:
        captured.append((phase_id, percent))
        original(self, phase_id, percent, **kwargs)

    monkeypatch.setattr(ProgressReporter, "report", tracking_report)
    return captured


def test_run_from_config_emits_phased_progress_json(
    tmp_path: Path,
    capture_progress_reports: list[tuple[str, int]],
) -> None:
    output_dir = tmp_path / "output"
    config = {
        "project_id": "99",
        "input_dxf_paths": [str(FIXTURE)],
        "included_layers": ["PIECES"],
        "sheet_stocks": [
            {"width_mm": 1000.0, "height_mm": 2000.0, "quantity": 1, "sort_order": 0}
        ],
        "kerf_mm": 0.0,
        "margin_mm": 5.0,
        "curve_tolerance_mm": 0.1,
        "sheet_gap_mm": 15.0,
        "time_limit_sec": 600,
        "output_dir": str(output_dir),
    }

    run_from_config(config)

    progress_path = output_dir / "progress.json"
    assert progress_path.is_file()
    final = json.loads(progress_path.read_text(encoding="utf-8"))
    assert final["version"] == 2
    assert final["phase_id"] == "writing_outputs"
    assert final["percent"] >= 95

    phase_ids = [phase for phase, _ in capture_progress_reports if phase in _PHASE_ORDER]
    assert phase_ids, "expected progress reports during nest run"
    assert phase_ids[0] == "extracting"
    assert "writing_outputs" in phase_ids
    order_indices = [_PHASE_ORDER.index(phase) for phase in phase_ids]
    assert order_indices == sorted(order_indices)
    assert max(order_indices) >= _PHASE_ORDER.index("refining")
