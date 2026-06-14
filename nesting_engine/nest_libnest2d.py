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
    _EPS_MM,
    _fits_bin,
    _layout_better_than,
    _layout_bounds,
    _layout_rank_key,
    place_with_rotation,
    placed_polygon,
    polygons_overlap_significantly,
    score_sheet_layout,
)
from nesting_engine.sheet_stocks_config import stocks_in_consumption_order
from nesting_engine.nest_types import (
    MultiBinResult,
    NestedSheet,
    OrphanPiece,
    PlacedPiece,
    SheetStockSpec,
    apply_kerf,
)
from nesting_engine.piece_loader import piece_polygon, placed_piece_from_source
from nesting_engine.nest_geometry_classify import (
    ORTHO_ROTATIONS_DEG,
    classify_geometry,
    is_axis_aligned_on_sheet,
    pre_align_orthogonal,
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
class SheetPiecePlacement:
    """Placement plus the geometry it applies to (quantized source or absolute world polygon)."""

    placement: Placement
    geometry: Polygon


@dataclass(frozen=True)
class ObstacleAwareSheetResult:
    """[REQ-FIT-NEST-002] Placements for nestable pieces; explicit unplaced piece indices."""

    placements: dict[int, SheetPiecePlacement]
    unplaced_indices: list[int]


@dataclass(frozen=True)
class _BatchOrthoContext:
    all_orthogonal: bool
    any_orthogonal: bool


@dataclass(frozen=True)
class _PreparedSolverPiece:
    solver_geometry: Polygon
    source_geometry: Polygon
    pre_align_deg: float | None
    is_orthogonal: bool


def _prepare_solver_piece(geometry: Polygon) -> _PreparedSolverPiece:
    is_orthogonal, _principal = classify_geometry(geometry)
    aligned, pre_align_deg = pre_align_orthogonal(geometry)
    return _PreparedSolverPiece(
        solver_geometry=aligned,
        source_geometry=geometry,
        pre_align_deg=pre_align_deg,
        is_orthogonal=is_orthogonal,
    )


def _batch_ortho_context(prepared: list[_PreparedSolverPiece]) -> _BatchOrthoContext:
    flags = [row.is_orthogonal for row in prepared]
    return _BatchOrthoContext(
        all_orthogonal=bool(flags) and all(flags),
        any_orthogonal=any(flags),
    )


def _centered_bin_for_batch(
    nest_piece_count: int,
    obstacle_count: int,
    *,
    all_orthogonal: bool,
) -> bool:
    """Cardinal NFP nest() uses a centered usable frame; bottom-left only for nest_blp batches."""
    if nest_piece_count + obstacle_count == 1:
        return True
    if obstacle_count > 0:
        return False
    return nest_piece_count >= 2 and all_orthogonal


def _all_pieces_orthogonal(pieces: list[Polygon]) -> bool:
    if not pieces:
        return False
    return all(classify_geometry(piece)[0] for piece in pieces)


def _orthogonal_placement_from_world(source_geometry: Polygon, world: Polygon) -> Placement:
    wminx, wminy, _, _ = world.bounds
    best_placement: Placement | None = None
    best_diff = float("inf")
    for angle in ORTHO_ROTATIONS_DEG:
        rotated = rotate(source_geometry, angle, origin="centroid")
        rminx, rminy, _, _ = rotated.bounds
        placement = Placement(wminx - rminx, wminy - rminy, float(angle))
        diff = placed_polygon(source_geometry, placement).symmetric_difference(world).area
        if diff < best_diff:
            best_diff = diff
            best_placement = placement
    assert best_placement is not None, "orthogonal placement must match item world"
    return best_placement


def _sheet_placement_from_nest_item(
    item: Item,
    prep: _PreparedSolverPiece,
    source_geometry: Polygon,
    *,
    margin_mm: float,
    usable_w: int,
    usable_h: int,
    centered_bin: bool,
) -> Placement:
    world = _world_polygon_from_item(
        item,
        margin_mm=margin_mm,
        usable_w=usable_w,
        usable_h=usable_h,
        centered_bin=centered_bin,
    )
    if prep.pre_align_deg is not None and abs(prep.pre_align_deg) > _EPS_MM:
        solver_placement = Placement(0.0, 0.0, math.degrees(item.rotation()))
        return _restore_placement_to_source(
            source_geometry,
            prep.solver_geometry,
            solver_placement,
            pre_align_deg=prep.pre_align_deg,
            world_geometry=world,
        )
    if prep.is_orthogonal:
        return _orthogonal_placement_from_world(source_geometry, world)
    placement, _diff = _placement_from_world_best_effort(source_geometry, world)
    return placement


def _restore_placement_to_source(
    source_geometry: Polygon,
    solver_geometry: Polygon,
    solver_placement: Placement,
    *,
    pre_align_deg: float | None = None,
    world_geometry: Polygon | None = None,
) -> Placement:
    world = world_geometry if world_geometry is not None else placed_polygon(
        solver_geometry, solver_placement
    )
    if pre_align_deg is not None:
        rotation_deg = (solver_placement.rotation_deg - pre_align_deg) % 360.0
        rotated = rotate(source_geometry, rotation_deg, origin="centroid")
        wminx, wminy, _, _ = world.bounds
        rminx, rminy, _, _ = rotated.bounds
        placement = Placement(wminx - rminx, wminy - rminy, rotation_deg)
        placed = placed_polygon(source_geometry, placement)
        assert is_axis_aligned_on_sheet(placed), (
            f"pre-aligned orthogonal piece must nest axis-aligned (rotation_deg={rotation_deg})"
        )
        return placement
    restored, _diff = _placement_from_world_best_effort(source_geometry, world)
    return restored


def _nfp_config_for_batch(*, orthogonal: bool) -> NfpConfig:
    config = NfpConfig()
    if orthogonal:
        config.rotations = [math.radians(deg) for deg in ORTHO_ROTATIONS_DEG]
    else:
        config.rotations = list(_ROTATION_STEPS_DEG)
    return config


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

    fit_pieces = [apply_kerf(piece, kerf_mm) for piece in pieces]
    centered_bin = _centered_bin_for_batch(
        len(pieces),
        0,
        all_orthogonal=_all_pieces_orthogonal([piece_polygon(row) for row in fit_pieces]),
    )
    usable_w, usable_h, frame_ox, frame_oy = _usable_frame(
        bin_width_mm, bin_height_mm, margin_mm, centered_bin=centered_bin
    )

    prepared: list[_PreparedSolverPiece] = []
    offsets = []
    for piece in fit_pieces:
        geom = piece_polygon(piece)
        minx, miny, _, _ = geom.bounds
        if centered_bin:
            ox = -usable_w / 2.0 - minx
            oy = -usable_h / 2.0 - miny
        else:
            ox = -minx
            oy = -miny
        offsets.append((ox, oy))
        translated = translate(geom, xoff=ox, yoff=oy)
        prepared.append(_prepare_solver_piece(translated))

    ortho_ctx = _batch_ortho_context(prepared)
    items = [_shapely_to_item(row.solver_geometry) for row in prepared]

    bins_used = _run_sheet_nest(items, usable_w, usable_h, ortho_ctx=ortho_ctx)
    assert bins_used >= 1, "libnest2d must allocate at least one bin"
    assert all(item.binId() >= 0 for item in items), "every piece must fit on the sheet"

    placements = []
    for index, (prep, item, _offset) in enumerate(zip(prepared, items, offsets, strict=True)):
        fit_geom = piece_polygon(fit_pieces[index])
        if ortho_ctx.all_orthogonal:
            orig_placement = _sheet_placement_from_nest_item(
                item,
                prep,
                fit_geom,
                margin_mm=margin_mm,
                usable_w=usable_w,
                usable_h=usable_h,
                centered_bin=centered_bin,
            )
        else:
            resolved = _resolve_libnest2d_placement(
                _quantize_polygon(prep.solver_geometry),
                item,
                margin_mm=margin_mm,
                usable_w=usable_w,
                usable_h=usable_h,
                frame_ox=frame_ox,
                frame_oy=frame_oy,
                centered_bin=centered_bin,
            )
            ox, oy = offsets[index]
            if prep.pre_align_deg is not None and abs(prep.pre_align_deg) > _EPS_MM:
                solver_world = placed_polygon(prep.solver_geometry, resolved.placement)
                sheet_world = translate(solver_world, xoff=ox, yoff=oy)
                orig_placement = _restore_placement_to_source(
                    fit_geom,
                    prep.solver_geometry,
                    resolved.placement,
                    pre_align_deg=prep.pre_align_deg,
                    world_geometry=sheet_world,
                )
            else:
                orig_placement = Placement(
                    x=resolved.placement.x + ox,
                    y=resolved.placement.y + oy,
                    rotation_deg=resolved.placement.rotation_deg,
                )
        placements.append(orig_placement)

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

    fit_pieces = [apply_kerf(piece, kerf_mm) for piece in pieces]
    centered_bin = _centered_bin_for_batch(
        len(pieces),
        len(obstacles),
        all_orthogonal=_all_pieces_orthogonal([piece_polygon(row) for row in fit_pieces]),
    )
    usable_w, usable_h, frame_ox, frame_oy = _usable_frame(
        bin_width_mm, bin_height_mm, margin_mm, centered_bin=centered_bin
    )
    bin_box = Box(usable_w, usable_h)
    fixed_items = [_fixed_item_from_world_polygon(obs, ox=frame_ox, oy=frame_oy) for obs in obstacles]

    prepared: list[_PreparedSolverPiece] = []
    offsets = []
    for piece in fit_pieces:
        geom = piece_polygon(piece)
        minx, miny, _, _ = geom.bounds
        if centered_bin:
            ox = -usable_w / 2.0 - minx
            oy = -usable_h / 2.0 - miny
        else:
            ox = -minx
            oy = -miny
        offsets.append((ox, oy))
        translated = translate(geom, xoff=ox, yoff=oy)
        prepared.append(_prepare_solver_piece(translated))

    ortho_ctx = _batch_ortho_context(prepared)
    nest_items = [_shapely_to_item(row.solver_geometry) for row in prepared]
    all_items = fixed_items + nest_items

    bins_used = _run_sheet_nest(all_items, usable_w, usable_h, ortho_ctx=ortho_ctx)
    if bins_used < 1:
        return ObstacleAwareSheetResult(
            placements={},
            unplaced_indices=list(range(len(pieces))),
        )

    placements, unplaced = _collect_obstacle_aware_placements(
        prepared,
        nest_items,
        obstacles=obstacles,
        bin_box=bin_box,
        bin_width_mm=bin_width_mm,
        bin_height_mm=bin_height_mm,
        margin_mm=margin_mm,
        usable_w=usable_w,
        usable_h=usable_h,
        frame_ox=frame_ox,
        frame_oy=frame_oy,
        centered_bin=centered_bin,
    )

    shifted_placements = {}
    for index, resolved in placements.items():
        ox, oy = offsets[index]
        prep = prepared[index]
        fit_geom = piece_polygon(fit_pieces[index])
        if ortho_ctx.all_orthogonal:
            orig_placement = _sheet_placement_from_nest_item(
                nest_items[index],
                prep,
                fit_geom,
                margin_mm=margin_mm,
                usable_w=usable_w,
                usable_h=usable_h,
                centered_bin=centered_bin,
            )
        elif prep.pre_align_deg is not None and abs(prep.pre_align_deg) > _EPS_MM:
            solver_world = placed_polygon(prep.solver_geometry, resolved.placement)
            sheet_world = translate(solver_world, xoff=ox, yoff=oy)
            orig_placement = _restore_placement_to_source(
                fit_geom,
                prep.solver_geometry,
                resolved.placement,
                pre_align_deg=prep.pre_align_deg,
                world_geometry=sheet_world,
            )
        else:
            orig_placement = Placement(
                x=resolved.placement.x + ox,
                y=resolved.placement.y + oy,
                rotation_deg=resolved.placement.rotation_deg,
            )
        orig_geometry = translate(resolved.geometry, xoff=-ox, yoff=-oy)
        shifted_placements[index] = SheetPiecePlacement(
            placement=orig_placement,
            geometry=orig_geometry,
        )

    assert len(shifted_placements) + len(unplaced) == len(pieces)
    return ObstacleAwareSheetResult(placements=shifted_placements, unplaced_indices=unplaced)


def _fill_phase_percent(pieces_placed: int, pieces_total: int) -> int:
    assert pieces_total >= 0 and pieces_placed >= 0
    if pieces_total <= 0:
        return 12
    ratio = min(1.0, pieces_placed / pieces_total)
    return min(55, 12 + int(43 * ratio))


def _report_pipeline_progress(
    progress_reporter,
    phase_id: str,
    percent: int,
    *,
    pieces_total: int | None = None,
    pieces_placed: int | None = None,
) -> None:
    if progress_reporter is None:
        return
    progress_reporter.report(
        phase_id,
        percent,
        pieces_total=pieces_total,
        pieces_placed=pieces_placed,
    )


def nest_multi_bin(
    pieces: list[Polygon],
    sheet_stocks: list[SheetStockSpec],
    *,
    margin_mm: float,
    kerf_mm: float,
    sheet_gap_mm: float,
    time_limit_sec: float | None = _DEFAULT_TIME_LIMIT_SEC,
    progress_reporter=None,
) -> MultiBinResult:
    assert margin_mm >= 0 and kerf_mm >= 0 and sheet_gap_mm >= 0, "non-negative job parameters"
    assert sheet_stocks, "at least one sheet stock required"
    if time_limit_sec is not None:
        assert time_limit_sec > 0.0, "time_limit_sec must be positive when set"

    deadline = _time_limit_deadline(time_limit_sec)
    remaining_indices = _indices_by_descending_area(pieces)
    stocks = stocks_in_consumption_order(sheet_stocks)
    total_pieces = len(pieces)

    _report_pipeline_progress(
        progress_reporter,
        "fill",
        12,
        pieces_total=total_pieces,
        pieces_placed=0,
    )
    sheets, remaining_indices, warnings = _nest_across_stocks(
        pieces,
        remaining_indices,
        stocks,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=sheet_gap_mm,
        time_limit_sec=time_limit_sec,
        deadline=deadline,
        progress_reporter=progress_reporter,
        pieces_total=total_pieces,
    )
    placed_count = total_pieces - len(remaining_indices)
    _report_pipeline_progress(
        progress_reporter,
        "fill",
        55,
        pieces_total=total_pieces,
        pieces_placed=placed_count,
    )
    sheets = _run_post_fill_phases(
        sheets,
        pieces,
        stocks,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=sheet_gap_mm,
        deadline=deadline,
        progress_reporter=progress_reporter,
        pieces_total=total_pieces,
        pieces_placed=placed_count,
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


def _run_post_fill_phases(
    sheets: list[NestedSheet],
    pieces: list[Polygon],
    stocks: list[SheetStockSpec],
    *,
    margin_mm: float,
    kerf_mm: float,
    sheet_gap_mm: float,
    deadline: float | None,
    progress_reporter=None,
    pieces_total: int = 0,
    pieces_placed: int = 0,
) -> list[NestedSheet]:
    """[REQ-FIT-NEST-002] Intra repack (×2), consolidate, then inter-sheet search under one deadline."""
    _report_pipeline_progress(
        progress_reporter,
        "optimizing",
        58,
        pieces_total=pieces_total,
        pieces_placed=pieces_placed,
    )
    sheets = _intra_sheet_repack_search(
        sheets,
        pieces,
        stocks,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=sheet_gap_mm,
        deadline=deadline,
    )
    _report_pipeline_progress(
        progress_reporter,
        "consolidating",
        72,
        pieces_total=pieces_total,
        pieces_placed=pieces_placed,
    )
    sheets = _consolidate_sheets(
        sheets,
        pieces,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=sheet_gap_mm,
        deadline=deadline,
    )
    _report_pipeline_progress(
        progress_reporter,
        "refining",
        82,
        pieces_total=pieces_total,
        pieces_placed=pieces_placed,
    )
    sheets = _intra_sheet_repack_search(
        sheets,
        pieces,
        stocks,
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
    _report_pipeline_progress(
        progress_reporter,
        "refining",
        90,
        pieces_total=pieces_total,
        pieces_placed=pieces_placed,
    )
    return sheets


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
    progress_reporter=None,
    pieces_total: int = 0,
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
                if pieces_total > 0:
                    placed_count = pieces_total - len(remaining_indices)
                    percent = _fill_phase_percent(placed_count, pieces_total)
                    _report_pipeline_progress(
                        progress_reporter,
                        "fill",
                        percent,
                        pieces_total=pieces_total,
                        pieces_placed=placed_count,
                    )

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
    items = [_shapely_to_item(piece_polygon(piece)) for piece in pieces]
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
    centered_bin: bool = True,
) -> tuple[int, int, float, float]:
    usable_w = max(int(round(bin_width_mm - 2.0 * margin_mm)), 1)
    usable_h = max(int(round(bin_height_mm - 2.0 * margin_mm)), 1)
    if centered_bin:
        frame_ox = usable_w / 2.0 + margin_mm
        frame_oy = usable_h / 2.0 + margin_mm
    else:
        frame_ox = margin_mm
        frame_oy = margin_mm
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
    prepared: list[_PreparedSolverPiece],
    nest_items: list[Item],
    *,
    obstacles: list[Polygon],
    bin_box: Box,
    bin_width_mm: float,
    bin_height_mm: float,
    margin_mm: float,
    usable_w: int,
    usable_h: int,
    frame_ox: float,
    frame_oy: float,
    centered_bin: bool = True,
) -> tuple[dict[int, Placement], list[int]]:
    placements: dict[int, Placement] = {}
    unplaced: list[int] = []
    placed_world: list[Polygon] = []

    for index, (prep, item) in enumerate(zip(prepared, nest_items, strict=True)):
        world = _world_polygon_from_item(
            item,
            margin_mm=margin_mm,
            usable_w=usable_w,
            usable_h=usable_h,
            centered_bin=centered_bin,
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
        nest_geom = _quantize_polygon(prep.solver_geometry)
        resolved = _resolve_libnest2d_placement(
            nest_geom,
            item,
            margin_mm=margin_mm,
            usable_w=usable_w,
            usable_h=usable_h,
            frame_ox=frame_ox,
            frame_oy=frame_oy,
            centered_bin=centered_bin,
        )
        placements[index] = resolved
        placed_world.append(_sheet_piece_world_polygon(resolved))

    assert len(placements) + len(unplaced) == len(prepared)
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
            if polygons_overlap_significantly(world, blocker):
                return False
    return True


_EPS_MM = 1e-6


def _run_sheet_nest(
    items: list[Item],
    usable_w: int,
    usable_h: int,
    *,
    ortho_ctx: _BatchOrthoContext | None = None,
) -> int:
    bin_shape = Box(usable_w, usable_h)
    ctx = ortho_ctx or _BatchOrthoContext(all_orthogonal=False, any_orthogonal=False)
    if len(items) == 1 or ctx.all_orthogonal:
        return nest(
            items,
            bin_shape,
            distance=0,
            config=_nfp_config_for_batch(orthogonal=ctx.any_orthogonal),
        )
    bl_config = BLConfig()
    bl_config.allow_rotations = not ctx.any_orthogonal
    return nest_blp(items, bin_shape, distance=0, config=bl_config)


def _world_polygon_from_item(
    item: Item,
    *,
    margin_mm: float,
    usable_w: int,
    usable_h: int,
    centered_bin: bool = True,
) -> Polygon:
    if centered_bin:
        offset_x = usable_w / 2.0 + margin_mm
        offset_y = usable_h / 2.0 + margin_mm
    else:
        offset_x = margin_mm
        offset_y = margin_mm
    exterior = [(point.x() + offset_x, point.y() + offset_y) for point in item.transformedContour()]
    holes = [
        [(point.x() + offset_x, point.y() + offset_y) for point in ring]
        for ring in item.transformedHoles()
    ]
    if holes:
        return Polygon(exterior, holes)
    return Polygon(exterior)


def _raw_polygon_from_item(item: Item) -> Polygon:
    outer = [(point.x(), point.y()) for point in item.rawContour()]
    holes = [[(point.x(), point.y()) for point in ring] for ring in item.rawHoles()]
    if holes:
        return Polygon(outer, holes)
    return Polygon(outer)


def _quantize_polygon(polygon: Polygon) -> Polygon:
    """Round-trip through libnest2d integer-mm vertices (same geometry the solver sees)."""
    return _raw_polygon_from_item(_shapely_to_item(polygon))


def _sheet_piece_world_polygon(resolved: SheetPiecePlacement) -> Polygon:
    return placed_polygon(resolved.geometry, resolved.placement)


def _placement_matches_world(
    fit_piece: Polygon,
    placement: Placement,
    world: Polygon,
    *,
    tolerance_mm2: float | None = None,
) -> bool:
    if tolerance_mm2 is None:
        tolerance_mm2 = max(_PLACEMENT_AREA_TOLERANCE_MM2, 0.01 * fit_piece.area)
    diff = placed_polygon(fit_piece, placement).symmetric_difference(world).area
    return diff <= tolerance_mm2


def _placement_from_world(piece: Polygon, world: Polygon) -> Placement:
    """Discrete-angle inverse map; asserts when no centroid+translate model fits within tolerance."""
    placement, best_diff = _placement_from_world_best_effort(piece, world)
    tolerance = max(_PLACEMENT_AREA_TOLERANCE_MM2, 0.01 * piece.area)
    assert best_diff <= tolerance, "libnest2d placement must map to Shapely transform"
    return placement


def _placement_from_world_best_effort(piece: Polygon, world: Polygon) -> tuple[Placement, float]:
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
    return best_placement, best_diff


def _resolve_libnest2d_placement(
    nest_geometry: Polygon,
    item: Item,
    *,
    margin_mm: float,
    usable_w: int,
    usable_h: int,
    frame_ox: float,
    frame_oy: float,
    centered_bin: bool = True,
) -> SheetPiecePlacement:
    """Map pynest2d item pose to Placement; use transformed contour when inverse fit fails."""
    world = _world_polygon_from_item(
        item,
        margin_mm=margin_mm,
        usable_w=usable_w,
        usable_h=usable_h,
        centered_bin=centered_bin,
    )
    angle = math.degrees(item.rotation())
    candidates: list[Placement] = []

    rotated = rotate(nest_geometry, angle, origin="centroid")
    wminx, wminy, _, _ = world.bounds
    rminx, rminy, _, _ = rotated.bounds
    candidates.append(Placement(wminx - rminx, wminy - rminy, angle))

    translation = item.translation()
    candidates.append(
        Placement(
            float(translation.x()) + frame_ox,
            float(translation.y()) + frame_oy,
            angle,
        )
    )

    tolerance = max(_PLACEMENT_AREA_TOLERANCE_MM2, 0.01 * nest_geometry.area)

    for placement in candidates:
        if _placement_matches_world(nest_geometry, placement, world, tolerance_mm2=tolerance):
            return SheetPiecePlacement(placement=placement, geometry=nest_geometry)

    placement, best_diff = _placement_from_world_best_effort(nest_geometry, world)
    if best_diff <= tolerance:
        return SheetPiecePlacement(placement=placement, geometry=nest_geometry)

    return SheetPiecePlacement(placement=Placement(0.0, 0.0, 0.0), geometry=world)


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
    # Round decimal coords to integers first
    rounded = [(int(round(x)), int(round(y))) for x, y in coords]

    # Remove consecutive duplicate coordinates to avoid zero-length segments
    cleaned = []
    for pt in rounded:
        if not cleaned or cleaned[-1] != pt:
            cleaned.append(pt)

    # Ensure the loop is closed by appending the first point to the end if needed
    if len(cleaned) > 1 and cleaned[0] != cleaned[-1]:
        cleaned.append(cleaned[0])

    assert len(cleaned) >= 4, "polygon ring needs at least four vertices (including closing vertex)"
    return [Point(x, y) for x, y in cleaned]


def _place_piece_on_sheet(
    fit_piece: Polygon,
    bin_width_mm: float,
    bin_height_mm: float,
    *,
    margin_mm: float,
    obstacles: list[Polygon],
) -> Placement | None:
    assert bin_width_mm >= _MIN_BIN_MM and bin_height_mm >= _MIN_BIN_MM, "bin must be positive"
    geom = piece_polygon(fit_piece)
    prep = _prepare_solver_piece(geom)
    allowed = list(ORTHO_ROTATIONS_DEG) if prep.is_orthogonal else None
    placement = place_with_rotation(
        prep.solver_geometry,
        bin_width_mm,
        bin_height_mm,
        margin=margin_mm,
        obstacles=obstacles,
        allowed_rotations=allowed,
    )
    if placement is None:
        return None
    if prep.pre_align_deg is not None:
        return _restore_placement_to_source(
            geom,
            prep.solver_geometry,
            placement,
            pre_align_deg=prep.pre_align_deg,
        )
    return placement


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

    if placed_pieces:
        placed_pieces = _compact_placed_pieces_to_margin(
            placed_pieces,
            pieces,
            bin_width,
            bin_height,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
        )

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
        return _try_full_sheet_batch_with_obstacles(
            pieces,
            batch_indices,
            batch_pieces,
            pending,
            bin_width,
            bin_height,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
            occupied=occupied,
        )
    return _try_full_sheet_batch_clean(
        pieces,
        batch_indices,
        batch_pieces,
        pending,
        bin_width,
        bin_height,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        occupied=occupied,
    )


def _try_full_sheet_batch_with_obstacles(
    pieces: list[Polygon],
    batch_indices: list[int],
    batch_pieces: list[Polygon],
    pending: list[int],
    bin_width: float,
    bin_height: float,
    *,
    margin_mm: float,
    kerf_mm: float,
    occupied: list[Polygon],
) -> tuple[list[PlacedPiece], list[int], list[Polygon]]:
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


def _try_full_sheet_batch_clean(
    pieces: list[Polygon],
    batch_indices: list[int],
    batch_pieces: list[Polygon],
    pending: list[int],
    bin_width: float,
    bin_height: float,
    *,
    margin_mm: float,
    kerf_mm: float,
    occupied: list[Polygon],
) -> tuple[list[PlacedPiece], list[int], list[Polygon]]:
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

    batch_placements = _shift_placements_to_bottom_left(
        batch_pieces,
        batch_placements,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
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
        placed.append(placed_piece_from_source(piece_index, pieces[piece_index], placement))
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
    for local_idx, resolved in batch_result.placements.items():
        piece_index = batch_indices[local_idx]
        placed.append(
            placed_piece_from_source(piece_index, pieces[piece_index], resolved.placement)
        )
        occupied.append(_sheet_piece_world_polygon(resolved))

    still_pending = [batch_indices[local_idx] for local_idx in batch_result.unplaced_indices]
    still_pending.extend(pending[len(batch_indices) :])
    return placed, still_pending, occupied


def _batch_resolved_placements_are_valid(
    resolved_placements: list[SheetPiecePlacement],
    *,
    bin_width_mm: float,
    bin_height_mm: float,
    margin_mm: float,
) -> bool:
    occupied: list[Polygon] = []
    for resolved in resolved_placements:
        placed = _sheet_piece_world_polygon(resolved)
        minx, miny, maxx, maxy = placed.bounds
        if minx < margin_mm - _EPS_MM or miny < margin_mm - _EPS_MM:
            return False
        if maxx > bin_width_mm - margin_mm + _EPS_MM or maxy > bin_height_mm - margin_mm + _EPS_MM:
            return False
        for obstacle in occupied:
            if polygons_overlap_significantly(placed, obstacle):
                return False
        occupied.append(placed)
    return True


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
            if polygons_overlap_significantly(placed, blocker):
                return False
        occupied.append(placed)
    return True


def _shift_placements_to_bottom_left(
    pieces: list[Polygon],
    placements: list[Placement],
    *,
    margin_mm: float,
    kerf_mm: float,
) -> list[Placement]:
    """Shift a batch layout so its combined bbox sits on the sheet margin (bottom-left)."""
    placed_polys = [
        placed_polygon(apply_kerf(piece, kerf_mm), placement)
        for piece, placement in zip(pieces, placements, strict=True)
    ]
    minx = min(poly.bounds[0] for poly in placed_polys)
    miny = min(poly.bounds[1] for poly in placed_polys)
    dx = margin_mm - minx
    dy = margin_mm - miny
    if abs(dx) <= _EPS_MM and abs(dy) <= _EPS_MM:
        return placements
    return [
        Placement(placement.x + dx, placement.y + dy, placement.rotation_deg)
        for placement in placements
    ]


def _shift_placed_pieces_to_bottom_left(
    sheet_pieces: list[PlacedPiece],
    pieces: list[Polygon],
    *,
    margin_mm: float,
    kerf_mm: float,
) -> list[PlacedPiece]:
    """[REQ-FIT-NEST-002] Shift a sheet layout so its combined bbox sits on the margin."""
    if not sheet_pieces:
        return sheet_pieces
    subset = [pieces[row.piece_index] for row in sheet_pieces]
    placements = [row.placement for row in sheet_pieces]
    shifted = _shift_placements_to_bottom_left(
        subset,
        placements,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    return [
        placed_piece_from_source(
            sheet_pieces[index].piece_index,
            pieces[sheet_pieces[index].piece_index],
            shifted[index],
        )
        for index in range(len(sheet_pieces))
    ]


def _placement_from_compacted_world(source_geometry: Polygon, world: Polygon) -> Placement:
    prep = _prepare_solver_piece(source_geometry)
    if prep.is_orthogonal:
        return _orthogonal_placement_from_world(source_geometry, world)
    placement, _diff = _placement_from_world_best_effort(source_geometry, world)
    return placement


def _compact_placed_pieces_to_margin(
    sheet_pieces: list[PlacedPiece],
    pieces: list[Polygon],
    bin_width: float,
    bin_height: float,
    *,
    margin_mm: float,
    kerf_mm: float,
) -> list[PlacedPiece]:
    """[REQ-FIT-NEST-002] Shift layout to margin, then align each piece's left edge to margin."""
    if not sheet_pieces:
        return sheet_pieces

    shifted = _shift_placed_pieces_to_bottom_left(
        sheet_pieces,
        pieces,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    placements = [row.placement for row in shifted]
    order = sorted(
        range(len(shifted)),
        key=lambda index: (
            placed_polygon(
                piece_polygon(apply_kerf(pieces[shifted[index].piece_index], kerf_mm)),
                placements[index],
            ).bounds[1],
            placed_polygon(
                piece_polygon(apply_kerf(pieces[shifted[index].piece_index], kerf_mm)),
                placements[index],
            ).bounds[0],
        ),
    )
    updated = list(placements)
    for index in order:
        piece_index = shifted[index].piece_index
        fit_geom = piece_polygon(apply_kerf(pieces[piece_index], kerf_mm))
        placed = placed_polygon(fit_geom, updated[index])
        dx = margin_mm - placed.bounds[0]
        if abs(dx) <= _EPS_MM:
            continue
        trial = translate(placed, xoff=dx, yoff=0.0)
        if not _fits_bin(trial, bin_width, bin_height, margin=margin_mm):
            continue
        obstacles = [
            placed_polygon(
                piece_polygon(apply_kerf(pieces[shifted[other].piece_index], kerf_mm)),
                updated[other],
            )
            for other in range(len(shifted))
            if other != index
        ]
        if any(polygons_overlap_significantly(trial, obstacle) for obstacle in obstacles):
            continue
        prep = _prepare_solver_piece(fit_geom)
        if prep.pre_align_deg is not None and abs(prep.pre_align_deg) > _EPS_MM:
            updated[index] = Placement(
                updated[index].x + dx,
                updated[index].y,
                updated[index].rotation_deg,
            )
        else:
            updated[index] = _placement_from_compacted_world(fit_geom, trial)

    compacted_pieces = [
        placed_piece_from_source(
            shifted[index].piece_index,
            pieces[shifted[index].piece_index],
            updated[index],
        )
        for index in range(len(shifted))
    ]
    if not _sheet_pieces_are_valid(
        compacted_pieces,
        pieces,
        bin_width_mm=bin_width,
        bin_height_mm=bin_height,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    ):
        return shifted
    return compacted_pieces


def _apply_sheet_margin_shift(
    work: list[NestedSheet],
    sheet_idx: int,
    pieces: list[Polygon],
    *,
    margin_mm: float,
    kerf_mm: float,
) -> list[NestedSheet]:
    sheet = work[sheet_idx]
    if not sheet.pieces:
        return work
    baseline_score = _layout_score_for_pieces(
        sheet.pieces,
        pieces,
        sheet.width_mm,
        sheet.height_mm,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    compacted = _compact_placed_pieces_to_margin(
        sheet.pieces,
        pieces,
        sheet.width_mm,
        sheet.height_mm,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    compacted_score = _layout_score_for_pieces(
        compacted,
        pieces,
        sheet.width_mm,
        sheet.height_mm,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    if not _layout_better_than(baseline_score, compacted_score):
        return work
    work[sheet_idx] = NestedSheet(
        stock_sort_order=sheet.stock_sort_order,
        sheet_index=sheet.sheet_index,
        width_mm=sheet.width_mm,
        height_mm=sheet.height_mm,
        offset_x_mm=sheet.offset_x_mm,
        pieces=compacted,
    )
    return work


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

    for offset, index in enumerate(pending):
        if _time_limit_exceeded(deadline):
            next_pending.extend(pending[offset:])
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

        placed_pieces.append(placed_piece_from_source(index, pieces[index], placement))
        occupied.append(placed_polygon(fit_piece, placement))
        progressed = True

    return placed_pieces, next_pending, occupied, progressed


def _indices_by_descending_area(pieces: list[Polygon]) -> list[int]:
    return sorted(
        range(len(pieces)),
        key=lambda index: piece_polygon(pieces[index]).area,
        reverse=True,
    )


def _can_open_sheet(stock: SheetStockSpec, sheets_used: int) -> bool:
    if stock.quantity is None:
        return True
    return sheets_used < int(stock.quantity)


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
        merged, work = _consolidate_one_pass(
            work,
            pieces,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
            deadline=deadline,
        )
        work = [sheet for sheet in work if sheet.pieces]

    return _reindex_sheet_offsets(work, sheet_gap_mm)


def _consolidate_one_pass(
    work: list[NestedSheet],
    pieces: list[Polygon],
    *,
    margin_mm: float,
    kerf_mm: float,
    deadline: float | None,
) -> tuple[bool, list[NestedSheet]]:
    merged = False
    for target_idx in range(len(work)):
        for donor_idx in range(len(work) - 1, target_idx, -1):
            if _time_limit_exceeded(deadline):
                return merged, work
            if _try_consolidate_pair(
                work,
                target_idx,
                donor_idx,
                pieces,
                margin_mm=margin_mm,
                kerf_mm=kerf_mm,
                deadline=deadline,
            ):
                merged = True
    return merged, work


def _try_consolidate_pair(
    work: list[NestedSheet],
    target_idx: int,
    donor_idx: int,
    pieces: list[Polygon],
    *,
    margin_mm: float,
    kerf_mm: float,
    deadline: float | None,
) -> bool:
    target = work[target_idx]
    donor = work[donor_idx]
    if target.width_mm != donor.width_mm or target.height_mm != donor.height_mm:
        return False

    target_pieces = list(target.pieces)
    donor_pieces = list(donor.pieces)
    if not donor_pieces:
        return False

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
        return False

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
    return True


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
    if not _batch_resolved_placements_are_valid(
        ordered,
        bin_width_mm=bin_width,
        bin_height_mm=bin_height,
        margin_mm=margin_mm,
    ):
        return False

    target_pieces[:] = [
        placed_piece_from_source(
            indices[local_idx],
            pieces[indices[local_idx]],
            ordered[local_idx].placement,
        )
        for local_idx in range(len(indices))
    ]
    donor_pieces.clear()
    return True


def _sheet_pieces_are_valid(
    sheet_pieces: list[PlacedPiece],
    pieces: list[Polygon],
    *,
    bin_width_mm: float,
    bin_height_mm: float,
    margin_mm: float,
    kerf_mm: float,
) -> bool:
    if not sheet_pieces:
        return True
    subset = [pieces[row.piece_index] for row in sheet_pieces]
    placements = [row.placement for row in sheet_pieces]
    return _batch_placements_are_valid(
        subset,
        placements,
        bin_width_mm=bin_width_mm,
        bin_height_mm=bin_height_mm,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )


def _try_orthogonal_flip_improvements(
    sheet_pieces: list[PlacedPiece],
    pieces: list[Polygon],
    bin_width: float,
    bin_height: float,
    *,
    margin_mm: float,
    kerf_mm: float,
) -> list[PlacedPiece] | None:
    """[REQ-FIT-NEST-002] Try rotating each orthogonal piece by 90° when layout score improves."""
    if len(sheet_pieces) < 2:
        return None
    if len(sheet_pieces) >= 3:
        return None

    best = sheet_pieces
    best_score = _layout_score_for_pieces(
        best,
        pieces,
        bin_width,
        bin_height,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    improved = False

    for index, placed_row in enumerate(best):
        piece_index = placed_row.piece_index
        fit_geom = piece_polygon(apply_kerf(pieces[piece_index], kerf_mm))
        prep = _prepare_solver_piece(fit_geom)
        if not prep.is_orthogonal:
            continue
        if prep.pre_align_deg is not None and abs(prep.pre_align_deg) > _EPS_MM:
            continue

        other_occupied = _occupied_polygons(
            [row for row_index, row in enumerate(best) if row_index != index],
            pieces,
            kerf_mm,
        )
        flip_rot = (placed_row.placement.rotation_deg + 90.0) % 360.0
        solver_placement = place_with_rotation(
            prep.solver_geometry,
            bin_width,
            bin_height,
            margin=margin_mm,
            obstacles=other_occupied,
            allowed_rotations=[flip_rot],
        )
        if solver_placement is None:
            continue

        new_placement = Placement(
            solver_placement.x,
            solver_placement.y,
            solver_placement.rotation_deg,
        )

        placed_poly = placed_polygon(fit_geom, new_placement)
        if not is_axis_aligned_on_sheet(placed_poly):
            continue

        trial = list(best)
        trial[index] = placed_piece_from_source(piece_index, pieces[piece_index], new_placement)
        if not _sheet_pieces_are_valid(
            trial,
            pieces,
            bin_width_mm=bin_width,
            bin_height_mm=bin_height,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
        ):
            continue

        trial_score = _layout_score_for_pieces(
            trial,
            pieces,
            bin_width,
            bin_height,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
        )
        if _layout_better_than(best_score, trial_score):
            best = trial
            best_score = trial_score
            improved = True

    return best if improved else None


def _intra_sheet_repack_search(
    sheets: list[NestedSheet],
    pieces: list[Polygon],
    sheet_stocks: list[SheetStockSpec],
    *,
    margin_mm: float,
    kerf_mm: float,
    sheet_gap_mm: float,
    deadline: float | None = None,
) -> list[NestedSheet]:
    """[REQ-FIT-NEST-002] Full-sheet re-nest per bin to maximize largest continuous free area."""
    assert sheet_stocks, "sheet stocks required for intra-sheet repack"
    work = list(sheets)

    for sheet_idx, sheet in enumerate(work):
        if _time_limit_exceeded(deadline):
            break
        work = _apply_intra_repack_to_sheet(
            work,
            sheet_idx,
            sheet,
            pieces,
            sheet_stocks,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
            deadline=deadline,
        )

    work = [sheet for sheet in work if sheet.pieces]
    return _reindex_sheet_offsets(work, sheet_gap_mm)


def _apply_intra_repack_to_sheet(
    work: list[NestedSheet],
    sheet_idx: int,
    sheet: NestedSheet,
    pieces: list[Polygon],
    sheet_stocks: list[SheetStockSpec],
    *,
    margin_mm: float,
    kerf_mm: float,
    deadline: float | None,
) -> list[NestedSheet]:
    if len(sheet.pieces) < 2:
        return work

    baseline_score = _layout_score_for_sheet(sheet, pieces, margin_mm=margin_mm, kerf_mm=kerf_mm)
    baseline_count = len(sheet.pieces)
    best = _best_intra_repack_candidate(
        sheet,
        work,
        sheet_idx,
        pieces,
        sheet_stocks,
        baseline_score=baseline_score,
        baseline_count=baseline_count,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        deadline=deadline,
    )
    if best is None or _time_limit_exceeded(deadline):
        work = _apply_orthogonal_flip_if_better(
            work,
            sheet_idx,
            sheet,
            pieces,
            baseline_score=baseline_score,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
        )
        return _apply_sheet_margin_shift(
            work,
            sheet_idx,
            pieces,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
        )

    repacked_pieces, pulled_indices = best
    work[sheet_idx] = NestedSheet(
        stock_sort_order=sheet.stock_sort_order,
        sheet_index=sheet.sheet_index,
        width_mm=sheet.width_mm,
        height_mm=sheet.height_mm,
        offset_x_mm=sheet.offset_x_mm,
        pieces=repacked_pieces,
    )
    if pulled_indices:
        work = _strip_pulled_pieces_from_donors(work, sheet_idx, pulled_indices)

    post_repack_score = _layout_score_for_sheet(
        work[sheet_idx],
        pieces,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    work = _apply_orthogonal_flip_if_better(
        work,
        sheet_idx,
        sheet,
        pieces,
        baseline_score=post_repack_score,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    return _apply_sheet_margin_shift(
        work,
        sheet_idx,
        pieces,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )


def _apply_orthogonal_flip_if_better(
    work: list[NestedSheet],
    sheet_idx: int,
    sheet: NestedSheet,
    pieces: list[Polygon],
    *,
    baseline_score: tuple[float, float, float, float, float],
    margin_mm: float,
    kerf_mm: float,
) -> list[NestedSheet]:
    flipped = _try_orthogonal_flip_improvements(
        work[sheet_idx].pieces,
        pieces,
        sheet.width_mm,
        sheet.height_mm,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    if flipped is None:
        return work

    candidate_score = _layout_score_for_pieces(
        flipped,
        pieces,
        sheet.width_mm,
        sheet.height_mm,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    if not _layout_better_than(baseline_score, candidate_score):
        return work

    work[sheet_idx] = NestedSheet(
        stock_sort_order=sheet.stock_sort_order,
        sheet_index=sheet.sheet_index,
        width_mm=sheet.width_mm,
        height_mm=sheet.height_mm,
        offset_x_mm=sheet.offset_x_mm,
        pieces=flipped,
    )
    return work


def _strip_pulled_pieces_from_donors(
    work: list[NestedSheet],
    sheet_idx: int,
    pulled_indices: set[int],
) -> list[NestedSheet]:
    for donor_idx in range(sheet_idx + 1, len(work)):
        donor = work[donor_idx]
        remaining = [row for row in donor.pieces if row.piece_index not in pulled_indices]
        work[donor_idx] = NestedSheet(
            stock_sort_order=donor.stock_sort_order,
            sheet_index=donor.sheet_index,
            width_mm=donor.width_mm,
            height_mm=donor.height_mm,
            offset_x_mm=donor.offset_x_mm,
            pieces=remaining,
        )
    return work


def _intra_repack_trials_for_sheet(
    sheet: NestedSheet,
    work: list[NestedSheet],
    sheet_idx: int,
    sheet_stocks: list[SheetStockSpec],
    deadline: float | None,
) -> list[list[PlacedPiece]]:
    trials: list[list[PlacedPiece]] = [list(sheet.pieces)]
    for donor_idx in range(sheet_idx + 1, len(work)):
        if _time_limit_exceeded(deadline):
            break
        donor = work[donor_idx]
        if not _sheets_allow_piece_transfer(sheet, donor, sheet_stocks):
            continue
        for donor_piece in donor.pieces:
            trials.append(list(sheet.pieces) + [donor_piece])
    return trials


def _pick_best_intra_repack_trial(
    trials: list[list[PlacedPiece]],
    sheet: NestedSheet,
    pieces: list[Polygon],
    *,
    baseline_score: tuple[float, float, float, float, float],
    baseline_count: int,
    margin_mm: float,
    kerf_mm: float,
    deadline: float | None,
) -> tuple[list[PlacedPiece], tuple[float, float, float, float, float]] | None:
    best_pieces: list[PlacedPiece] | None = None
    best_score: tuple[float, float, float, float, float] | None = None
    best_key: tuple[int, tuple[float, float, float, float, float], int] | None = None

    for trial_pieces in trials:
        if _time_limit_exceeded(deadline):
            return None
        if len(trial_pieces) < 2:
            continue
        repacked = _try_repack_intra_sheet(
            trial_pieces,
            pieces,
            sheet.width_mm,
            sheet.height_mm,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
        )
        if repacked is None:
            continue
        flipped = _try_orthogonal_flip_improvements(
            repacked,
            pieces,
            sheet.width_mm,
            sheet.height_mm,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
        )
        if flipped is not None:
            repacked = flipped
        candidate_score = _layout_score_for_pieces(
            repacked,
            pieces,
            sheet.width_mm,
            sheet.height_mm,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
        )
        pulled_trial = len(trial_pieces) > baseline_count
        if not _intra_repack_acceptable(
            baseline_score,
            candidate_score,
            baseline_count,
            len(repacked),
            pulled_extra=pulled_trial,
        ):
            continue
        merged_pull = pulled_trial and len(repacked) > baseline_count
        candidate_key = (1 if merged_pull else 0, _layout_rank_key(candidate_score), len(repacked))
        if best_key is None or candidate_key > best_key:
            best_pieces = repacked
            best_score = candidate_score
            best_key = candidate_key

    if best_pieces is None or best_score is None:
        return None
    if best_score == baseline_score and len(best_pieces) == baseline_count:
        return None
    return best_pieces, best_score


def _best_intra_repack_candidate(
    sheet: NestedSheet,
    work: list[NestedSheet],
    sheet_idx: int,
    pieces: list[Polygon],
    sheet_stocks: list[SheetStockSpec],
    *,
    baseline_score: tuple[float, float, float, float, float],
    baseline_count: int,
    margin_mm: float,
    kerf_mm: float,
    deadline: float | None,
) -> tuple[list[PlacedPiece], set[int]] | None:
    trials = _intra_repack_trials_for_sheet(sheet, work, sheet_idx, sheet_stocks, deadline)
    picked = _pick_best_intra_repack_trial(
        trials,
        sheet,
        pieces,
        baseline_score=baseline_score,
        baseline_count=baseline_count,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        deadline=deadline,
    )
    if picked is None:
        return None
    best_pieces, _best_score = picked
    pulled = {row.piece_index for row in best_pieces} - {row.piece_index for row in sheet.pieces}
    return best_pieces, pulled


def _intra_repack_acceptable(
    baseline_score: tuple[float, float, float, float, float],
    candidate_score: tuple[float, float, float, float, float],
    baseline_count: int,
    candidate_count: int,
    *,
    pulled_extra: bool = False,
) -> bool:
    if _layout_better_than(baseline_score, candidate_score):
        return True
    if pulled_extra and candidate_count > baseline_count:
        return True
    return candidate_count > baseline_count and candidate_score[0] >= baseline_score[0] - _EPS_MM


def _layout_score_for_sheet(
    sheet: NestedSheet,
    pieces: list[Polygon],
    *,
    margin_mm: float,
    kerf_mm: float,
) -> tuple[float, float, float, float, float]:
    placed = _occupied_polygons(sheet.pieces, pieces, kerf_mm)
    return _layout_score_from_polygons(sheet.width_mm, sheet.height_mm, margin_mm, placed)


def _layout_score_for_pieces(
    sheet_pieces: list[PlacedPiece],
    pieces: list[Polygon],
    bin_width: float,
    bin_height: float,
    *,
    margin_mm: float,
    kerf_mm: float,
) -> tuple[float, float, float, float, float]:
    placed = _occupied_polygons(sheet_pieces, pieces, kerf_mm)
    return _layout_score_from_polygons(bin_width, bin_height, margin_mm, placed)


def _layout_score_from_polygons(
    bin_width: float,
    bin_height: float,
    margin_mm: float,
    placed_polygons: list[Polygon],
) -> tuple[float, float, float, float, float]:
    free_area, footprint = score_sheet_layout(bin_width, bin_height, margin_mm, placed_polygons)
    if not placed_polygons:
        return (free_area, footprint, margin_mm, margin_mm, margin_mm)
    minx, miny, _maxx, layout_maxy = _layout_bounds(placed_polygons[0], placed_polygons[1:])
    return (free_area, footprint, layout_maxy, miny, minx)


def _try_repack_intra_sheet(
    sheet_pieces: list[PlacedPiece],
    pieces: list[Polygon],
    bin_width: float,
    bin_height: float,
    *,
    margin_mm: float,
    kerf_mm: float,
) -> list[PlacedPiece] | None:
    assert len(sheet_pieces) >= 2, "intra-sheet repack requires at least two pieces"
    indices = [placed.piece_index for placed in sheet_pieces]
    if len(indices) > _MAX_PIECES:
        return None

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
        return None

    ordered = [result.placements[local_idx] for local_idx in range(len(indices))]
    if not _batch_resolved_placements_are_valid(
        ordered,
        bin_width_mm=bin_width,
        bin_height_mm=bin_height,
        margin_mm=margin_mm,
    ):
        return None

    return [
        placed_piece_from_source(
            indices[local_idx],
            pieces[indices[local_idx]],
            ordered[local_idx].placement,
        )
        for local_idx in range(len(indices))
    ]


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

        merged, work = _inter_sheet_try_merge_donor(
            work,
            donor_idx,
            pieces,
            sheet_stocks,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
            deadline=deadline,
        )
        if merged:
            progress = True

        work = [sheet for sheet in work if sheet.pieces]

    return _reindex_sheet_offsets(work, sheet_gap_mm)


def _inter_sheet_try_merge_donor(
    work: list[NestedSheet],
    donor_idx: int,
    pieces: list[Polygon],
    sheet_stocks: list[SheetStockSpec],
    *,
    margin_mm: float,
    kerf_mm: float,
    deadline: float | None,
) -> tuple[bool, list[NestedSheet]]:
    donor = work[donor_idx]
    for target_idx in range(donor_idx):
        if _time_limit_exceeded(deadline):
            return False, work
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
        return True, work
    return False, work


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
            placed_piece_from_source(placed.piece_index, pieces[placed.piece_index], placement)
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
