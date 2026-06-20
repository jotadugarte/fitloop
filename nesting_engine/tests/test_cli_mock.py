# [REQ-FIT-CLI-001] Mock CLI writes stepped progress.json for Rails bridge tests.
from __future__ import annotations

import json
from pathlib import Path

import pytest

from nesting_engine.cli_mock import run
from nesting_engine.progress_reporter import ProgressReporter

_EXPECTED_PHASES = (
    "extracting",
    "fill",
    "optimizing",
    "consolidating",
    "refining",
    "writing_outputs",
)


@pytest.fixture
def capture_cli_mock_progress(monkeypatch: pytest.MonkeyPatch) -> list[str]:
    captured: list[str] = []
    original = ProgressReporter.report

    def tracking_report(
        self: ProgressReporter,
        phase_id: str,
        percent: int,
        **kwargs: object,
    ) -> None:
        captured.append(phase_id)
        original(self, phase_id, percent, **kwargs)

    monkeypatch.setattr(ProgressReporter, "report", tracking_report)
    return captured


def test_cli_mock_writes_outputs_and_stepped_progress(
    tmp_path: Path,
    capture_cli_mock_progress: list[str],
) -> None:
    output_dir = tmp_path / "work" / "output"
    config_path = tmp_path / "work" / "config.json"
    config_path.parent.mkdir(parents=True)
    config_path.write_text(
        json.dumps({"project_id": "mock-1", "output_dir": str(output_dir)}),
        encoding="utf-8",
    )

    assert run(config_path) == 0

    assert (output_dir / "nested.dxf").is_file()
    assert (output_dir / "placements.json").is_file()
    assert (output_dir / "report.json").is_file()

    progress_path = output_dir / "progress.json"
    assert progress_path.is_file()
    final = json.loads(progress_path.read_text(encoding="utf-8"))
    assert final["version"] == 2
    assert final["phase_id"] == "writing_outputs"
    assert final["percent"] >= 95

    seen = [phase for phase in capture_cli_mock_progress if phase in _EXPECTED_PHASES]
    assert seen[0] == "extracting"
    assert seen[-1] == "writing_outputs"
    order = [_EXPECTED_PHASES.index(phase) for phase in seen]
    assert order == sorted(order)
