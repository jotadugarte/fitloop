# [REQ-FIT-NEST-002] Multi-bin nest, sheet gap offsets, outputs, orphans.
from __future__ import annotations

import json
from pathlib import Path

import ezdxf
import pytest
from shapely.geometry import Polygon, box

from nesting_engine.nest import _piece_placement_dict, run_from_config
from nesting_engine.nest_bin import SheetStockSpec, nest_multi_bin

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "sample_piece.dxf"


def test_mixed_sizes_use_one_sheet_when_rect_and_circle_fit_beside_large_pieces() -> None:
    from shapely.geometry import Polygon
    import math

    def circle(radius: float, count: int = 48) -> Polygon:
        return Polygon(
            [
                (radius * math.cos(2 * math.pi * i / count), radius * math.sin(2 * math.pi * i / count))
                for i in range(count)
            ]
        )

    washer = Polygon(circle(400).exterior.coords, [list(circle(150).exterior.coords)])
    hexagon = Polygon(
        [
            (120 * math.cos(math.pi / 3 * i), 120 * math.sin(math.pi / 3 * i))
            for i in range(6)
        ]
    )
    pieces = [washer, hexagon, circle(60), box(0, 0, 150, 40), box(0, 0, 1200, 80)]
    stocks = [SheetStockSpec(width_mm=1500.0, height_mm=1000.0, quantity=None, sort_order=0)]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=5.0,
        kerf_mm=0.0,
        sheet_gap_mm=15.0,
    )

    assert result.orphans == []
    assert len(result.sheets) <= 2
    assert len(result.sheets[0].pieces) >= 4


def test_multiple_pieces_pack_on_one_sheet() -> None:
    pieces = [box(0, 0, 10, 10) for _ in range(3)]
    stocks = [SheetStockSpec(width_mm=50, height_mm=50, quantity=None, sort_order=0)]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=0.0,
        kerf_mm=0.0,
        sheet_gap_mm=10.0,
    )

    assert len(result.sheets) == 1
    assert len(result.sheets[0].pieces) == 3
    assert result.orphans == []


def test_margin_applies_at_sheet_edge_not_between_pieces() -> None:  # [REQ-FIT-NEST-002]
    from nesting_engine.nest_placement import placed_polygon

    pieces = [box(0, 0, 10, 10), box(0, 0, 10, 10)]
    stocks = [SheetStockSpec(width_mm=50, height_mm=50, quantity=1, sort_order=0)]
    margin = 5.0

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=margin,
        kerf_mm=0.0,
        sheet_gap_mm=0.0,
    )

    assert result.orphans == []
    placed = sorted(
        result.sheets[0].pieces,
        key=lambda row: row.placement.x + row.placement.y,
    )
    first = placed_polygon(pieces[placed[0].piece_index], placed[0].placement)
    second = placed_polygon(pieces[placed[1].piece_index], placed[1].placement)

    assert first.bounds[0] == pytest.approx(margin, abs=0.05)
    assert first.bounds[1] == pytest.approx(margin, abs=0.05)
    assert second.bounds[0] >= margin + 10.0 - 0.05
    assert first.distance(second) >= 0.0
    for poly in (first, second):
        assert poly.bounds[0] >= margin - 0.05
        assert poly.bounds[1] >= margin - 0.05
        assert poly.bounds[2] <= 50.0 - margin + 0.05
        assert poly.bounds[3] <= 50.0 - margin + 0.05


def test_kerf_keeps_minimum_gap_between_pieces() -> None:  # [REQ-FIT-NEST-002]
    from nesting_engine.nest_placement import placed_polygon

    kerf = 4.0
    pieces = [box(0, 0, 10, 10), box(0, 0, 10, 10)]
    stocks = [SheetStockSpec(width_mm=50, height_mm=50, quantity=1, sort_order=0)]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=0.0,
        kerf_mm=kerf,
        sheet_gap_mm=0.0,
    )

    assert result.orphans == []
    polys = [
        placed_polygon(pieces[row.piece_index], row.placement)
        for row in result.sheets[0].pieces
    ]
    gap = polys[0].distance(polys[1])
    assert gap >= kerf - 0.2
    assert not polys[0].intersects(polys[1])


def test_unlimited_stock_opens_extra_sheets_when_full() -> None:
    pieces = [box(0, 0, 15, 15) for _ in range(3)]
    stocks = [SheetStockSpec(width_mm=20, height_mm=20, quantity=None, sort_order=0)]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=0.0,
        kerf_mm=0.0,
        sheet_gap_mm=10.0,
    )

    assert len(result.sheets) == 3
    assert result.orphans == []
    assert result.sheets[1].offset_x_mm == 30.0
    assert result.sheets[2].offset_x_mm == 60.0


def test_finite_stock_then_next_sort_order() -> None:
    pieces = [box(0, 0, 30, 30)]
    stocks = [
        SheetStockSpec(width_mm=20, height_mm=20, quantity=1, sort_order=0),
        SheetStockSpec(width_mm=200, height_mm=200, quantity=1, sort_order=1),
    ]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=0.0,
        kerf_mm=0.0,
        sheet_gap_mm=15.0,
    )

    assert len(result.sheets) == 1
    assert result.sheets[0].stock_sort_order == 1
    assert result.orphans == []


def test_oversized_piece_becomes_orphan() -> None:
    pieces = [box(0, 0, 500, 500)]
    stocks = [SheetStockSpec(width_mm=100, height_mm=100, quantity=None, sort_order=0)]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=0.0,
        kerf_mm=0.0,
        sheet_gap_mm=15.0,
    )

    assert result.sheets == []
    assert len(result.orphans) == 1
    assert result.orphans[0].reason == "oversized_for_sheet"


def test_placements_json_uses_sheet_local_bounds() -> None:
    piece = box(5000.0, 3000.0, 5040.0, 3030.0)
    stocks = [SheetStockSpec(width_mm=500.0, height_mm=400.0, quantity=1, sort_order=0)]
    margin = 5.0

    result = nest_multi_bin(
        [piece],
        stocks,
        margin_mm=margin,
        kerf_mm=0.0,
        sheet_gap_mm=15.0,
    )

    placed = result.sheets[0].pieces[0]
    placement = _piece_placement_dict(placed)

    assert placement["x_mm"] >= margin - 0.01
    assert placement["y_mm"] >= margin - 0.01
    assert len(placement["rings"]) >= 1
    assert placement["x_mm"] + placement["width_mm"] <= 500.0 - margin + 0.01
    assert placement["y_mm"] + placement["height_mm"] <= 400.0 - margin + 0.01


def test_large_margin_prevents_placement() -> None:
    piece = box(0, 0, 40, 40)
    stocks = [SheetStockSpec(width_mm=50, height_mm=50, quantity=1, sort_order=0)]

    fits = nest_multi_bin([piece], stocks, margin_mm=0.0, kerf_mm=0.0, sheet_gap_mm=0.0)
    tight = nest_multi_bin([piece], stocks, margin_mm=8.0, kerf_mm=0.0, sheet_gap_mm=0.0)

    assert fits.orphans == []
    assert len(tight.orphans) == 1


def test_placement_dict_includes_hole_rings_for_washer() -> None:
    outer = box(0, 0, 100, 100)
    inner = box(30, 30, 70, 70)
    washer = Polygon(outer.exterior.coords, [list(inner.exterior.coords)])
    stocks = [SheetStockSpec(width_mm=200.0, height_mm=200.0, quantity=1, sort_order=0)]

    result = nest_multi_bin([washer], stocks, margin_mm=0.0, kerf_mm=0.0, sheet_gap_mm=0.0)
    placement = _piece_placement_dict(result.sheets[0].pieces[0])

    assert len(placement["rings"]) == 2


def test_placements_json_includes_orphan_geometry(tmp_path: Path) -> None:
    import ezdxf

    dxf_path = tmp_path / "oversized.dxf"
    doc = ezdxf.new("R2010")
    msp = doc.modelspace()
    msp.add_lwpolyline([(0, 0), (500, 0), (500, 500), (0, 500)], close=True, dxfattribs={"layer": "PIECES"})
    doc.saveas(dxf_path)

    output_dir = tmp_path / "output"
    config = {
        "project_id": "1",
        "input_dxf_paths": [str(dxf_path)],
        "included_layers": ["PIECES"],
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

    placements = json.loads((output_dir / "placements.json").read_text(encoding="utf-8"))
    assert len(placements["orphans"]) == 1
    orphan = placements["orphans"][0]
    assert orphan["reason"] == "oversized_for_sheet"
    assert orphan["rings"]
    assert orphan["width_mm"] == pytest.approx(500.0, rel=0.01)


def test_run_from_config_writes_outputs(tmp_path: Path) -> None:
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

    assert (output_dir / "nested.dxf").is_file()
    report = json.loads((output_dir / "report.json").read_text(encoding="utf-8"))
    placements = json.loads((output_dir / "placements.json").read_text(encoding="utf-8"))

    assert report["status"] == "completed"
    assert len(placements["sheets"]) >= 1
    assert placements["sheets"][0]["offset_x_mm"] == 0.0

    doc = ezdxf.readfile(output_dir / "nested.dxf")
    layers = {layer.dxf.name for layer in doc.layers}
    assert "SHEETS" in layers
    assert "PIECES" in layers


def test_run_from_config_cli_json_contract_keys(tmp_path: Path) -> None:
    # [REQ-FIT-NEST-002] Contract regression: stable JSON keys; invariants only (no golden x/y).
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

    report = json.loads((output_dir / "report.json").read_text(encoding="utf-8"))
    placements = json.loads((output_dir / "placements.json").read_text(encoding="utf-8"))

    assert set(report.keys()) >= {"status", "orphans", "warnings"}
    assert report["status"] in {"completed", "partial", "failed"}
    assert isinstance(report["orphans"], list)
    assert isinstance(report["warnings"], list)

    assert set(placements.keys()) == {"sheets", "orphans"}
    assert isinstance(placements["sheets"], list)
    assert isinstance(placements["orphans"], list)

    sheet = placements["sheets"][0]
    assert set(sheet.keys()) >= {
        "stock_sort_order",
        "sheet_index",
        "width_mm",
        "height_mm",
        "offset_x_mm",
        "pieces",
    }
    assert sheet["pieces"], "expected at least one placed piece in contract fixture"
    piece = sheet["pieces"][0]
    assert set(piece.keys()) >= {
        "piece_index",
        "x_mm",
        "y_mm",
        "rotation_deg",
        "width_mm",
        "height_mm",
        "rings",
    }
    assert isinstance(piece["rings"], list) and piece["rings"]
    assert piece["width_mm"] > 0.0
    assert piece["height_mm"] > 0.0
    assert 0.0 <= piece["rotation_deg"] < 360.0


def test_nest_with_derived_pieces_emits_split_metadata_without_dxf_annotations(tmp_path: Path) -> None:
    """[REQ-FIT-SPLIT-001] Derived children nest; report/placements note split; nested.dxf stays clean."""
    output_dir = tmp_path / "output"
    config = {
        "project_id": "split-derived",
        "input_dxf_paths": [],
        "included_layers": [],
        "derived_pieces": [
            {
                "parent_piece_key": "0",
                "label": "Pieza-1a",
                "sort_order": 0,
                "rings": [
                    [
                        [0.0, 0.0],
                        [60.0, 0.0],
                        [60.0, 40.0],
                        [0.0, 40.0],
                    ]
                ],
            },
            {
                "parent_piece_key": "0",
                "label": "Pieza-1b",
                "sort_order": 1,
                "rings": [
                    [
                        [0.0, 0.0],
                        [60.0, 0.0],
                        [60.0, 40.0],
                        [0.0, 40.0],
                    ]
                ],
            },
        ],
        "split_cut_segments": [
            [[30.0, 0.0], [30.0, 40.0]],
        ],
        "sheet_stocks": [
            {"width_mm": 300.0, "height_mm": 300.0, "quantity": 1, "sort_order": 0}
        ],
        "kerf_mm": 0.0,
        "margin_mm": 5.0,
        "curve_tolerance_mm": 0.1,
        "sheet_gap_mm": 15.0,
        "time_limit_sec": 600,
        "output_dir": str(output_dir),
    }

    run_from_config(config)

    report = json.loads((output_dir / "report.json").read_text(encoding="utf-8"))
    placements = json.loads((output_dir / "placements.json").read_text(encoding="utf-8"))

    assert report["status"] == "completed"
    assert report["split"]["derived_labels"] == ["Pieza-1a", "Pieza-1b"]
    assert report["split"]["cut_segment_count"] == 1

    placed_labels = {
        piece["label"]
        for sheet in placements["sheets"]
        for piece in sheet["pieces"]
        if "label" in piece
    }
    assert placed_labels == {"Pieza-1a", "Pieza-1b"}

    doc = ezdxf.readfile(output_dir / "nested.dxf")
    layers = {layer.dxf.name for layer in doc.layers}
    assert "SPLIT_CUTS" not in layers
    assert "SPLIT_LABELS" not in layers

    msp = doc.modelspace()
    assert not [entity for entity in msp if entity.dxf.layer in {"SPLIT_CUTS", "SPLIT_LABELS"}]
    piece_polys = [entity for entity in msp if entity.dxf.layer == "PIECES"]
    assert piece_polys, "expected nested piece contours in nested.dxf"
