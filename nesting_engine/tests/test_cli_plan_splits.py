# [REQ-FIT-CLI-001] [REQ-FIT-SPLIT-001] CLI plan_splits mode writes split_preview.json.
from __future__ import annotations

import json
from pathlib import Path

import ezdxf
import pytest

from nesting_engine.nest import run_from_config


def _write_oversized_dxf(path: Path) -> None:
    doc = ezdxf.new("R2010")
    msp = doc.modelspace()
    msp.add_lwpolyline(
        [(0, 0), (500, 0), (500, 500), (0, 500)],
        close=True,
        dxfattribs={"layer": "PIECES"},
    )
    doc.saveas(path)


def test_plan_splits_writes_split_preview_json(tmp_path: Path) -> None:
    """[REQ-FIT-CLI-001] [REQ-FIT-SPLIT-001] plan_splits mode emits preview cuts and child outlines."""
    dxf_path = tmp_path / "oversized.dxf"
    _write_oversized_dxf(dxf_path)
    output_dir = tmp_path / "output"
    config = {
        "mode": "plan_splits",
        "project_id": "split-plan-1",
        "input_dxf_paths": [str(dxf_path)],
        "included_layers": ["PIECES"],
        "piece_keys": ["0"],
        "sheet_stocks": [
            {"width_mm": 100.0, "height_mm": 100.0, "quantity": 1, "sort_order": 0}
        ],
        "kerf_mm": 0.0,
        "margin_mm": 0.0,
        "curve_tolerance_mm": 0.25,
        "sheet_gap_mm": 15.0,
        "time_limit_sec": 600,
        "output_dir": str(output_dir),
    }

    run_from_config(config)

    preview_path = output_dir / "split_preview.json"
    assert preview_path.is_file(), "expected split_preview.json for plan_splits mode"
    assert not (output_dir / "nested.dxf").exists(), "plan_splits must not write nested.dxf"

    preview = json.loads(preview_path.read_text(encoding="utf-8"))
    assert set(preview.keys()) >= {"proposals", "warnings"}
    assert isinstance(preview["warnings"], list)
    assert len(preview["proposals"]) == 1

    proposal = preview["proposals"][0]
    assert proposal["piece_key"] == "0"
    assert proposal["feasible"] is True
    assert proposal["reason"] is None
    assert len(proposal["children"]) >= 2
    assert len(proposal["cut_segments"]) >= 1

    child = proposal["children"][0]
    assert set(child.keys()) >= {"label", "rings"}
    assert child["label"] in {"a", "b", "c"}
    assert isinstance(child["rings"], list) and child["rings"]


def test_plan_splits_reports_split_not_feasible(tmp_path: Path) -> None:
    """[REQ-FIT-SPLIT-001] Empty usable bin surfaces split_not_feasible in preview."""
    dxf_path = tmp_path / "oversized.dxf"
    _write_oversized_dxf(dxf_path)
    output_dir = tmp_path / "output"
    config = {
        "mode": "plan_splits",
        "project_id": "split-plan-2",
        "input_dxf_paths": [str(dxf_path)],
        "included_layers": ["PIECES"],
        "piece_keys": ["0"],
        "sheet_stocks": [
            {"width_mm": 20.0, "height_mm": 20.0, "quantity": 1, "sort_order": 0}
        ],
        "kerf_mm": 0.0,
        "margin_mm": 10.0,
        "curve_tolerance_mm": 0.25,
        "sheet_gap_mm": 15.0,
        "time_limit_sec": 600,
        "output_dir": str(output_dir),
    }

    run_from_config(config)

    preview = json.loads((output_dir / "split_preview.json").read_text(encoding="utf-8"))
    proposal = preview["proposals"][0]
    assert proposal["feasible"] is False
    assert proposal["reason"] == "split_not_feasible"
    assert proposal["children"] == []
