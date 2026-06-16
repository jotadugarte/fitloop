# [REQ-FIT-NEST-002] Multi-sheet assignment heuristic tests.
from __future__ import annotations

from shapely.geometry import box

from nesting_engine.nest_sheet_assignment import first_fit_decreasing_order, sheet_count_lower_bound
from nesting_engine.nest_types import SheetStockSpec


def test_sheet_count_lower_bound_uses_total_area() -> None:
    pieces = [box(0, 0, 100, 100), box(0, 0, 100, 100)]
    stock = SheetStockSpec(width_mm=200.0, height_mm=200.0, quantity=2, sort_order=0)
    assert sheet_count_lower_bound(pieces, stock, margin_mm=0.0) == 1


def test_first_fit_decreasing_order_sorts_by_area() -> None:
    pieces = [box(0, 0, 10, 10), box(0, 0, 50, 50)]
    assert first_fit_decreasing_order(pieces) == [1, 0]
