# [REQ-FIT-SPLIT-001] plan_splits prefers plan_pieces rings over extract index.
from __future__ import annotations

import json
from pathlib import Path

import ezdxf

from nesting_engine.nest import run_from_config


def _write_two_squares_dxf(path: Path) -> None:
    doc = ezdxf.new("R2010")
    msp = doc.modelspace()
    msp.add_lwpolyline(
        [(0, 0), (80, 0), (80, 80), (0, 80)],
        close=True,
        dxfattribs={"layer": "PIECES"},
    )
    msp.add_lwpolyline(
        [(0, 0), (480, 0), (480, 480), (0, 480)],
        close=True,
        dxfattribs={"layer": "PIECES"},
    )
    doc.saveas(path)


def test_plan_splits_uses_plan_pieces_geometry_not_extract_index(tmp_path: Path) -> None:
    """[REQ-FIT-SPLIT-001] plan_pieces must target the orphan polygon, not pieces[index]."""
    dxf_path = tmp_path / "two.dxf"
    _write_two_squares_dxf(dxf_path)
    output_dir = tmp_path / "output"
    large_rings = [[[0.0, 0.0], [480.0, 0.0], [480.0, 480.0], [0.0, 480.0]]]
    config = {
        "mode": "plan_splits",
        "project_id": "plan-pieces-1",
        "input_dxf_paths": [str(dxf_path)],
        "included_layers": ["PIECES"],
        "piece_keys": ["0"],
        "plan_pieces": [{"piece_key": "0", "rings": large_rings}],
        "sheet_stocks": [
            {"width_mm": 200.0, "height_mm": 200.0, "quantity": 1, "sort_order": 0}
        ],
        "kerf_mm": 0.0,
        "margin_mm": 0.0,
        "curve_tolerance_mm": 0.25,
        "sheet_gap_mm": 15.0,
        "time_limit_sec": 600,
        "output_dir": str(output_dir),
    }

    run_from_config(config)

    preview = json.loads((output_dir / "split_preview.json").read_text(encoding="utf-8"))
    proposal = preview["proposals"][0]
    assert proposal["feasible"] is True
    child_points = [
        point
        for child in proposal["children"]
        for ring in child["rings"]
        for point in ring
    ]
    max_coord = max(max(abs(point[0]), abs(point[1])) for point in child_points)
    assert max_coord > 200.0, "expected split of the large plan_pieces polygon, not the small index-0 piece"
