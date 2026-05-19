# [REQ-FIT-SPLIT-001] Auto-split planner: straight cuts, holes, recursive fit, failures.
from __future__ import annotations

import pytest
from shapely.geometry import Polygon, box

from nesting_engine.nest_types import SheetStockSpec
from nesting_engine.split_planner import SplitChild, plan_split

_EPS = 0.05


def _usable_bin(stock: SheetStockSpec, margin_mm: float) -> tuple[float, float]:
    return (
        stock.width_mm - (2 * margin_mm),
        stock.height_mm - (2 * margin_mm),
    )


def _fits_stock(polygon: Polygon, stock: SheetStockSpec, *, margin_mm: float) -> bool:
    inner_w, inner_h = _usable_bin(stock, margin_mm)
    minx, miny, maxx, maxy = polygon.bounds
    width = maxx - minx
    height = maxy - miny
    return width <= inner_w + _EPS and height <= inner_h + _EPS


def test_oversized_rectangle_splits_into_two_fit_largest_stock() -> None:
    """[REQ-FIT-SPLIT-001] 200×80 mm piece on 100×100 stock → two children that both fit."""
    piece = box(0, 0, 200, 80)
    stocks = [SheetStockSpec(width_mm=100, height_mm=100, quantity=None, sort_order=0)]

    result = plan_split(piece, stocks, margin_mm=0.0)

    assert result.feasible is True
    assert result.reason is None
    assert len(result.children) == 2
    assert all(isinstance(child, SplitChild) for child in result.children)
    assert all(_fits_stock(child.polygon, stocks[0], margin_mm=0.0) for child in result.children)
    assert len(result.cut_segments) >= 1


def test_split_preserves_internal_holes() -> None:
    """[REQ-FIT-SPLIT-001] Cuts must not slice through interior rings (holes)."""
    outer = [(0, 0), (200, 0), (200, 120), (0, 120)]
    hole = [(60, 40), (140, 40), (140, 80), (60, 80)]
    piece = Polygon(outer, [hole])
    stocks = [SheetStockSpec(width_mm=100, height_mm=100, quantity=None, sort_order=0)]

    result = plan_split(piece, stocks, margin_mm=0.0)

    assert result.feasible is True
    assert sum(1 for child in result.children if len(child.polygon.interiors) >= 1) >= 1


def test_recursive_resplit_until_children_fit() -> None:
    """[REQ-FIT-SPLIT-001] Child still oversized after first cut → further splits until fit."""
    piece = box(0, 0, 280, 70)
    stocks = [SheetStockSpec(width_mm=100, height_mm=100, quantity=None, sort_order=0)]

    result = plan_split(piece, stocks, margin_mm=0.0)

    assert result.feasible is True
    assert len(result.children) >= 3
    assert all(_fits_stock(child.polygon, stocks[0], margin_mm=0.0) for child in result.children)


def test_split_not_feasible_when_usable_bin_is_empty() -> None:
    """[REQ-FIT-SPLIT-001] No usable sheet area → split_not_feasible."""
    piece = box(0, 0, 100, 100)
    stocks = [SheetStockSpec(width_mm=20, height_mm=20, quantity=1, sort_order=0)]

    result = plan_split(piece, stocks, margin_mm=10.0)

    assert result.feasible is False
    assert result.reason == "split_not_feasible"
    assert result.children == []
