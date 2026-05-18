# [REQ-FIT-NEST-002] Inter-sheet local search moves pieces off sparse last sheets.
from __future__ import annotations

from shapely.geometry import box
from shapely.ops import unary_union

from nesting_engine.nest_bin import SheetStockSpec
from nesting_engine.nest_libnest2d import _inter_sheet_local_search, nest_sheet_with_obstacles
from nesting_engine.nest_placement import Placement, placed_polygon
from nesting_engine.nest_types import NestedSheet, PlacedPiece

from nesting_engine.tests.test_nest_libnest2d import _assert_all_fit_bin


def _fixture_sparse_last_sheet(
    pieces: list[object],
    *,
    bin_width_mm: float,
    bin_height_mm: float,
) -> list[NestedSheet]:
    """Earlier sheet holds four strips; last sheet has one strip (sparse donor).

    Combined batch repack fits all five on one bin (see test precondition). Inter-sheet search
    should move the donor-sheet piece onto the earlier sheet and drop the empty sheet.
    """
    first_placements = [
        Placement(0.0, 0.0, 0.0),
        Placement(85.0, 0.0, 0.0),
        Placement(170.0, 0.0, 0.0),
        Placement(0.0, 100.0, 0.0),
    ]
    first_sheet = [
        PlacedPiece(piece_index=index, polygon=pieces[index], placement=first_placements[index])
        for index in range(4)
    ]
    last_sheet = [
        PlacedPiece(piece_index=4, polygon=pieces[4], placement=Placement(0.0, 0.0, 0.0)),
    ]
    return [
        NestedSheet(
            stock_sort_order=0,
            sheet_index=0,
            width_mm=bin_width_mm,
            height_mm=bin_height_mm,
            offset_x_mm=0.0,
            pieces=first_sheet,
        ),
        NestedSheet(
            stock_sort_order=0,
            sheet_index=1,
            width_mm=bin_width_mm,
            height_mm=bin_height_mm,
            offset_x_mm=bin_width_mm,
            pieces=last_sheet,
        ),
    ]


def test_inter_sheet_local_search_merges_sparse_last_sheet() -> None:
    """[REQ-FIT-NEST-002] Five 80×30 mm strips on 250×250 mm stock: move last-sheet piece onto the first sheet."""
    margin_mm = 0.0
    kerf_mm = 0.0
    bin_w, bin_h = 250.0, 250.0
    pieces = [box(0, 0, 80, 30) for _ in range(5)]
    stocks = [SheetStockSpec(width_mm=bin_w, height_mm=bin_h, quantity=None, sort_order=0)]

    repack = nest_sheet_with_obstacles(
        pieces,
        bin_width_mm=bin_w,
        bin_height_mm=bin_h,
        obstacles=[],
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    assert len(repack.placements) == len(pieces), "fixture must be batch-feasible on one bin"

    sheets = _fixture_sparse_last_sheet(pieces, bin_width_mm=bin_w, bin_height_mm=bin_h)
    assert len(sheets) == 2
    assert len(sheets[-1].pieces) == 1

    improved = _inter_sheet_local_search(
        sheets,
        pieces,
        stocks,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=0.0,
        deadline=None,
    )

    assert len(improved) < len(sheets), "should remove the sparse last sheet"
    assert len(improved) <= 1

    merged = improved[0]
    assert len(merged.pieces) == len(pieces)
    placements = [row.placement for row in sorted(merged.pieces, key=lambda row: row.piece_index)]
    _assert_all_fit_bin(
        pieces,
        placements,
        bin_width_mm=bin_w,
        bin_height_mm=bin_h,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )

    placed_polys = [placed_polygon(pieces[row.piece_index], row.placement) for row in merged.pieces]
    for left in range(len(placed_polys)):
        for right in range(left + 1, len(placed_polys)):
            assert not (
                placed_polys[left].intersects(placed_polys[right])
                and not placed_polys[left].touches(placed_polys[right])
            )

    occupied_union = unary_union(placed_polys)
    assert occupied_union.area > 0.0
