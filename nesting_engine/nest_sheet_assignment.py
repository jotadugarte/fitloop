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


def assignment_seeds(
    pieces: list[Polygon],
    stocks: list[SheetStockSpec],
    *,
    margin_mm: float,
) -> list[OrderingSeed]:
    """[REQ-FIT-NEST-002] Multi-sheet assignment seed generator.

    Uses FFD sorting + stock-aware bin packing (finite stocks first).
    Returns a list containing one OrderingSeed ('ffd_area') if multiple sheets
    or stocks are available, otherwise returns an empty list.
    """
    if not pieces or not stocks:
        return []

    # Verify if we have multiple sheets / stocks
    total_qty = 0
    has_unlimited = False
    for s in stocks:
        if s.quantity is None:
            has_unlimited = True
        else:
            total_qty += s.quantity

    if len(stocks) <= 1 and total_qty <= 1 and not has_unlimited:
        return []

    from nesting_engine.nest_ordering import OrderingSeed
    from nesting_engine.sheet_stocks_config import stocks_in_consumption_order

    # 1. Standard FFD ordering of piece indices by area descending
    ffd_order = first_fit_decreasing_order(pieces)

    # 2. Stock-aware ordering: expand stocks into available bins
    ordered_stocks = stocks_in_consumption_order(stocks)
    bins = []
    for stock in ordered_stocks:
        usable_w = max(0.0, stock.width_mm - 2 * margin_mm)
        usable_h = max(0.0, stock.height_mm - 2 * margin_mm)
        usable_area = usable_w * usable_h
        qty = stock.quantity if stock.quantity is not None else 999999
        for _ in range(qty):
            bins.append({
                "w": usable_w,
                "h": usable_h,
                "area": usable_area,
                "remaining_area": usable_area,
                "pieces": [],
            })

    # Assign pieces to bins using First-Fit
    for p_idx in ffd_order:
        poly = piece_polygon(pieces[p_idx])
        min_x, min_y, max_x, max_y = poly.bounds
        p_w = max_x - min_x
        p_h = max_y - min_y
        p_area = poly.area

        placed = False
        for b in bins:
            # Fits oriented or rotated 90 degrees
            fits_dim = (p_w <= b["w"] and p_h <= b["h"]) or (p_h <= b["w"] and p_w <= b["h"])
            if fits_dim and b["remaining_area"] >= p_area:
                b["pieces"].append(p_idx)
                b["remaining_area"] -= p_area
                placed = True
                break
        if not placed:
            # Fallback to last bin if not placed
            bins[-1]["pieces"].append(p_idx)

    # Reconstruct the piece order from bins (grouping pieces by sheet)
    stock_aware_order = []
    for b in bins:
        stock_aware_order.extend(b["pieces"])

    # Deduplicate and verify all piece indices are included exactly once
    seen = set()
    final_order = []
    for idx in stock_aware_order:
        if idx not in seen and 0 <= idx < len(pieces):
            seen.add(idx)
            final_order.append(idx)

    for idx in range(len(pieces)):
        if idx not in seen:
            final_order.append(idx)

    return [
        OrderingSeed(
            name="ffd_area:as_extracted",
            piece_order=tuple(final_order),
            orientation_profile="as_extracted",
        )
    ]

