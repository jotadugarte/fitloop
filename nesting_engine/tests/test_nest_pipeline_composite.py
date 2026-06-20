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

    placed = placements["sheets"][0]["pieces"][0]
    assert placed["primary_layer_name"] == CORTE
    assert placed["decorations"]
    assert {row["layer_name"] for row in placed["decorations"]} == {GRABADO}


def test_run_from_config_composite_partial_serializes_orphan_bounds(tmp_path: Path) -> None:
    """[REQ-FIT-DXF-002] Orphan placements use CompositePiece.polygon, not the dataclass itself."""
    dxf_path = tmp_path / "composite-nest.dxf"
    output_dir = tmp_path / "output"
    _write_composite_nest_fixture(dxf_path)

    run_from_config(
        {
            "project_id": "composite-partial",
            "curve_tolerance_mm": 0.25,
            "input_files": [
                {
                    "path": str(dxf_path),
                    "primary_layer": CORTE,
                    "auxiliary_layers": [GRABADO],
                }
            ],
            "sheet_stocks": [
                {"width_mm": 50.0, "height_mm": 50.0, "quantity": 1, "sort_order": 0}
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

    assert report["status"] == "partial"
    assert placements["orphans"]
    for orphan in placements["orphans"]:
        assert orphan["rings"]
        assert orphan["width_mm"] > 0
        assert orphan["height_mm"] > 0
        assert orphan["reason"]


def _write_oversized_mother_dxf(path: Path) -> None:
    doc = ezdxf.new("R2010")
    msp = doc.modelspace()
    msp.add_lwpolyline(
        [(0, 0), (200, 0), (200, 80), (0, 80)],
        close=True,
        dxfattribs={"layer": CORTE},
    )
    msp.add_line((10, 40), (190, 40), dxfattribs={"layer": GRABADO})
    doc.saveas(path)


def test_nest_with_derived_composite_children_preserves_auxiliary_layers(tmp_path: Path) -> None:
    """[REQ-FIT-NEST-002] [REQ-FIT-SPLIT-001] [REQ-FIT-DXF-002] Post-split derived children keep layer names."""
    dxf_path = tmp_path / "mother-oversized.dxf"
    output_dir = tmp_path / "output"
    _write_oversized_mother_dxf(dxf_path)

    run_from_config(
        {
            "project_id": "composite-derived",
            "curve_tolerance_mm": 0.25,
            "input_files": [
                {
                    "path": str(dxf_path),
                    "primary_layer": CORTE,
                    "auxiliary_layers": [GRABADO],
                }
            ],
            "excluded_piece_keys": ["0"],
            "derived_pieces": [
                {
                    "parent_piece_key": "0",
                    "label": "Pieza-1a",
                    "sort_order": 0,
                    "primary_layer_name": CORTE,
                    "rings": [
                        [
                            [0.0, 0.0],
                            [100.0, 0.0],
                            [100.0, 80.0],
                            [0.0, 80.0],
                        ]
                    ],
                    "decorations": [
                        {
                            "layer_name": GRABADO,
                            "geometry_type": "line",
                            "payload": {
                                "coordinates": [[10.0, 40.0], [90.0, 40.0]],
                            },
                        }
                    ],
                },
                {
                    "parent_piece_key": "0",
                    "label": "Pieza-1b",
                    "sort_order": 1,
                    "primary_layer_name": CORTE,
                    "rings": [
                        [
                            [100.0, 0.0],
                            [200.0, 0.0],
                            [200.0, 80.0],
                            [100.0, 80.0],
                        ]
                    ],
                    "decorations": [
                        {
                            "layer_name": GRABADO,
                            "geometry_type": "line",
                            "payload": {
                                "coordinates": [[110.0, 40.0], [190.0, 40.0]],
                            },
                        }
                    ],
                },
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

    placed_labels = {
        piece["label"]
        for piece in placements["sheets"][0]["pieces"]
        if "label" in piece
    }
    assert placed_labels == {"Pieza-1a", "Pieza-1b"}

    doc = ezdxf.readfile(output_dir / "nested.dxf")
    layer_names = {layer.dxf.name for layer in doc.layers}
    assert CORTE in layer_names
    assert GRABADO in layer_names
    assert "PIECES" not in layer_names

    modelspace = list(doc.modelspace())
    grabado_entities = [entity for entity in modelspace if entity.dxf.layer == GRABADO]
    corte_entities = [entity for entity in modelspace if entity.dxf.layer == CORTE]
    assert len(corte_entities) >= 2
    assert len(grabado_entities) >= 2


def test_run_from_config_nests_composite_pieces_thorough(tmp_path: Path) -> None:
    """[REQ-FIT-DXF-002] [REQ-FIT-NEST-002] E2E composite nest in thorough mode."""
    dxf_path = tmp_path / "composite-nest-thorough.dxf"
    output_dir = tmp_path / "output"
    _write_composite_nest_fixture(dxf_path)

    run_from_config(
        {
            "project_id": "composite-thorough",
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
            "optimization_mode": "thorough",
            "max_seeds": 12,
            "max_local_search_iterations": 8,
            "output_dir": str(output_dir),
        }
    )

    report = json.loads((output_dir / "report.json").read_text(encoding="utf-8"))
    placements = json.loads((output_dir / "placements.json").read_text(encoding="utf-8"))

    assert report["status"] == "completed"
    assert placements["orphans"] == []
    assert len(placements["sheets"]) == 1
    assert len(placements["sheets"][0]["pieces"]) == 2

