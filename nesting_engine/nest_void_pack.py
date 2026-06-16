# [REQ-FIT-NEST-002] Pack thin strip pieces into detected sheet voids.
from __future__ import annotations

import time

from shapely.geometry import Polygon

from nesting_engine.nest_objective import score_nested_layout
from nesting_engine.nest_geometry_classify import ORTHO_ROTATIONS_DEG
from nesting_engine.nest_placement import (
    place_with_rotation,
    placed_polygon,
    polygons_overlap_significantly,
)
from nesting_engine.nest_types import NestedSheet, PlacedPiece, apply_kerf
from nesting_engine.piece_loader import piece_polygon, placed_piece_from_source
from nesting_engine.nest_voids import PlaceableRect, find_placeable_rects

_STRIP_ASPECT_RATIO = 3.0
_MAX_STRIP_AREA_MM2 = 250_000.0


def void_pack_sheets(
    sheets: list[NestedSheet],
    pieces: list[Polygon],
    *,
    margin_mm: float,
    kerf_mm: float,
    deadline: float | None = None,
) -> list[NestedSheet]:
    from nesting_engine.nest_libnest2d import multi_bin_layout_has_significant_overlaps

    if not sheets:
        return sheets
    baseline = score_nested_layout(sheets, pieces, margin_mm=margin_mm)
    improved = [
        _void_pack_one_sheet(sheet, pieces, margin_mm=margin_mm, kerf_mm=kerf_mm, deadline=deadline)
        for sheet in sheets
    ]
    if multi_bin_layout_has_significant_overlaps(improved, pieces, kerf_mm=kerf_mm):
        return sheets
    candidate_score = score_nested_layout(improved, pieces, margin_mm=margin_mm)
    if candidate_score.total_waste_mm2 <= baseline.total_waste_mm2:
        return improved
    return sheets


def _void_pack_one_sheet(
    sheet: NestedSheet,
    pieces: list[Polygon],
    *,
    margin_mm: float,
    kerf_mm: float,
    deadline: float | None,
) -> NestedSheet:
    if _time_limit_exceeded(deadline):
        return sheet

    placed_indices = {row.piece_index for row in sheet.pieces}
    strip_candidates = [
        index
        for index in range(len(pieces))
        if index not in placed_indices and _is_strip_piece(pieces[index])
    ]
    if not strip_candidates:
        return sheet

    work_pieces = list(sheet.pieces)
    occupied = [
        apply_kerf(placed_polygon(pieces[row.piece_index], row.placement), kerf_mm)
        for row in work_pieces
    ]
    for index in strip_candidates:
        if _time_limit_exceeded(deadline):
            break
        geometry = piece_polygon(pieces[index])
        min_dim = min(geometry.bounds[2] - geometry.bounds[0], geometry.bounds[3] - geometry.bounds[1])
        rects = find_placeable_rects(
            NestedSheet(
                stock_sort_order=sheet.stock_sort_order,
                sheet_index=sheet.sheet_index,
                width_mm=sheet.width_mm,
                height_mm=sheet.height_mm,
                offset_x_mm=sheet.offset_x_mm,
                pieces=work_pieces,
            ),
            pieces,
            margin_mm=margin_mm,
            min_width_mm=min_dim,
            min_height_mm=min_dim,
        )
        placement = _best_strip_placement_in_rects(
            pieces[index],
            rects,
            occupied,
            sheet.width_mm,
            sheet.height_mm,
            margin_mm=margin_mm,
        )
        if placement is None:
            continue
        world = placed_polygon(pieces[index], placement)
        if any(polygons_overlap_significantly(world, obstacle) for obstacle in occupied):
            continue
        work_pieces.append(placed_piece_from_source(index, pieces[index], placement))
        occupied.append(world)

    return NestedSheet(
        stock_sort_order=sheet.stock_sort_order,
        sheet_index=sheet.sheet_index,
        width_mm=sheet.width_mm,
        height_mm=sheet.height_mm,
        offset_x_mm=sheet.offset_x_mm,
        pieces=work_pieces,
    )


def _is_strip_piece(piece: Polygon) -> bool:
    geometry = piece_polygon(piece)
    minx, miny, maxx, maxy = geometry.bounds
    width = maxx - minx
    height = maxy - miny
    if width <= 0.0 or height <= 0.0:
        return False
    if geometry.area > _MAX_STRIP_AREA_MM2:
        return False
    return max(width, height) / min(width, height) >= _STRIP_ASPECT_RATIO


def _best_strip_placement_in_rects(
    piece: Polygon,
    rects: list[PlaceableRect],
    occupied: list[Polygon],
    bin_width: float,
    bin_height: float,
    *,
    margin_mm: float,
):
    best = None
    best_key = None
    for rect in rects:
        placement = place_with_rotation(
            piece,
            bin_width,
            bin_height,
            margin=margin_mm,
            obstacles=occupied,
            allowed_rotations=list(ORTHO_ROTATIONS_DEG),
        )
        if placement is None:
            continue
        world = placed_polygon(piece, placement)
        minx, miny, maxx, maxy = world.bounds
        if minx < rect.min_x - 1e-6 or miny < rect.min_y - 1e-6:
            continue
        if maxx > rect.min_x + rect.width + 1e-6 or maxy > rect.min_y + rect.height + 1e-6:
            continue
        key = (rect.area, -maxy, -maxx)
        if best_key is None or key > best_key:
            best = placement
            best_key = key
    return best


def _time_limit_exceeded(deadline: float | None) -> bool:
    return deadline is not None and time.monotonic() >= deadline
