# [REQ-FIT-NEST-002] Extended consolidate via full-sheet repack on sparse donors.
from __future__ import annotations

import nesting_engine.nest_libnest2d as nest_libnest2d
import pytest
from shapely.geometry import box

from nesting_engine.nest_libnest2d import (
    _consolidate_sheets,
    nest_sheet_with_obstacles,
)
from nesting_engine.nest_placement import Placement, placed_polygon
from nesting_engine.nest_types import NestedSheet, PlacedPiece

from nesting_engine.tests.test_nest_libnest2d import _assert_all_fit_bin


def _fixture_four_plus_one_strips(
    pieces: list[object],
    *,
    bin_width_mm: float,
    bin_height_mm: float,
) -> list[NestedSheet]:
    """Target holds four strips in a fragmented row/column layout; donor has one strip.

    Per-piece merge can place the donor strip, but the monkeypatched test blocks that path
    to exercise full-sheet repack in extended `_consolidate_sheets`.
    """
    target_placements = [
        Placement(0.0, 0.0, 0.0),
        Placement(85.0, 0.0, 0.0),
        Placement(170.0, 0.0, 0.0),
        Placement(0.0, 100.0, 0.0),
    ]
    target = [
        PlacedPiece(piece_index=index, polygon=pieces[index], placement=target_placements[index])
        for index in range(4)
    ]
    donor = [PlacedPiece(piece_index=4, polygon=pieces[4], placement=Placement(0.0, 0.0, 0.0))]
    return [
        NestedSheet(
            stock_sort_order=0,
            sheet_index=0,
            width_mm=bin_width_mm,
            height_mm=bin_height_mm,
            offset_x_mm=0.0,
            pieces=target,
        ),
        NestedSheet(
            stock_sort_order=0,
            sheet_index=1,
            width_mm=bin_width_mm,
            height_mm=bin_height_mm,
            offset_x_mm=bin_width_mm,
            pieces=donor,
        ),
    ]


def test_consolidate_sheets_repack_merges_sparse_donor_when_per_piece_blocked(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """[REQ-FIT-NEST-002] Five 80×30 mm strips on 250×250 mm: batch repack fits one bin; per-piece path disabled.

    Fixture: four strips on target sheet, one on nearly empty donor (same stock size).
    Baseline `_consolidate_sheets` keeps two sheets when `_move_pieces_into_sheet` cannot move.
    Epic target: full-sheet repack on donor+target reduces to one sheet.
    """
    margin_mm = 0.0
    kerf_mm = 0.0
    bin_w, bin_h = 250.0, 250.0
    pieces = [box(0, 0, 80, 30) for _ in range(5)]

    repack = nest_sheet_with_obstacles(
        pieces,
        bin_width_mm=bin_w,
        bin_height_mm=bin_h,
        obstacles=[],
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    assert len(repack.placements) == len(pieces), "fixture must be batch-feasible on one bin"

    sheets = _fixture_four_plus_one_strips(pieces, bin_width_mm=bin_w, bin_height_mm=bin_h)
    assert len(sheets) == 2
    assert len(sheets[0].pieces) == 4
    assert len(sheets[1].pieces) == 1

    monkeypatch.setattr(nest_libnest2d, "_move_pieces_into_sheet", lambda *args, **kwargs: False)

    consolidated = _consolidate_sheets(
        sheets,
        pieces,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=0.0,
    )

    assert len(consolidated) <= 1, "full-sheet repack should merge donor into target"

    merged = consolidated[0]
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
