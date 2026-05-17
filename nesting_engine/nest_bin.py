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

    sheets = _consolidate_sheets(
        sheets,
        pieces,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=sheet_gap_mm,
    )

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
    pending = list(indices)
    still_unplaced: list[int] = []

    while pending:
        progress = False
        next_pending: list[int] = []
        for index in pending:
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
                next_pending.append(index)
                continue

            placed_pieces.append(PlacedPiece(piece_index=index, polygon=piece, placement=placement))
            occupied.append(placed_polygon(fit_piece, placement))
            progress = True

        pending = next_pending
        if not progress:
            still_unplaced = pending
            break

    return placed_pieces, still_unplaced


def _consolidate_sheets(
    sheets: list[NestedSheet],
    pieces: list[Polygon],
    *,
    margin_mm: float,
    kerf_mm: float,
    sheet_gap_mm: float,
) -> list[NestedSheet]:
    if len(sheets) <= 1:
        return _reindex_sheet_offsets(sheets, sheet_gap_mm)

    work = list(sheets)
    merged = True
    while merged:
        merged = False
        for target_idx in range(len(work)):
            for donor_idx in range(len(work) - 1, target_idx, -1):
                target = work[target_idx]
                donor = work[donor_idx]
                if target.width_mm != donor.width_mm or target.height_mm != donor.height_mm:
                    continue

                target_pieces = list(target.pieces)
                donor_pieces = list(donor.pieces)
                if not donor_pieces:
                    continue

                if _move_pieces_into_sheet(
                    target_pieces,
                    donor_pieces,
                    pieces,
                    target.width_mm,
                    target.height_mm,
                    margin_mm=margin_mm,
                    kerf_mm=kerf_mm,
                ):
                    work[target_idx] = NestedSheet(
                        stock_sort_order=target.stock_sort_order,
                        sheet_index=target.sheet_index,
                        width_mm=target.width_mm,
                        height_mm=target.height_mm,
                        offset_x_mm=target.offset_x_mm,
                        pieces=target_pieces,
                    )
                    work[donor_idx] = NestedSheet(
                        stock_sort_order=donor.stock_sort_order,
                        sheet_index=donor.sheet_index,
                        width_mm=donor.width_mm,
                        height_mm=donor.height_mm,
                        offset_x_mm=donor.offset_x_mm,
                        pieces=donor_pieces,
                    )
                    merged = True

        work = [sheet for sheet in work if sheet.pieces]

    return _reindex_sheet_offsets(work, sheet_gap_mm)


def _move_pieces_into_sheet(
    target_pieces: list[PlacedPiece],
    donor_pieces: list[PlacedPiece],
    pieces: list[Polygon],
    bin_width: float,
    bin_height: float,
    *,
    margin_mm: float,
    kerf_mm: float,
) -> bool:
    occupied = _occupied_polygons(target_pieces, pieces, kerf_mm)
    moved = False
    remaining: list[PlacedPiece] = []

    for placed in donor_pieces:
        fit_piece = _apply_kerf(pieces[placed.piece_index], kerf_mm)
        placement = _place_with_rotation(
            fit_piece,
            bin_width,
            bin_height,
            margin=margin_mm,
            obstacles=occupied,
        )
        if placement is None:
            remaining.append(placed)
            continue

        target_pieces.append(
            PlacedPiece(piece_index=placed.piece_index, polygon=placed.polygon, placement=placement)
        )
        occupied.append(placed_polygon(fit_piece, placement))
        moved = True

    donor_pieces[:] = remaining
    return moved


def _occupied_polygons(
    placed_pieces: list[PlacedPiece],
    pieces: list[Polygon],
    kerf_mm: float,
) -> list[Polygon]:
    occupied: list[Polygon] = []
    for placed in placed_pieces:
        fit_piece = _apply_kerf(pieces[placed.piece_index], kerf_mm)
        occupied.append(placed_polygon(fit_piece, placed.placement))
    return occupied


def _reindex_sheet_offsets(sheets: list[NestedSheet], sheet_gap_mm: float) -> list[NestedSheet]:
    offset_x = 0.0
    reindexed: list[NestedSheet] = []
    for sheet_index, sheet in enumerate(sheets):
        reindexed.append(
            NestedSheet(
                stock_sort_order=sheet.stock_sort_order,
                sheet_index=sheet_index,
                width_mm=sheet.width_mm,
                height_mm=sheet.height_mm,
                offset_x_mm=offset_x,
                pieces=sheet.pieces,
            )
        )
        offset_x += sheet.width_mm + sheet_gap_mm
    return reindexed


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
