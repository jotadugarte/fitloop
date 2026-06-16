# [REQ-FIT-NEST-002] Void rectangle detection tests.
from __future__ import annotations

from shapely.geometry import box

from nesting_engine.nest_types import NestedSheet, PlacedPiece
from nesting_engine.nest_placement import Placement
from nesting_engine.nest_voids import find_placeable_rects


def test_find_placeable_rects_on_empty_sheet() -> None:
    sheet = NestedSheet(
        stock_sort_order=0,
        sheet_index=0,
        width_mm=100.0,
        height_mm=80.0,
        offset_x_mm=0.0,
        pieces=[],
    )
    rects = find_placeable_rects(
        sheet,
        [],
        margin_mm=5.0,
        min_width_mm=10.0,
        min_height_mm=10.0,
    )
    assert rects
    assert rects[0].width >= 80.0
    assert rects[0].height >= 60.0


def test_find_placeable_rects_above_placed_piece() -> None:
    piece = box(0, 0, 40, 20)
    placement = Placement(x=10.0, y=10.0, rotation_deg=0.0)
    sheet = NestedSheet(
        stock_sort_order=0,
        sheet_index=0,
        width_mm=100.0,
        height_mm=80.0,
        offset_x_mm=0.0,
        pieces=[PlacedPiece(piece_index=0, polygon=piece, placement=placement)],
    )
    rects = find_placeable_rects(
        sheet,
        [piece],
        margin_mm=5.0,
        min_width_mm=10.0,
        min_height_mm=10.0,
    )
    assert rects
    assert max(rect.min_y for rect in rects) > 5.0
