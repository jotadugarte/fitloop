# [REQ-FIT-NEST-002] Full-sheet batch vs per-piece greedy multi-bin fill.
from __future__ import annotations

from shapely.geometry import box

from nesting_engine.nest_bin import SheetStockSpec
from nesting_engine.nest_libnest2d import (
    _place_on_one_sheet,
    nest_multi_bin,
    nest_sheet,
)
from nesting_engine.nest_placement import placed_polygon

from nesting_engine.tests.test_nest_libnest2d import _assert_all_fit_bin


def test_place_on_one_sheet_batch_packs_five_strips_without_greedy() -> None:
    """[REQ-FIT-NEST-002] Five 80×30 mm strips on 250×250 mm: libnest2d batch is valid; fills in one batch pass."""
    pieces = [box(0, 0, 80, 30) for _ in range(5)]

    placed, remaining = _place_on_one_sheet(
        pieces,
        list(range(len(pieces))),
        250.0,
        250.0,
        margin_mm=0.0,
        kerf_mm=0.0,
    )

    assert remaining == []
    assert len(placed) == len(pieces)


def test_nest_multi_bin_batch_packs_five_strips_on_one_sheet() -> None:
    """[REQ-FIT-NEST-002] Same strip fixture: `nest_multi_bin` should stay on one sheet via full-sheet fill."""
    margin_mm = 0.0
    kerf_mm = 0.0
    bin_w, bin_h = 250.0, 250.0
    pieces = [box(0, 0, 80, 30) for _ in range(5)]
    stocks = [SheetStockSpec(width_mm=bin_w, height_mm=bin_h, quantity=None, sort_order=0)]

    batch_placements = nest_sheet(
        pieces,
        bin_width_mm=bin_w,
        bin_height_mm=bin_h,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    assert len(batch_placements) == len(pieces)
    _assert_all_fit_bin(
        pieces,
        batch_placements,
        bin_width_mm=bin_w,
        bin_height_mm=bin_h,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=0.0,
        time_limit_sec=30.0,
    )

    assert result.orphans == []
    assert len(result.sheets) <= 1

    sheet = result.sheets[0]
    assert len(sheet.pieces) == len(pieces)
    placements = [row.placement for row in sorted(sheet.pieces, key=lambda row: row.piece_index)]
    _assert_all_fit_bin(
        pieces,
        placements,
        bin_width_mm=bin_w,
        bin_height_mm=bin_h,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )

    if kerf_mm > 0.0:
        polys = [placed_polygon(pieces[row.piece_index], row.placement) for row in sheet.pieces]
        for left in range(len(polys)):
            for right in range(left + 1, len(polys)):
                gap = polys[left].distance(polys[right])
                assert gap >= kerf_mm - 0.2
