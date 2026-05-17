# [REQ-FIT-NEST-002] Shared multi-bin types and kerf buffer (no libnest2d import).
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


def apply_kerf(piece: Polygon, kerf_mm: float) -> Polygon:
    if kerf_mm <= 0:
        return piece
    buffered = piece.buffer(kerf_mm / 2.0)
    assert not buffered.is_empty, "kerf buffer must not empty the piece"
    return buffered
