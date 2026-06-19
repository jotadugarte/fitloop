# [REQ-FIT-NEST-002] Multi-sheet assignment heuristic tests.
from __future__ import annotations

from shapely.geometry import box

from nesting_engine.nest_sheet_assignment import (
    assignment_seeds,
    first_fit_decreasing_order,
    sheet_count_lower_bound,
)
from nesting_engine.nest_types import SheetStockSpec


def test_sheet_count_lower_bound_uses_total_area() -> None:
    pieces = [box(0, 0, 100, 100), box(0, 0, 100, 100)]
    stock = SheetStockSpec(width_mm=200.0, height_mm=200.0, quantity=2, sort_order=0)
    assert sheet_count_lower_bound(pieces, stock, margin_mm=0.0) == 1


def test_first_fit_decreasing_order_sorts_by_area() -> None:
    pieces = [box(0, 0, 10, 10), box(0, 0, 50, 50)]
    assert first_fit_decreasing_order(pieces) == [1, 0]


def test_assignment_seeds_returns_ffd_area_ordering() -> None:
    pieces = [box(0, 0, 10, 10), box(0, 0, 50, 50)]
    # Single stock, quantity = 1 -> returns empty list (no multi-sheet assignment needed)
    stocks_single = [SheetStockSpec(width_mm=100.0, height_mm=100.0, quantity=1, sort_order=0)]
    assert assignment_seeds(pieces, stocks_single, margin_mm=0.0) == []

    # Multiple stocks or quantity > 1 -> returns extra OrderingSeed with ffd_area
    stocks_multi = [SheetStockSpec(width_mm=100.0, height_mm=100.0, quantity=2, sort_order=0)]
    seeds = assignment_seeds(pieces, stocks_multi, margin_mm=0.0)
    assert len(seeds) == 1
    assert seeds[0].name == "ffd_area:as_extracted"
    assert seeds[0].piece_order == (1, 0)
    assert seeds[0].orientation_profile == "as_extracted"

