# [REQ-FIT-NEST-001] libnest2d binding spike via python-libnest2d (pynest2d).
from __future__ import annotations

import math
import time
from dataclasses import dataclass

from pynest2d import BLConfig, Box, Item, NfpConfig, Point, nest, nest_blp
from shapely.affinity import rotate, translate
from shapely.geometry import Polygon
from shapely.geometry.polygon import orient

from nesting_engine.nest_placement import (
    ROTATION_STEP_DEG,
    Placement,
    place_with_rotation,
    placed_polygon,
)
from nesting_engine.nest_types import (
    MultiBinResult,
    NestedSheet,
    OrphanPiece,
    PlacedPiece,
    SheetStockSpec,
    apply_kerf,
)

_BINDING_NAME = "python-libnest2d 0.1.3 (pynest2d)"
_MAX_PIECES = 128
_MIN_BIN_MM = 1.0
_MIN_COORD_QUANTUM_MM = 1.0
_ROTATION_STEPS_DEG = tuple(float(step) for step in range(0, 360, ROTATION_STEP_DEG))
_MAX_PLACEMENT_ANGLE_STEPS = 360 // ROTATION_STEP_DEG
_PLACEMENT_AREA_TOLERANCE_MM2 = 150.0
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


@dataclass(frozen=True)
class ObstacleAwareSheetResult:
    """[REQ-FIT-NEST-002] Placements for nestable pieces; explicit unplaced piece indices."""

    placements: dict[int, Placement]
    unplaced_indices: list[int]


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
    fit_pieces = [apply_kerf(piece, kerf_mm) for piece in pieces]
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


def nest_sheet_with_obstacles(
    pieces: list[Polygon],
    bin_width_mm: float,
    bin_height_mm: float,
    *,
    obstacles: list[Polygon],
    margin_mm: float,
    kerf_mm: float,
) -> ObstacleAwareSheetResult:
    """[REQ-FIT-NEST-002] Batch-nest pieces with fixed kerf-buffered obstacle footprints."""
    assert bin_width_mm >= _MIN_BIN_MM and bin_height_mm >= _MIN_BIN_MM, "bin must be positive"
    assert margin_mm >= 0.0 and kerf_mm >= 0.0, "margin and kerf must be non-negative"
    assert len(pieces) + len(obstacles) <= _MAX_PIECES, "item count exceeds sheet limit"
    assert pieces or obstacles, "at least one piece or obstacle required"

    usable_w, usable_h, frame_ox, frame_oy = _usable_frame(bin_width_mm, bin_height_mm, margin_mm)
    bin_box = Box(usable_w, usable_h)
    fixed_items = [_fixed_item_from_world_polygon(obs, ox=frame_ox, oy=frame_oy) for obs in obstacles]
    fit_pieces = [apply_kerf(piece, kerf_mm) for piece in pieces]
    nest_items = [_shapely_to_item(fit_piece) for fit_piece in fit_pieces]
    all_items = fixed_items + nest_items

    bins_used = _run_sheet_nest(all_items, usable_w, usable_h)
    if bins_used < 1:
        return ObstacleAwareSheetResult(
            placements={},
            unplaced_indices=list(range(len(pieces))),
        )

    placements, unplaced = _collect_obstacle_aware_placements(
        fit_pieces,
        nest_items,
        obstacles=obstacles,
        bin_box=bin_box,
        bin_width_mm=bin_width_mm,
        bin_height_mm=bin_height_mm,
        margin_mm=margin_mm,
        usable_w=usable_w,
        usable_h=usable_h,
    )
    assert len(placements) + len(unplaced) == len(pieces)
    return ObstacleAwareSheetResult(placements=placements, unplaced_indices=unplaced)


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

    deadline = _time_limit_deadline(time_limit_sec)
    remaining_indices = _indices_by_descending_area(pieces)
    stocks = sorted(sheet_stocks, key=lambda stock: stock.sort_order)

    sheets, remaining_indices, warnings = _nest_across_stocks(
        pieces,
        remaining_indices,
        stocks,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=sheet_gap_mm,
        time_limit_sec=time_limit_sec,
        deadline=deadline,
    )
    sheets = _consolidate_sheets(
        sheets,
        pieces,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=sheet_gap_mm,
        deadline=deadline,
    )
    sheets = _inter_sheet_local_search(
        sheets,
        pieces,
        stocks,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=sheet_gap_mm,
        deadline=deadline,
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


def _nest_across_stocks(
    pieces: list[Polygon],
    remaining_indices: list[int],
    stocks: list[SheetStockSpec],
    *,
    margin_mm: float,
    kerf_mm: float,
    sheet_gap_mm: float,
    time_limit_sec: float | None,
    deadline: float | None,
) -> tuple[list[NestedSheet], list[int], list[str]]:
    warnings: list[str] = []
    sheets: list[NestedSheet] = []
    offset_x = 0.0
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

    return sheets, remaining_indices, warnings


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


def _usable_frame(
    bin_width_mm: float,
    bin_height_mm: float,
    margin_mm: float,
) -> tuple[int, int, float, float]:
    usable_w = max(int(round(bin_width_mm - 2.0 * margin_mm)), 1)
    usable_h = max(int(round(bin_height_mm - 2.0 * margin_mm)), 1)
    frame_ox = usable_w / 2.0 + margin_mm
    frame_oy = usable_h / 2.0 + margin_mm
    return usable_w, usable_h, frame_ox, frame_oy


def _fixed_item_from_world_polygon(world: Polygon, *, ox: float, oy: float) -> Item:
    item = _world_polygon_to_item(world, ox=ox, oy=oy)
    item.setBinId(0)
    item.markAsFixedInBin(0)
    assert item.isFixed(), "obstacle item must be fixed in bin"
    return item


def _world_polygon_to_item(world: Polygon, *, ox: float, oy: float) -> Item:
    shifted = translate(world, xoff=-ox, yoff=-oy)
    return _shapely_to_item(shifted)


def _collect_obstacle_aware_placements(
    fit_pieces: list[Polygon],
    nest_items: list[Item],
    *,
    obstacles: list[Polygon],
    bin_box: Box,
    bin_width_mm: float,
    bin_height_mm: float,
    margin_mm: float,
    usable_w: int,
    usable_h: int,
) -> tuple[dict[int, Placement], list[int]]:
    placements: dict[int, Placement] = {}
    unplaced: list[int] = []
    placed_world: list[Polygon] = []

    for index, (fit_piece, item) in enumerate(zip(fit_pieces, nest_items, strict=True)):
        world = _world_polygon_from_item(
            item,
            margin_mm=margin_mm,
            usable_w=usable_w,
            usable_h=usable_h,
        )
        if item.binId() < 0:
            unplaced.append(index)
            continue
        if not _world_placement_valid(
            world,
            bin_width_mm=bin_width_mm,
            bin_height_mm=bin_height_mm,
            margin_mm=margin_mm,
            obstacles=obstacles,
            other_placed=placed_world,
        ):
            unplaced.append(index)
            continue
        placements[index] = _placement_from_world(fit_piece, world)
        placed_world.append(world)

    assert len(placements) + len(unplaced) == len(fit_pieces)
    return placements, unplaced


def _world_placement_valid(
    world: Polygon,
    *,
    bin_width_mm: float,
    bin_height_mm: float,
    margin_mm: float,
    obstacles: list[Polygon],
    other_placed: list[Polygon],
) -> bool:
    minx, miny, maxx, maxy = world.bounds
    if minx < margin_mm - _EPS_MM or miny < margin_mm - _EPS_MM:
        return False
    if maxx > bin_width_mm - margin_mm + _EPS_MM or maxy > bin_height_mm - margin_mm + _EPS_MM:
        return False
    for blocker in obstacles + other_placed:
        if world.intersects(blocker) and not world.touches(blocker):
            return False
    return True


_EPS_MM = 1e-6


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
    for step in range(_MAX_PLACEMENT_ANGLE_STEPS):
        angle = float(step * ROTATION_STEP_DEG)
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
    """Quantize vertices to integer mm for libnest2d; see _MIN_COORD_QUANTUM_MM."""
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
    """[REQ-FIT-NEST-002] Full-sheet libnest2d fill with Shapely fallback when batch places zero."""
    placed_pieces: list[PlacedPiece] = []
    occupied: list[Polygon] = []
    pending = list(indices)

    while pending:
        if _time_limit_exceeded(deadline):
            return placed_pieces, pending

        batch_placed, pending, occupied = _try_full_sheet_batch(
            pieces,
            pending,
            bin_width,
            bin_height,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
            occupied=occupied,
        )
        placed_pieces.extend(batch_placed)
        if batch_placed:
            continue

        placed_pieces, pending, occupied, progressed = _greedy_place_pending(
            pieces,
            pending,
            bin_width,
            bin_height,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
            occupied=occupied,
            placed_pieces=placed_pieces,
            deadline=deadline,
        )
        if not progressed:
            return placed_pieces, pending

    return placed_pieces, []


def _try_full_sheet_batch(
    pieces: list[Polygon],
    pending: list[int],
    bin_width: float,
    bin_height: float,
    *,
    margin_mm: float,
    kerf_mm: float,
    occupied: list[Polygon],
) -> tuple[list[PlacedPiece], list[int], list[Polygon]]:
    max_batch = _MAX_PIECES - len(occupied)
    if max_batch <= 0 or not pending:
        return [], pending, occupied

    batch_indices = pending[:max_batch]
    batch_pieces = [pieces[index] for index in batch_indices]
    if occupied:
        batch_result = nest_sheet_with_obstacles(
            batch_pieces,
            bin_width,
            bin_height,
            obstacles=occupied,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
        )
        return _placed_from_batch_result(
            pieces,
            batch_indices,
            batch_result,
            pending,
            kerf_mm=kerf_mm,
            occupied=occupied,
        )

    try:
        batch_placements = nest_sheet(
            batch_pieces,
            bin_width_mm=bin_width,
            bin_height_mm=bin_height,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
        )
    except AssertionError:
        return [], pending, occupied

    if not _batch_placements_are_valid(
        batch_pieces,
        batch_placements,
        bin_width_mm=bin_width,
        bin_height_mm=bin_height,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    ):
        return [], pending, occupied

    placed: list[PlacedPiece] = []
    for local_idx, placement in enumerate(batch_placements):
        piece_index = batch_indices[local_idx]
        fit_piece = apply_kerf(pieces[piece_index], kerf_mm)
        placed.append(PlacedPiece(piece_index=piece_index, polygon=pieces[piece_index], placement=placement))
        occupied.append(placed_polygon(fit_piece, placement))

    still_pending = pending[len(batch_indices) :]
    return placed, still_pending, occupied


def _placed_from_batch_result(
    pieces: list[Polygon],
    batch_indices: list[int],
    batch_result: ObstacleAwareSheetResult,
    pending: list[int],
    *,
    kerf_mm: float,
    occupied: list[Polygon],
) -> tuple[list[PlacedPiece], list[int], list[Polygon]]:
    if not batch_result.placements:
        return [], pending, occupied

    placed: list[PlacedPiece] = []
    for local_idx, placement in batch_result.placements.items():
        piece_index = batch_indices[local_idx]
        fit_piece = apply_kerf(pieces[piece_index], kerf_mm)
        placed.append(PlacedPiece(piece_index=piece_index, polygon=pieces[piece_index], placement=placement))
        occupied.append(placed_polygon(fit_piece, placement))

    still_pending = [batch_indices[local_idx] for local_idx in batch_result.unplaced_indices]
    still_pending.extend(pending[len(batch_indices) :])
    return placed, still_pending, occupied


def _batch_placements_are_valid(
    pieces: list[Polygon],
    placements: list[Placement],
    *,
    bin_width_mm: float,
    bin_height_mm: float,
    margin_mm: float,
    kerf_mm: float,
) -> bool:
    if len(placements) != len(pieces):
        return False

    occupied: list[Polygon] = []
    for piece, placement in zip(pieces, placements, strict=True):
        fit_piece = apply_kerf(piece, kerf_mm)
        placed = placed_polygon(fit_piece, placement)
        minx, miny, maxx, maxy = placed.bounds
        if minx < margin_mm - _EPS_MM or miny < margin_mm - _EPS_MM:
            return False
        if maxx > bin_width_mm - margin_mm + _EPS_MM or maxy > bin_height_mm - margin_mm + _EPS_MM:
            return False
        for blocker in occupied:
            if placed.intersects(blocker) and not placed.touches(blocker):
                return False
        occupied.append(placed)
    return True


def _greedy_place_pending(
    pieces: list[Polygon],
    pending: list[int],
    bin_width: float,
    bin_height: float,
    *,
    margin_mm: float,
    kerf_mm: float,
    occupied: list[Polygon],
    placed_pieces: list[PlacedPiece],
    deadline: float | None,
) -> tuple[list[PlacedPiece], list[int], list[Polygon], bool]:
    next_pending: list[int] = []
    progressed = False

    for index in pending:
        if _time_limit_exceeded(deadline):
            next_pending.extend(pending[pending.index(index) :])
            return placed_pieces, next_pending, occupied, progressed

        fit_piece = apply_kerf(pieces[index], kerf_mm)
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
        progressed = True

    return placed_pieces, next_pending, occupied, progressed


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
    deadline: float | None = None,
) -> list[NestedSheet]:
    """[REQ-FIT-NEST-002] Pairwise per-piece merge, then full-sheet repack for remaining donors."""
    if len(sheets) <= 1:
        return _reindex_sheet_offsets(sheets, sheet_gap_mm)

    work = list(sheets)
    merged = True
    while merged:
        if _time_limit_exceeded(deadline):
            break
        merged = False
        for target_idx in range(len(work)):
            for donor_idx in range(len(work) - 1, target_idx, -1):
                if _time_limit_exceeded(deadline):
                    break
                target = work[target_idx]
                donor = work[donor_idx]
                if target.width_mm != donor.width_mm or target.height_mm != donor.height_mm:
                    continue

                target_pieces = list(target.pieces)
                donor_pieces = list(donor.pieces)
                if not donor_pieces:
                    continue

                moved = _move_pieces_into_sheet(
                    target_pieces,
                    donor_pieces,
                    pieces,
                    target.width_mm,
                    target.height_mm,
                    margin_mm=margin_mm,
                    kerf_mm=kerf_mm,
                )
                repacked = False
                if donor_pieces and not _time_limit_exceeded(deadline):
                    repacked = _try_repack_merge_sheets(
                        target_pieces,
                        donor_pieces,
                        pieces,
                        target.width_mm,
                        target.height_mm,
                        margin_mm=margin_mm,
                        kerf_mm=kerf_mm,
                    )
                if not moved and not repacked:
                    continue

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


def _try_repack_merge_sheets(
    target_pieces: list[PlacedPiece],
    donor_pieces: list[PlacedPiece],
    pieces: list[Polygon],
    bin_width: float,
    bin_height: float,
    *,
    margin_mm: float,
    kerf_mm: float,
) -> bool:
    assert donor_pieces, "repack merge requires a non-empty donor"
    indices = [placed.piece_index for placed in target_pieces] + [
        placed.piece_index for placed in donor_pieces
    ]
    if len(indices) > _MAX_PIECES:
        return False

    batch_pieces = [pieces[index] for index in indices]
    result = nest_sheet_with_obstacles(
        batch_pieces,
        bin_width,
        bin_height,
        obstacles=[],
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    if len(result.placements) != len(indices):
        return False

    ordered = [result.placements[local_idx] for local_idx in range(len(indices))]
    if not _batch_placements_are_valid(
        batch_pieces,
        ordered,
        bin_width_mm=bin_width,
        bin_height_mm=bin_height,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    ):
        return False

    target_pieces[:] = [
        PlacedPiece(piece_index=indices[local_idx], polygon=pieces[indices[local_idx]], placement=ordered[local_idx])
        for local_idx in range(len(indices))
    ]
    donor_pieces.clear()
    return True


def _inter_sheet_local_search(
    sheets: list[NestedSheet],
    pieces: list[Polygon],
    sheet_stocks: list[SheetStockSpec],
    *,
    margin_mm: float,
    kerf_mm: float,
    sheet_gap_mm: float,
    deadline: float | None = None,
) -> list[NestedSheet]:
    """[REQ-FIT-NEST-002] Move pieces from sparse later sheets onto earlier same-size sheets via batch repack."""
    assert sheet_stocks, "sheet stocks required for inter-sheet search"
    if len(sheets) <= 1:
        return _reindex_sheet_offsets(sheets, sheet_gap_mm)

    work = list(sheets)
    progress = True
    while progress:
        if _time_limit_exceeded(deadline):
            break
        progress = False
        if len(work) <= 1:
            break

        donor_idx = len(work) - 1
        donor = work[donor_idx]
        if not donor.pieces:
            work.pop()
            progress = True
            continue

        for target_idx in range(donor_idx):
            if _time_limit_exceeded(deadline):
                break
            target = work[target_idx]
            if not _sheets_allow_piece_transfer(target, donor, sheet_stocks):
                continue

            target_pieces = list(target.pieces)
            donor_pieces = list(donor.pieces)
            if not _try_repack_merge_sheets(
                target_pieces,
                donor_pieces,
                pieces,
                target.width_mm,
                target.height_mm,
                margin_mm=margin_mm,
                kerf_mm=kerf_mm,
            ):
                continue

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
            progress = True
            break

        work = [sheet for sheet in work if sheet.pieces]

    return _reindex_sheet_offsets(work, sheet_gap_mm)


def _sheets_allow_piece_transfer(
    target: NestedSheet,
    donor: NestedSheet,
    sheet_stocks: list[SheetStockSpec],
) -> bool:
    if target.width_mm != donor.width_mm or target.height_mm != donor.height_mm:
        return False
    if target.stock_sort_order != donor.stock_sort_order:
        return False
    stock = _stock_for_sort_order(sheet_stocks, target.stock_sort_order)
    if stock is None:
        return False
    assert stock.width_mm == target.width_mm and stock.height_mm == target.height_mm
    return True


def _stock_for_sort_order(
    sheet_stocks: list[SheetStockSpec],
    sort_order: int,
) -> SheetStockSpec | None:
    for stock in sheet_stocks:
        if stock.sort_order == sort_order:
            return stock
    return None


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
        fit_piece = apply_kerf(pieces[placed.piece_index], kerf_mm)
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
        fit_piece = apply_kerf(pieces[placed.piece_index], kerf_mm)
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
        fit_piece = apply_kerf(pieces[index], kerf_mm)
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
