# [REQ-FIT-DXF-002] [REQ-FIT-NEST-002] End-to-end composite nest preserves layer names.
from __future__ import annotations

import json
from pathlib import Path

import ezdxf
import pytest
from shapely.geometry import Polygon

from nesting_engine.nest import run_from_config

CORTE = "CORTE"
GRABADO = "GRABADO"


def _write_composite_nest_fixture(path: Path) -> None:
    doc = ezdxf.new("R2010")
    msp = doc.modelspace()
    msp.add_lwpolyline(
        [(0, 0), (40, 0), (40, 40), (0, 40)],
        close=True,
        dxfattribs={"layer": CORTE},
    )
    msp.add_lwpolyline(
        [(60, 0), (100, 0), (100, 40), (60, 40)],
        close=True,
        dxfattribs={"layer": CORTE},
    )
    msp.add_line((35, 20), (65, 20), dxfattribs={"layer": GRABADO})
    msp.add_text("MARK", dxfattribs={"layer": GRABADO, "insert": (20, 20)})
    doc.saveas(path)


def test_run_from_config_nests_composite_pieces_with_original_layers(tmp_path: Path) -> None:
    dxf_path = tmp_path / "composite-nest.dxf"
    output_dir = tmp_path / "output"
    _write_composite_nest_fixture(dxf_path)

    run_from_config(
        {
            "project_id": "composite",
            "curve_tolerance_mm": 0.25,
            "input_files": [
                {
                    "path": str(dxf_path),
                    "primary_layer": CORTE,
                    "auxiliary_layers": [GRABADO],
                }
            ],
            "sheet_stocks": [
                {"width_mm": 250.0, "height_mm": 120.0, "quantity": 1, "sort_order": 0}
            ],
            "kerf_mm": 2.0,
            "margin_mm": 5.0,
            "sheet_gap_mm": 15.0,
            "time_limit_sec": 60,
            "output_dir": str(output_dir),
        }
    )

    report = json.loads((output_dir / "report.json").read_text(encoding="utf-8"))
    placements = json.loads((output_dir / "placements.json").read_text(encoding="utf-8"))

    assert report["status"] == "completed"
    assert placements["orphans"] == []
    assert len(placements["sheets"]) == 1
    assert len(placements["sheets"][0]["pieces"]) == 2

    doc = ezdxf.readfile(output_dir / "nested.dxf")
    layer_names = {layer.dxf.name for layer in doc.layers}
    assert "SHEETS" in layer_names
    assert CORTE in layer_names
    assert GRABADO in layer_names

    modelspace = list(doc.modelspace())
    assert any(entity.dxf.layer == "SHEETS" for entity in modelspace)
    assert any(entity.dxf.layer == CORTE for entity in modelspace)
    assert any(entity.dxf.layer == GRABADO for entity in modelspace)
    assert not any(entity.dxf.layer == "PIECES" for entity in modelspace)

    placed_polys = []
    for placed_row in placements["sheets"][0]["pieces"]:
        poly = Polygon(placed_row["rings"][0], placed_row["rings"][1:])
        placed_polys.append(poly)

    sheet = placements["sheets"][0]
    margin = 5.0
    for poly in placed_polys:
        assert poly.bounds[0] >= sheet["offset_x_mm"] + margin - 0.5
        assert poly.bounds[1] >= margin - 0.5
        assert poly.bounds[2] <= sheet["offset_x_mm"] + sheet["width_mm"] - margin + 0.5
        assert poly.bounds[3] <= sheet["height_mm"] - margin + 0.5

    grabado_entities = [entity for entity in modelspace if entity.dxf.layer == GRABADO]
    assert len(grabado_entities) >= 3
