# [REQ-FIT-CLI-001] [REQ-FIT-SPLIT-001] [REQ-FIT-DXF-002] plan_splits preserves composite decorations.
from __future__ import annotations

import json
from pathlib import Path

import ezdxf
import pytest
from shapely.geometry import LineString

from nesting_engine.nest import run_from_config

CORTE = "CORTE"
GRABADO = "GRABADO"


def _write_oversized_composite_dxf(path: Path) -> None:
    doc = ezdxf.new("R2010")
    msp = doc.modelspace()
    msp.add_lwpolyline(
        [(0, 0), (200, 0), (200, 80), (0, 80)],
        close=True,
        dxfattribs={"layer": CORTE},
    )
    msp.add_line((10, 20), (190, 20), dxfattribs={"layer": GRABADO})
    doc.saveas(path)


def test_plan_splits_composite_emits_child_decorations(tmp_path: Path) -> None:
    dxf_path = tmp_path / "composite-oversized.dxf"
    _write_oversized_composite_dxf(dxf_path)
    output_dir = tmp_path / "output"
    config = {
        "mode": "plan_splits",
        "project_id": "split-composite-1",
        "input_files": [
            {
                "path": str(dxf_path),
                "primary_layer": CORTE,
                "auxiliary_layers": [GRABADO],
            }
        ],
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

    preview = json.loads((output_dir / "split_preview.json").read_text(encoding="utf-8"))
    proposal = preview["proposals"][0]
    assert proposal["feasible"] is True
    assert len(proposal["children"]) == 2

    for child in proposal["children"]:
        assert "decorations" in child
        assert len(child["decorations"]) == 1
        deco = child["decorations"][0]
        assert deco["layer_name"] == GRABADO
        assert deco["geometry_type"] == "line"
        assert len(deco["payload"]["coordinates"]) >= 2

    lengths = sorted(
        LineString(child["decorations"][0]["payload"]["coordinates"]).length
        for child in proposal["children"]
    )
    assert sum(lengths) == pytest.approx(180.0, abs=5.0)
    assert lengths[0] == pytest.approx(90.0, abs=5.0)
    assert lengths[1] == pytest.approx(90.0, abs=5.0)


def test_plan_splits_plan_pieces_can_supply_mother_decorations(tmp_path: Path) -> None:
    dxf_path = tmp_path / "composite-plan-piece.dxf"
    _write_oversized_composite_dxf(dxf_path)
    output_dir = tmp_path / "output"
    mother_rings = [[[0.0, 0.0], [200.0, 0.0], [200.0, 80.0], [0.0, 80.0]]]
    config = {
        "mode": "plan_splits",
        "project_id": "split-composite-2",
        "input_files": [
            {
                "path": str(dxf_path),
                "primary_layer": CORTE,
                "auxiliary_layers": [GRABADO],
            }
        ],
        "piece_keys": ["0"],
        "plan_pieces": [
            {
                "piece_key": "0",
                "rings": mother_rings,
                "primary_layer_name": CORTE,
                "decorations": [
                    {
                        "layer_name": GRABADO,
                        "geometry_type": "line",
                        "payload": {"coordinates": [[10.0, 20.0], [190.0, 20.0]]},
                    }
                ],
            }
        ],
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

    proposal = json.loads((output_dir / "split_preview.json").read_text(encoding="utf-8"))["proposals"][0]
    assert proposal["feasible"] is True
    assert all(child.get("decorations") for child in proposal["children"])
