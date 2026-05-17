# [REQ-FIT-NEST-002] Multi-bin nest, sheet gap offsets, outputs, orphans.
from __future__ import annotations

import json
from pathlib import Path

import ezdxf
from shapely.geometry import box

from nesting_engine.nest import _piece_placement_dict, run_from_config
from nesting_engine.nest_bin import SheetStockSpec, nest_multi_bin

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "sample_piece.dxf"


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
    assert placement["x_mm"] <= margin + 50.0
    assert placement["y_mm"] <= margin + 50.0


def test_large_margin_prevents_placement() -> None:
    piece = box(0, 0, 40, 40)
    stocks = [SheetStockSpec(width_mm=50, height_mm=50, quantity=1, sort_order=0)]

    fits = nest_multi_bin([piece], stocks, margin_mm=0.0, kerf_mm=0.0, sheet_gap_mm=0.0)
    tight = nest_multi_bin([piece], stocks, margin_mm=8.0, kerf_mm=0.0, sheet_gap_mm=0.0)

    assert fits.orphans == []
    assert len(tight.orphans) == 1


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
