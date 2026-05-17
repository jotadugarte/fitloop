# [REQ-FIT-NEST-002] Multi-bin nesting using P0 spike placement per sheet.
from __future__ import annotations

from dataclasses import dataclass

from shapely.geometry import Polygon

from nesting_engine.nest_spike import Placement, _place_with_rotation, placed_polygon, run_spike_nest


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


def nest_multi_bin(
    pieces: list[Polygon],
    sheet_stocks: list[SheetStockSpec],
    *,
    margin_mm: float,
    kerf_mm: float,
    sheet_gap_mm: float,
) -> MultiBinResult:
    assert margin_mm >= 0 and kerf_mm >= 0 and sheet_gap_mm >= 0, "non-negative job parameters"
    assert sheet_stocks, "at least one sheet stock required"

    warnings: list[str] = []
    remaining_indices = _indices_by_descending_area(pieces)
    sheets: list[NestedSheet] = []
    offset_x = 0.0
    stocks = sorted(sheet_stocks, key=lambda stock: stock.sort_order)

    for stock in stocks:
        sheets_used = 0
        while remaining_indices and _can_open_sheet(stock, sheets_used):
            placed, remaining_indices = _place_on_one_sheet(
                pieces,
                remaining_indices,
                stock.width_mm,
                stock.height_mm,
                margin_mm=margin_mm,
                kerf_mm=kerf_mm,
            )
            if not placed:
                break

            sheets.append(
                NestedSheet(
                    stock_sort_order=stock.sort_order,
                    sheet_index=sheets_used,
                    width_mm=stock.width_mm,
                    height_mm=stock.height_mm,
                    offset_x_mm=offset_x,
                    pieces=placed,
                )
            )
            offset_x += stock.width_mm + sheet_gap_mm
            sheets_used += 1

    orphans = _orphans_for_remaining(
        pieces,
        remaining_indices,
        stocks,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    return MultiBinResult(sheets=sheets, orphans=orphans, warnings=warnings)


def _indices_by_descending_area(pieces: list[Polygon]) -> list[int]:
    return sorted(range(len(pieces)), key=lambda index: pieces[index].area, reverse=True)


def _can_open_sheet(stock: SheetStockSpec, sheets_used: int) -> bool:
    if stock.quantity is None:
        return True
    return sheets_used < stock.quantity


def _place_on_one_sheet(
    pieces: list[Polygon],
    indices: list[int],
    bin_width: float,
    bin_height: float,
    *,
    margin_mm: float,
    kerf_mm: float,
) -> tuple[list[PlacedPiece], list[int]]:
    placed_pieces: list[PlacedPiece] = []
    occupied: list[Polygon] = []
    still_unplaced: list[int] = []

    for index in indices:
        piece = pieces[index]
        fit_piece = _apply_kerf(piece, kerf_mm)
        placement = _place_with_rotation(
            fit_piece,
            bin_width,
            bin_height,
            margin=margin_mm,
            obstacles=occupied,
        )
        if placement is None:
            still_unplaced.append(index)
            continue

        placed_pieces.append(PlacedPiece(piece_index=index, polygon=piece, placement=placement))
        occupied.append(placed_polygon(fit_piece, placement))

    return placed_pieces, still_unplaced


def _orphans_for_remaining(
    pieces: list[Polygon],
    indices: list[int],
    stocks: list[SheetStockSpec],
    *,
    margin_mm: float,
    kerf_mm: float,
) -> list[OrphanPiece]:
    orphans: list[OrphanPiece] = []
    for index in indices:
        piece = pieces[index]
        fit_piece = _apply_kerf(piece, kerf_mm)
        reason = (
            "oversized_for_sheet"
            if not _fits_any_stock(fit_piece, stocks, margin_mm=margin_mm)
            else "no_sheet_capacity"
        )
        orphans.append(OrphanPiece(piece_index=index, reason=reason))
    return orphans


def _fits_any_stock(
    piece: Polygon,
    stocks: list[SheetStockSpec],
    *,
    margin_mm: float,
) -> bool:
    for stock in stocks:
        result = run_spike_nest([piece], stock.width_mm, stock.height_mm, margin=margin_mm)
        if result.all_placed:
            return True
    return False


def _apply_kerf(piece: Polygon, kerf_mm: float) -> Polygon:
    if kerf_mm <= 0:
        return piece
    buffered = piece.buffer(kerf_mm / 2.0)
    assert not buffered.is_empty, "kerf buffer must not empty the piece"
    return buffered
