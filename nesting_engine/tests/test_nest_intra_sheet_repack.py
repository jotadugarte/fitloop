# [REQ-FIT-NEST-002] Intra-sheet repack closes internal voids via full-sheet re-nest.
from __future__ import annotations

import nesting_engine.nest_libnest2d as nest_libnest2d
import pytest
from shapely.geometry import box

from nesting_engine.nest_bin import SheetStockSpec
from nesting_engine.nest_libnest2d import (
    _intra_sheet_repack_search,
    _layout_score_for_sheet,
    nest_sheet,
    nest_sheet_with_obstacles,
)
from nesting_engine.nest_placement import Placement, _layout_better_than, placed_polygon, score_sheet_layout
from nesting_engine.nest_types import NestedSheet, PlacedPiece, apply_kerf

from nesting_engine.tests.test_nest_libnest2d import _assert_all_fit_bin


def _placed_polygons_on_sheet(
    sheet: NestedSheet,
    pieces: list[object],
    *,
    kerf_mm: float,
) -> list[object]:
    return [
        placed_polygon(apply_kerf(pieces[row.piece_index], kerf_mm), row.placement)
        for row in sheet.pieces
    ]


def _sheet_free_area_mm2(
    sheet: NestedSheet,
    pieces: list[object],
    *,
    margin_mm: float,
    kerf_mm: float,
) -> float:
    polys = _placed_polygons_on_sheet(sheet, pieces, kerf_mm=kerf_mm)
    free_area, _footprint = score_sheet_layout(sheet.width_mm, sheet.height_mm, margin_mm, polys)
    return free_area


def _fixture_fragmented_row_layout(
    pieces: list[object],
    *,
    bin_width_mm: float,
    bin_height_mm: float,
) -> NestedSheet:
    """Three strips on the top row plus one at origin — oversized footprint vs batch re-nest."""
    fragmented_placements = [
        Placement(0.0, 200.0, 0.0),
        Placement(85.0, 200.0, 0.0),
        Placement(170.0, 200.0, 0.0),
        Placement(0.0, 0.0, 0.0),
    ]
    placed = [
        PlacedPiece(piece_index=index, polygon=pieces[index], placement=fragmented_placements[index])
        for index in range(4)
    ]
    return NestedSheet(
        stock_sort_order=0,
        sheet_index=0,
        width_mm=bin_width_mm,
        height_mm=bin_height_mm,
        offset_x_mm=0.0,
        pieces=placed,
    )


def _fixture_fragmented_target_plus_sparse_donor(
    pieces: list[object],
    *,
    bin_width_mm: float,
    bin_height_mm: float,
) -> list[NestedSheet]:
    target = _fixture_fragmented_row_layout(pieces, bin_width_mm=bin_width_mm, bin_height_mm=bin_height_mm)
    donor = NestedSheet(
        stock_sort_order=0,
        sheet_index=1,
        width_mm=bin_width_mm,
        height_mm=bin_height_mm,
        offset_x_mm=bin_width_mm,
        pieces=[PlacedPiece(piece_index=4, polygon=pieces[4], placement=Placement(0.0, 0.0, 0.0))],
    )
    return [target, donor]


def test_intra_sheet_repack_pulls_piece_from_later_sheet() -> None:
    """[REQ-FIT-NEST-002] Repack on sheet 0 may absorb a piece from a later same-stock sheet."""
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
    assert len(repack.placements) == len(pieces), "fixture: all strips must batch-fit on one sheet"

    sheets = _fixture_fragmented_target_plus_sparse_donor(pieces, bin_width_mm=bin_w, bin_height_mm=bin_h)
    baseline_score = _layout_score_for_sheet(sheets[0], pieces, margin_mm=margin_mm, kerf_mm=kerf_mm)

    improved = _intra_sheet_repack_search(
        sheets,
        pieces,
        stocks,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=0.0,
        deadline=None,
    )

    assert len(improved) <= 1
    merged = improved[0]
    assert len(merged.pieces) == len(pieces)

    assert {row.piece_index for row in merged.pieces} == set(range(len(pieces)))

    placements = [row.placement for row in sorted(merged.pieces, key=lambda row: row.piece_index)]
    _assert_all_fit_bin(
        pieces,
        placements,
        bin_width_mm=bin_w,
        bin_height_mm=bin_h,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )


def test_intra_sheet_repack_respects_global_deadline(monkeypatch: pytest.MonkeyPatch) -> None:
    """[REQ-FIT-NEST-002] Expired deadline returns best-so-far layouts without error."""
    margin_mm = 0.0
    kerf_mm = 0.0
    bin_w, bin_h = 250.0, 250.0
    pieces = [box(0, 0, 80, 30) for _ in range(8)]
    stocks = [SheetStockSpec(width_mm=bin_w, height_mm=bin_h, quantity=None, sort_order=0)]

    sheet_a = _fixture_fragmented_row_layout(pieces[:4], bin_width_mm=bin_w, bin_height_mm=bin_h)
    sheet_b = _fixture_fragmented_row_layout(
        pieces[4:],
        bin_width_mm=bin_w,
        bin_height_mm=bin_h,
    )
    sheet_b = NestedSheet(
        stock_sort_order=sheet_b.stock_sort_order,
        sheet_index=1,
        width_mm=sheet_b.width_mm,
        height_mm=sheet_b.height_mm,
        offset_x_mm=bin_w,
        pieces=[
            PlacedPiece(piece_index=4 + index, polygon=pieces[4 + index], placement=row.placement)
            for index, row in enumerate(sheet_b.pieces)
        ],
    )
    sheets = [sheet_a, sheet_b]
    scores_before = [
        _layout_score_for_sheet(sheet, pieces, margin_mm=margin_mm, kerf_mm=kerf_mm) for sheet in sheets
    ]

    monkeypatch.setattr(nest_libnest2d.time, "monotonic", lambda: 1000.0)

    result = _intra_sheet_repack_search(
        sheets,
        pieces,
        stocks,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=0.0,
        deadline=0.0,
    )

    assert len(result) == 2
    assert sum(len(sheet.pieces) for sheet in result) == len(pieces)
    scores_after = [
        _layout_score_for_sheet(sheet, pieces, margin_mm=margin_mm, kerf_mm=kerf_mm) for sheet in result
    ]
    assert scores_after == scores_before, "expired deadline must not apply partial repacks"


def test_intra_sheet_repack_improves_free_area_on_synthetic_hole() -> None:
    """[REQ-FIT-NEST-002] Full-sheet re-nest on one bin must strictly increase continuous free area."""
    margin_mm = 0.0
    kerf_mm = 0.0
    bin_w, bin_h = 250.0, 250.0
    pieces = [box(0, 0, 80, 30) for _ in range(4)]
    stocks = [SheetStockSpec(width_mm=bin_w, height_mm=bin_h, quantity=None, sort_order=0)]

    batch = nest_sheet(pieces, bin_width_mm=bin_w, bin_height_mm=bin_h, margin_mm=margin_mm, kerf_mm=kerf_mm)
    assert len(batch) == len(pieces), "fixture: all strips must batch-fit on one sheet"

    sheet = _fixture_fragmented_row_layout(pieces, bin_width_mm=bin_w, bin_height_mm=bin_h)
    assert len(sheet.pieces) >= 2
    baseline_score = _layout_score_for_sheet(sheet, pieces, margin_mm=margin_mm, kerf_mm=kerf_mm)

    improved_sheets = _intra_sheet_repack_search(
        [sheet],
        pieces,
        stocks,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=0.0,
        deadline=None,
    )

    assert len(improved_sheets) == 1
    repacked = improved_sheets[0]
    assert len(repacked.pieces) == len(sheet.pieces)

    repacked_score = _layout_score_for_sheet(repacked, pieces, margin_mm=margin_mm, kerf_mm=kerf_mm)
    assert _layout_better_than(baseline_score, repacked_score), (
        "intra repack must improve layout score (free area, then footprint, then bottom-left)"
    )

    placements = [row.placement for row in sorted(repacked.pieces, key=lambda row: row.piece_index)]
    _assert_all_fit_bin(
        pieces,
        placements,
        bin_width_mm=bin_w,
        bin_height_mm=bin_h,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )

    placed_polys = _placed_polygons_on_sheet(repacked, pieces, kerf_mm=kerf_mm)
    for left in range(len(placed_polys)):
        for right in range(left + 1, len(placed_polys)):
            assert not (
                placed_polys[left].intersects(placed_polys[right])
                and not placed_polys[left].touches(placed_polys[right])
            )
