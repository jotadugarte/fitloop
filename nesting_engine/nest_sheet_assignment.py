# [REQ-FIT-NEST-002] Multi-sheet assignment heuristics for thorough nesting.
from __future__ import annotations

import math

from shapely.geometry import Polygon

from nesting_engine.nest_types import SheetStockSpec
from nesting_engine.piece_loader import piece_polygon


def sheet_count_lower_bound(
    pieces: list[Polygon],
    stock: SheetStockSpec,
    *,
    margin_mm: float,
) -> int:
    usable_w = stock.width_mm - 2 * margin_mm
    usable_h = stock.height_mm - 2 * margin_mm
    sheet_area = usable_w * usable_h
    assert sheet_area > 0.0
    total_area = sum(piece_polygon(piece).area for piece in pieces)
    if total_area <= 0.0:
        return 0
    return max(1, math.ceil(total_area / sheet_area))


def first_fit_decreasing_order(pieces: list[Polygon]) -> list[int]:
    return sorted(
        range(len(pieces)),
        key=lambda index: piece_polygon(pieces[index]).area,
        reverse=True,
    )
