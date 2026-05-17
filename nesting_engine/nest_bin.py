# [REQ-FIT-NEST-002] Multi-bin nesting; placement via nest_libnest2d.
from __future__ import annotations

from dataclasses import dataclass

from shapely.geometry import Polygon

from nesting_engine.nest_placement import Placement


@dataclass(frozen=True)
class SheetStockSpec:
    width_mm: float
    height_mm: float
    quantity: int | None
    sort_order: int


@dataclass(frozen=True)
class PlacedPiece:
    piece_index: int
    polygon: Polygon
    placement: Placement


@dataclass(frozen=True)
class NestedSheet:
    stock_sort_order: int
    sheet_index: int
    width_mm: float
    height_mm: float
    offset_x_mm: float
    pieces: list[PlacedPiece]


@dataclass(frozen=True)
class OrphanPiece:
    piece_index: int
    reason: str


@dataclass(frozen=True)
class MultiBinResult:
    sheets: list[NestedSheet]
    orphans: list[OrphanPiece]
    warnings: list[str]


def _apply_kerf(piece: Polygon, kerf_mm: float) -> Polygon:
    if kerf_mm <= 0:
        return piece
    buffered = piece.buffer(kerf_mm / 2.0)
    assert not buffered.is_empty, "kerf buffer must not empty the piece"
    return buffered


def nest_multi_bin(
    pieces: list[Polygon],
    sheet_stocks: list[SheetStockSpec],
    *,
    margin_mm: float,
    kerf_mm: float,
    sheet_gap_mm: float,
    time_limit_sec: float = 600.0,
) -> MultiBinResult:
    from nesting_engine.nest_libnest2d import nest_multi_bin as libnest_multi_bin

    return libnest_multi_bin(
        pieces,
        sheet_stocks,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=sheet_gap_mm,
        time_limit_sec=time_limit_sec,
    )
