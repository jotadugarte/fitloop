# [REQ-FIT-NEST-002] Shapely placement helpers (margin/obstacles); libnest2d batch via nest_sheet.
from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

from shapely.affinity import rotate, translate
from shapely.geometry import Polygon, box
from shapely.ops import unary_union

ROTATION_STEP_DEG = 5
_MAX_ROTATION_STEPS = 360 // ROTATION_STEP_DEG
_COMPACT_STEP_MM = 2.0
_MAX_COMPACT_STEPS = 200
_FREE_AREA_POLYGON_LIMIT = 10
_EPS_MM = 1e-6


@dataclass(frozen=True)
class Placement:
    """Translation (x, y) after rotation so the piece AABB sits at margin inside the sheet."""

    x: float
    y: float
    rotation_deg: float


def placed_polygon(piece: Polygon, placement: Placement) -> Polygon:
    rotated = rotate(piece, placement.rotation_deg, origin="centroid")
    return translate(rotated, xoff=placement.x, yoff=placement.y)


def place_with_rotation(
    piece: Polygon,
    bin_width: float,
    bin_height: float,
    *,
    margin: float,
    obstacles: list[Polygon] | None = None,
) -> Placement | None:
    occupied = obstacles or []
    base_x_candidates, base_y_candidates = _anchor_candidates(occupied, margin)
    occupied_union = unary_union(occupied) if occupied else None

    best: Placement | None = None
    best_score: tuple[float, float, float, float, float] | None = None
    best_footprint = float("inf")

    for step in range(_MAX_ROTATION_STEPS):
        angle = float(step * ROTATION_STEP_DEG)
        candidate = _best_placement_for_angle(
            piece,
            angle,
            bin_width,
            bin_height,
            margin=margin,
            occupied=occupied,
            base_x_candidates=base_x_candidates,
            base_y_candidates=base_y_candidates,
            occupied_union=occupied_union,
            best_footprint=best_footprint,
        )
        if candidate is None:
            continue
        placement, score, footprint = candidate
        if best_score is None or score < best_score:
            best_footprint = footprint
            best = placement
            best_score = score

    return best


def _best_placement_for_angle(
    piece: Polygon,
    angle: float,
    bin_width: float,
    bin_height: float,
    *,
    margin: float,
    occupied: list[Polygon],
    base_x_candidates: set[float],
    base_y_candidates: set[float],
    occupied_union: Polygon | None,
    best_footprint: float,
) -> tuple[Placement, tuple[float, float, float, float, float], float] | None:
    rotated = rotate(piece, angle, origin="centroid")
    minx, miny, maxx, maxy = rotated.bounds
    width = maxx - minx
    height = maxy - miny

    if width + 2 * margin > bin_width or height + 2 * margin > bin_height:
        return None

    x_candidates = _x_candidates(base_x_candidates, occupied, bin_width, width, margin)
    y_candidates = _y_candidates(base_y_candidates, occupied, bin_height, height, margin)

    best: Placement | None = None
    best_score: tuple[float, float, float, float, float] | None = None
    angle_best_footprint = best_footprint

    for y_anchor in sorted(y_candidates):
        for x_anchor in sorted(x_candidates):
            trial = _try_anchor_placement(
                rotated,
                minx,
                miny,
                angle,
                x_anchor,
                y_anchor,
                bin_width,
                bin_height,
                margin=margin,
                occupied=occupied,
                occupied_union=occupied_union,
                footprint_cap=angle_best_footprint,
            )
            if trial is None:
                continue
            placement, score, footprint = trial
            if best_score is None or score < best_score:
                angle_best_footprint = footprint
                best = placement
                best_score = score

    if best is None or best_score is None:
        return None
    return best, best_score, angle_best_footprint


def _try_anchor_placement(
    rotated: Polygon,
    minx: float,
    miny: float,
    angle: float,
    x_anchor: float,
    y_anchor: float,
    bin_width: float,
    bin_height: float,
    *,
    margin: float,
    occupied: list[Polygon],
    occupied_union: Polygon | None,
    footprint_cap: float,
) -> tuple[Placement, tuple[float, float, float, float, float], float] | None:
    dx = x_anchor - minx
    dy = y_anchor - miny
    placed = translate(rotated, xoff=dx, yoff=dy)
    if not _fits_bin(placed, bin_width, bin_height, margin=margin):
        return None
    if _overlaps_any(placed, occupied):
        return None

    compacted = _compact_toward_origin(
        placed, bin_width, bin_height, margin=margin, obstacles=occupied
    )
    if not _fits_bin(compacted, bin_width, bin_height, margin=margin):
        return None
    if _overlaps_any(compacted, occupied):
        return None

    _lminx, _lminy, layout_maxx, layout_maxy = _layout_bounds(compacted, occupied)
    footprint = (layout_maxx - margin) * (layout_maxy - margin)
    if footprint > footprint_cap + _EPS_MM:
        return None

    score = _placement_score(
        compacted,
        bin_width,
        bin_height,
        margin=margin,
        footprint=footprint,
        layout_maxx=layout_maxx,
        layout_maxy=layout_maxy,
        occupied_union=occupied_union,
        obstacle_count=len(occupied) + 1,
    )
    cminx, cminy, _, _ = compacted.bounds
    placement = Placement(cminx - minx, cminy - miny, angle)
    return placement, score, footprint


def _x_candidates(
    base: set[float],
    occupied: list[Polygon],
    bin_width: float,
    width: float,
    margin: float,
) -> set[float]:
    x_candidates = set(base)
    x_candidates.add(bin_width - width - margin)
    for obstacle in occupied:
        o_minx, _, o_maxx, _o_maxy = obstacle.bounds
        if o_minx - width >= margin:
            x_candidates.add(o_minx - width)
        x_candidates.add(o_maxx)
    return x_candidates


def _y_candidates(
    base: set[float],
    occupied: list[Polygon],
    bin_height: float,
    height: float,
    margin: float,
) -> set[float]:
    y_candidates = set(base)
    y_candidates.add(bin_height - height - margin)
    for obstacle in occupied:
        _, o_miny, _, o_maxy = obstacle.bounds
        y_candidates.add(o_miny)
        y_candidates.add(o_maxy)
        if o_maxy - height >= margin:
            y_candidates.add(o_maxy - height)
    return y_candidates


def _anchor_candidates(occupied: list[Polygon], margin: float) -> tuple[set[float], set[float]]:
    x_candidates = {margin}
    y_candidates = {margin}
    for obstacle in occupied:
        o_minx, o_miny, o_maxx, o_maxy = obstacle.bounds
        x_candidates.add(o_maxx)
        x_candidates.add(o_minx)
        y_candidates.add(o_miny)
        y_candidates.add(o_maxy)
    return x_candidates, y_candidates


def _placement_score(
    placed: Polygon,
    bin_width: float,
    bin_height: float,
    *,
    margin: float,
    footprint: float,
    layout_maxx: float,
    layout_maxy: float,
    occupied_union: Polygon | None,
    obstacle_count: int,
) -> tuple[float, float, float, float, float]:
    free_area = _largest_continuous_free_area(
        bin_width,
        bin_height,
        margin,
        layout_maxx,
        layout_maxy,
        placed,
        occupied_union,
        obstacle_count,
    )
    minx, miny, _, _ = placed.bounds
    return (footprint, -free_area, layout_maxy, miny, minx)


def _layout_bounds(placed: Polygon, occupied: list[Polygon]) -> tuple[float, float, float, float]:
    minx, miny, maxx, maxy = placed.bounds
    for obstacle in occupied:
        o_minx, o_miny, o_maxx, o_maxy = obstacle.bounds
        minx = min(minx, o_minx)
        miny = min(miny, o_miny)
        maxx = max(maxx, o_maxx)
        maxy = max(maxy, o_maxy)
    return minx, miny, maxx, maxy


def _largest_continuous_free_area(
    bin_width: float,
    bin_height: float,
    margin: float,
    layout_maxx: float,
    layout_maxy: float,
    placed: Polygon,
    occupied_union: Polygon | None,
    obstacle_count: int,
) -> float:
    strip_free = _free_strip_area_estimate(bin_width, bin_height, margin, layout_maxx, layout_maxy)
    if obstacle_count > _FREE_AREA_POLYGON_LIMIT or occupied_union is None:
        return strip_free

    sheet = box(margin, margin, bin_width - margin, bin_height - margin)
    combined = occupied_union.union(placed)
    free = sheet.difference(combined)
    if free.is_empty:
        return strip_free
    if free.geom_type == "Polygon":
        return max(strip_free, float(free.area))
    if free.geom_type == "MultiPolygon":
        return max(strip_free, float(max(part.area for part in free.geoms)))
    return strip_free


def _free_strip_area_estimate(
    bin_width: float,
    bin_height: float,
    margin: float,
    layout_maxx: float,
    layout_maxy: float,
) -> float:
    usable_h = bin_height - 2 * margin
    right_w = max(bin_width - margin - layout_maxx, 0.0)
    top_h = max(bin_height - margin - layout_maxy, 0.0)
    layout_w = max(layout_maxx - margin, 0.0)
    return max(right_w * usable_h, layout_w * top_h, 0.0)


def _compact_toward_origin(
    placed: Polygon,
    bin_width: float,
    bin_height: float,
    *,
    margin: float,
    obstacles: list[Polygon],
) -> Polygon:
    current = _slide_axis(
        placed,
        axis="y",
        delta=-_COMPACT_STEP_MM,
        bin_width=bin_width,
        bin_height=bin_height,
        margin=margin,
        obstacles=obstacles,
    )
    return _slide_axis(
        current,
        axis="x",
        delta=-_COMPACT_STEP_MM,
        bin_width=bin_width,
        bin_height=bin_height,
        margin=margin,
        obstacles=obstacles,
    )


def _slide_axis(
    placed: Polygon,
    *,
    axis: Literal["x", "y"],
    delta: float,
    bin_width: float,
    bin_height: float,
    margin: float,
    obstacles: list[Polygon],
) -> Polygon:
    assert axis in {"x", "y"}
    current = placed
    for _ in range(_MAX_COMPACT_STEPS):
        xoff = delta if axis == "x" else 0.0
        yoff = delta if axis == "y" else 0.0
        candidate = translate(current, xoff=xoff, yoff=yoff)
        if not _fits_bin(candidate, bin_width, bin_height, margin=margin):
            break
        if _overlaps_any(candidate, obstacles):
            break
        current = candidate
    return current


def _fits_bin(placed: Polygon, bin_width: float, bin_height: float, *, margin: float) -> bool:
    minx, miny, maxx, maxy = placed.bounds
    return (
        minx >= margin - _EPS_MM
        and miny >= margin - _EPS_MM
        and maxx <= bin_width - margin + _EPS_MM
        and maxy <= bin_height - margin + _EPS_MM
    )


def _overlaps_any(placed: Polygon, obstacles: list[Polygon]) -> bool:
    for obstacle in obstacles:
        if placed.intersects(obstacle) and not placed.touches(obstacle):
            return True
    return False
