# [REQ-FIT-NEST-001] Production capabilities; [REQ-FIT-NEST-002] nest_sheet + nest_multi_bin.
from __future__ import annotations

import pytest
from shapely.geometry import Polygon, box

from nesting_engine.nest_bin import SheetStockSpec, _apply_kerf
from nesting_engine.nest_libnest2d import capabilities, nest_multi_bin, nest_sheet
from nesting_engine.nest_spike import Placement, placed_polygon

_EPS_MM = 1e-6


def test_capabilities_reports_libnest2d_production() -> None:
    caps = capabilities()

    assert caps.spike_only is False
    assert "libnest2d" in caps.library.lower()


def test_nest_sheet_packs_multiple_rectangles() -> None:
    pieces = [box(0, 0, 40, 20), box(0, 0, 30, 25)]

    placements = nest_sheet(pieces, bin_width_mm=200.0, bin_height_mm=200.0, margin_mm=1.0, kerf_mm=0.0)

    assert len(placements) == len(pieces)
    _assert_all_fit_bin(pieces, placements, bin_width_mm=200.0, bin_height_mm=200.0, margin_mm=1.0, kerf_mm=0.0)


def test_nest_sheet_places_piece_with_hole() -> None:
    outer = box(0, 0, 80, 40)
    hole = box(20, 10, 60, 30)
    piece = Polygon(outer.exterior.coords, [list(hole.exterior.coords)])

    placements = nest_sheet([piece], bin_width_mm=200.0, bin_height_mm=200.0, margin_mm=1.0, kerf_mm=0.0)

    assert len(placements) == 1
    assert placements[0].rotation_deg >= 0.0
    _assert_all_fit_bin([piece], placements, bin_width_mm=200.0, bin_height_mm=200.0, margin_mm=1.0, kerf_mm=0.0)


def test_nest_sheet_uses_non_zero_rotation_when_required() -> None:
    piece = box(0, 0, 90, 20)

    placements = nest_sheet([piece], bin_width_mm=50.0, bin_height_mm=100.0, margin_mm=0.0, kerf_mm=0.0)

    assert len(placements) == 1
    assert placements[0].rotation_deg != 0.0
    assert placements[0].rotation_deg >= 15.0
    _assert_all_fit_bin([piece], placements, bin_width_mm=50.0, bin_height_mm=100.0, margin_mm=0.0, kerf_mm=0.0)


def _assert_all_fit_bin(
    pieces: list[Polygon],
    placements: list[Placement],
    *,
    bin_width_mm: float,
    bin_height_mm: float,
    margin_mm: float,
    kerf_mm: float,
) -> None:
    assert len(placements) == len(pieces)
    occupied: list[Polygon] = []
    for piece, placement in zip(pieces, placements, strict=True):
        fit_piece = _apply_kerf(piece, kerf_mm)
        placed = placed_polygon(fit_piece, placement)
        minx, miny, maxx, maxy = placed.bounds
        assert minx >= margin_mm - _EPS_MM
        assert miny >= margin_mm - _EPS_MM
        assert maxx <= bin_width_mm - margin_mm + _EPS_MM
        assert maxy <= bin_height_mm - margin_mm + _EPS_MM
        for obstacle in occupied:
            assert not (placed.intersects(obstacle) and not placed.touches(obstacle))
        occupied.append(placed)


def test_libnest2d_multi_bin_packs_multiple_pieces_on_one_sheet() -> None:
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


def test_libnest2d_margin_applies_at_sheet_edge_not_between_pieces() -> None:
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
    assert second.bounds[0] == pytest.approx(margin + 10.0, abs=0.05)


def test_libnest2d_kerf_keeps_minimum_gap_between_pieces() -> None:
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
    assert gap == pytest.approx(kerf, abs=0.2)


def test_libnest2d_unlimited_stock_opens_extra_sheets_when_full() -> None:
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
    assert result.sheets[1].offset_x_mm == pytest.approx(30.0, abs=0.05)
    assert result.sheets[2].offset_x_mm == pytest.approx(60.0, abs=0.05)


def test_libnest2d_finite_stock_then_next_sort_order() -> None:
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
