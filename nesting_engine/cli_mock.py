"""Mock nesting CLI for Rails bridge tests (REQ-FIT-CLI-001)."""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

from nesting_engine.progress_reporter import ProgressReporter

# [REQ-FIT-JOB-001] Stepped phases so CliRunner poll tests observe live progress.
_PROGRESS_STEPS: tuple[tuple[str, int], ...] = (
    ("extracting", 10),
    ("fill", 25),
    ("fill", 45),
    ("optimizing", 60),
    ("consolidating", 75),
    ("refining", 85),
    ("writing_outputs", 96),
    ("writing_outputs", 99),
)
_PROGRESS_STEP_SLEEP_SEC = 0.05


def run(config_path: Path) -> int:
    config = json.loads(config_path.read_text(encoding="utf-8"))
    output_dir = Path(config["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)

    reporter = ProgressReporter(output_dir / "progress.json")
    pieces_total = 3
    for phase_id, percent in _PROGRESS_STEPS:
        pieces_placed = min(pieces_total, max(0, int(pieces_total * percent / 100)))
        reporter.report(
            phase_id,
            percent,
            pieces_total=pieces_total,
            pieces_placed=pieces_placed,
        )
        time.sleep(_PROGRESS_STEP_SLEEP_SEC)

    (output_dir / "nested.dxf").write_text("FITLOOP MOCK NESTED DXF\n", encoding="utf-8")
    (output_dir / "placements.json").write_text(
        json.dumps({"sheets": [], "project_id": config.get("project_id")}),
        encoding="utf-8",
    )
    (output_dir / "report.json").write_text(
        json.dumps({"status": "completed", "orphans": [], "warnings": []}),
        encoding="utf-8",
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    if len(argv) != 1:
        print("usage: cli_mock.py CONFIG_JSON_PATH", file=sys.stderr)
        return 1
    return run(Path(argv[0]))


if __name__ == "__main__":
    raise SystemExit(main())
