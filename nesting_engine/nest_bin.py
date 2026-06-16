# [REQ-FIT-NEST-002] Multi-bin nesting; placement via nest_libnest2d.
from __future__ import annotations

from shapely.geometry import Polygon

from nesting_engine.nest_types import (
    MultiBinResult,
    NestedSheet,
    OrphanPiece,
    PlacedPiece,
    SheetStockSpec,
    apply_kerf,
)

_apply_kerf = apply_kerf

__all__ = [
    "MultiBinResult",
    "NestedSheet",
    "OrphanPiece",
    "PlacedPiece",
    "SheetStockSpec",
    "_apply_kerf",
    "apply_kerf",
    "nest_multi_bin",
]


def nest_multi_bin(
    pieces: list[Polygon],
    sheet_stocks: list[SheetStockSpec],
    *,
    margin_mm: float,
    kerf_mm: float,
    sheet_gap_mm: float,
    time_limit_sec: float = 600.0,
    progress_reporter=None,
    optimization_mode: str = "fast",
) -> MultiBinResult:
    from nesting_engine.nest_libnest2d import nest_multi_bin as libnest_multi_bin

    return libnest_multi_bin(
        pieces,
        sheet_stocks,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=sheet_gap_mm,
        time_limit_sec=time_limit_sec,
        progress_reporter=progress_reporter,
        optimization_mode=optimization_mode,
    )
