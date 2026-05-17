"""Mock nesting CLI for Rails bridge tests (REQ-FIT-CLI-001)."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def run(config_path: Path) -> int:
    config = json.loads(config_path.read_text(encoding="utf-8"))
    output_dir = Path(config["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)

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
