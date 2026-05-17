# [REQ-FIT-NEST-001] libnest2d binding spike via python-libnest2d (pynest2d).
from __future__ import annotations

import math
import time
from dataclasses import dataclass

from pynest2d import BLConfig, Box, Item, NfpConfig, Point, nest, nest_blp
from shapely.affinity import rotate, translate
from shapely.geometry import Polygon
from shapely.geometry.polygon import orient

from nesting_engine.nest_bin import (
    MultiBinResult,
    NestedSheet,
    OrphanPiece,
    PlacedPiece,
    SheetStockSpec,
    _apply_kerf,
)
from nesting_engine.nest_placement import Placement, place_with_rotation, placed_polygon

_BINDING_NAME = "python-libnest2d 0.1.3 (pynest2d)"
_MAX_PIECES = 64
_MIN_BIN_MM = 1.0
_ROTATION_STEPS_DEG = tuple(float(step) for step in range(0, 360, 15))
_PLACEMENT_AREA_TOLERANCE_MM2 = 150.0
_MAX_ANGLE_SEARCH_DEG = 360
_DEFAULT_TIME_LIMIT_SEC = 600.0


@dataclass(frozen=True)
class NestingCapabilities:
    """Production nesting engine capabilities (ADR 0001)."""

    library: str
    supports_holes: bool
    supports_any_angle_rotation: bool
    spike_only: bool


@dataclass(frozen=True)
class BindingPlacement:
    x_mm: float
    y_mm: float
    rotation_deg: float


@dataclass(frozen=True)
class BindingSpikeResult:
    placements: list[BindingPlacement]
    all_placed: bool


def libnest2d_binding_name() -> str:
    return _BINDING_NAME


def nest_sheet(
    pieces: list[Polygon],
    bin_width_mm: float,
    bin_height_mm: float,
    *,
    margin_mm: float,
    kerf_mm: float,
) -> list[Placement]:
    assert bin_width_mm >= _MIN_BIN_MM and bin_height_mm >= _MIN_BIN_MM, "bin must be positive"
    assert margin_mm >= 0.0 and kerf_mm >= 0.0, "margin and kerf must be non-negative"
    assert pieces, "at least one piece required"
    assert len(pieces) <= _MAX_PIECES, "piece count exceeds sheet limit"

    usable_w = max(int(round(bin_width_mm - 2.0 * margin_mm)), 1)
    usable_h = max(int(round(bin_height_mm - 2.0 * margin_mm)), 1)
    fit_pieces = [_apply_kerf(piece, kerf_mm) for piece in pieces]
    items = [_shapely_to_item(piece) for piece in fit_pieces]

    bins_used = _run_sheet_nest(items, usable_w, usable_h)
    assert bins_used >= 1, "libnest2d must allocate at least one bin"
    assert all(item.binId() >= 0 for item in items), "every piece must fit on the sheet"

    placements = [
        _placement_from_world(
            fit_piece,
            _world_polygon_from_item(item, margin_mm=margin_mm, usable_w=usable_w, usable_h=usable_h),
        )
        for fit_piece, item in zip(fit_pieces, items, strict=True)
    ]
    assert len(placements) == len(pieces)
    return placements


def nest_multi_bin(
    pieces: list[Polygon],
    sheet_stocks: list[SheetStockSpec],
    *,
    margin_mm: float,
    kerf_mm: float,
    sheet_gap_mm: float,
    time_limit_sec: float | None = _DEFAULT_TIME_LIMIT_SEC,
) -> MultiBinResult:
    assert margin_mm >= 0 and kerf_mm >= 0 and sheet_gap_mm >= 0, "non-negative job parameters"
    assert sheet_stocks, "at least one sheet stock required"
    if time_limit_sec is not None:
        assert time_limit_sec > 0.0, "time_limit_sec must be positive when set"

    warnings: list[str] = []
    deadline = _time_limit_deadline(time_limit_sec)
    remaining_indices = _indices_by_descending_area(pieces)
    sheets: list[NestedSheet] = []
    offset_x = 0.0
    stocks = sorted(sheet_stocks, key=lambda stock: stock.sort_order)
    timed_out = False

    for stock in stocks:
        if timed_out:
            break
        sheets_used = 0
        while remaining_indices and _can_open_sheet(stock, sheets_used):
            if _time_limit_exceeded(deadline):
                warnings.append(_time_limit_warning(time_limit_sec))
                timed_out = True
                break

            placed, remaining_indices = _place_on_one_sheet(
                pieces,
                remaining_indices,
                stock.width_mm,
                stock.height_mm,
                margin_mm=margin_mm,
                kerf_mm=kerf_mm,
                deadline=deadline,
            )
            if placed:
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

            if _time_limit_exceeded(deadline):
                warnings.append(_time_limit_warning(time_limit_sec))
                timed_out = True
                break
            if not placed:
                break

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
    assert len(sheets) >= 0
    return MultiBinResult(sheets=sheets, orphans=orphans, warnings=warnings)


def capabilities() -> NestingCapabilities:
    caps = NestingCapabilities(
        library=libnest2d_binding_name(),
        supports_holes=True,
        supports_any_angle_rotation=True,
        spike_only=False,
    )
    assert "libnest2d" in caps.library.lower()
    assert caps.spike_only is False
    return caps


def binding_spike_nest(
    pieces: list[Polygon],
    *,
    bin_width_mm: float,
    bin_height_mm: float,
    margin_mm: float = 1.0,
) -> BindingSpikeResult:
    assert bin_width_mm >= _MIN_BIN_MM and bin_height_mm >= _MIN_BIN_MM, "bin must be positive"
    assert margin_mm >= 0.0, "margin must be non-negative"
    assert pieces, "at least one piece required"
    assert len(pieces) <= _MAX_PIECES, "piece count exceeds spike limit"

    usable_w = max(int(round(bin_width_mm - 2.0 * margin_mm)), 1)
    usable_h = max(int(round(bin_height_mm - 2.0 * margin_mm)), 1)
    items = [_shapely_to_item(piece) for piece in pieces]
    config = _default_nfp_config()

    bins_used = nest(items, Box(usable_w, usable_h), distance=0, config=config)
    placements = _placements_from_items(items, margin_mm=margin_mm)
    all_placed = bins_used >= 1 and all(item.binId() >= 0 for item in items)

    assert len(placements) == len(pieces)
    return BindingSpikeResult(placements, all_placed)


def _default_nfp_config() -> NfpConfig:
    config = NfpConfig()
    config.rotations = list(_ROTATION_STEPS_DEG)
    return config


def _run_sheet_nest(items: list[Item], usable_w: int, usable_h: int) -> int:
    bin_shape = Box(usable_w, usable_h)
    if len(items) == 1:
        return nest(items, bin_shape, distance=0, config=_default_nfp_config())
    bl_config = BLConfig()
    bl_config.allow_rotations = True
    return nest_blp(items, bin_shape, distance=0, config=bl_config)


def _world_polygon_from_item(
    item: Item,
    *,
    margin_mm: float,
    usable_w: int,
    usable_h: int,
) -> Polygon:
    offset_x = usable_w / 2.0 + margin_mm
    offset_y = usable_h / 2.0 + margin_mm
    exterior = [(point.x() + offset_x, point.y() + offset_y) for point in item.transformedContour()]
    holes = [
        [(point.x() + offset_x, point.y() + offset_y) for point in ring]
        for ring in item.transformedHoles()
    ]
    if holes:
        return Polygon(exterior, holes)
    return Polygon(exterior)


def _placement_from_world(piece: Polygon, world: Polygon) -> Placement:
    wminx, wminy, _, _ = world.bounds
    best_placement: Placement | None = None
    best_diff = float("inf")
    for angle_index in range(_MAX_ANGLE_SEARCH_DEG):
        angle = float(angle_index)
        rotated = rotate(piece, angle, origin="centroid")
        rminx, rminy, _, _ = rotated.bounds
        offset_x = wminx - rminx
        offset_y = wminy - rminy
        placed = translate(rotated, xoff=offset_x, yoff=offset_y)
        diff = placed.symmetric_difference(world).area
        if diff < best_diff:
            best_diff = diff
            best_placement = Placement(offset_x, offset_y, angle)
    assert best_placement is not None, "placement search must find a candidate"
    assert best_diff <= _PLACEMENT_AREA_TOLERANCE_MM2, "libnest2d placement must map to Shapely transform"
    return best_placement


def _shapely_to_item(polygon: Polygon) -> Item:
    assert isinstance(polygon, Polygon), "piece must be a Shapely Polygon"
    assert not polygon.is_empty, "piece must not be empty"

    outer = orient(polygon, sign=-1.0)
    contour = _ring_to_points(outer.exterior.coords)
    holes = [_ring_to_points(ring.coords[::-1]) for ring in outer.interiors]
    if holes:
        return Item(contour, holes)
    return Item(contour)


def _ring_to_points(coords) -> list[Point]:
    ring = list(coords)
    if len(ring) > 1 and ring[0] == ring[-1]:
        ring = ring[:-1]
    points = [Point(int(round(x)), int(round(y))) for x, y in ring]
    assert len(points) >= 3, "polygon ring needs at least three vertices"
    return points


def _place_piece_on_sheet(
    fit_piece: Polygon,
    bin_width_mm: float,
    bin_height_mm: float,
    *,
    margin_mm: float,
    obstacles: list[Polygon],
) -> Placement | None:
    assert bin_width_mm >= _MIN_BIN_MM and bin_height_mm >= _MIN_BIN_MM, "bin must be positive"
    return place_with_rotation(
        fit_piece,
        bin_width_mm,
        bin_height_mm,
        margin=margin_mm,
        obstacles=obstacles,
    )


def _time_limit_deadline(time_limit_sec: float | None) -> float | None:
    if time_limit_sec is None or time_limit_sec <= 0.0:
        return None
    return time.monotonic() + time_limit_sec


def _time_limit_exceeded(deadline: float | None) -> bool:
    if deadline is None:
        return False
    return time.monotonic() >= deadline


def _time_limit_warning(time_limit_sec: float | None) -> str:
    limit = time_limit_sec if time_limit_sec is not None else _DEFAULT_TIME_LIMIT_SEC
    return f"time_limit_sec ({limit:g}s) exceeded; returning best-so-far placements"


def _place_on_one_sheet(
    pieces: list[Polygon],
    indices: list[int],
    bin_width: float,
    bin_height: float,
    *,
    margin_mm: float,
    kerf_mm: float,
    deadline: float | None = None,
) -> tuple[list[PlacedPiece], list[int]]:
    placed_pieces: list[PlacedPiece] = []
    occupied: list[Polygon] = []
    pending = list(indices)

    while pending:
        if _time_limit_exceeded(deadline):
            return placed_pieces, pending

        progress = False
        next_pending: list[int] = []
        for index in pending:
            if _time_limit_exceeded(deadline):
                next_pending.extend(pending[pending.index(index) :])
                return placed_pieces, next_pending

            fit_piece = _apply_kerf(pieces[index], kerf_mm)
            placement = _place_piece_on_sheet(
                fit_piece,
                bin_width,
                bin_height,
                margin_mm=margin_mm,
                obstacles=occupied,
            )
            if placement is None:
                next_pending.append(index)
                continue

            placed_pieces.append(PlacedPiece(piece_index=index, polygon=pieces[index], placement=placement))
            occupied.append(placed_polygon(fit_piece, placement))
            progress = True

        pending = next_pending
        if not progress:
            return placed_pieces, pending

    return placed_pieces, []


def _indices_by_descending_area(pieces: list[Polygon]) -> list[int]:
    return sorted(range(len(pieces)), key=lambda index: pieces[index].area, reverse=True)


def _can_open_sheet(stock: SheetStockSpec, sheets_used: int) -> bool:
    if stock.quantity is None:
        return True
    return sheets_used < stock.quantity


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
        placement = _place_piece_on_sheet(
            fit_piece,
            bin_width,
            bin_height,
            margin_mm=margin_mm,
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
        fit_piece = _apply_kerf(pieces[index], kerf_mm)
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
        placement = _place_piece_on_sheet(
            piece,
            stock.width_mm,
            stock.height_mm,
            margin_mm=margin_mm,
            obstacles=[],
        )
        if placement is not None:
            return True
    return False


def _placements_from_items(items: list[Item], *, margin_mm: float) -> list[BindingPlacement]:
    placements: list[BindingPlacement] = []
    for item in items:
        translation = item.translation()
        placements.append(
            BindingPlacement(
                x_mm=float(translation.x()) + margin_mm,
                y_mm=float(translation.y()) + margin_mm,
                rotation_deg=math.degrees(item.rotation()),
            )
        )
    assert len(placements) == len(items)
    return placements
