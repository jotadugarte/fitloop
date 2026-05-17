# [REQ-FIT-NEST-001] P0 spike: hole-aware polygons, any-angle rotation check, bin placement.
from __future__ import annotations

from dataclasses import dataclass

from shapely.affinity import rotate, translate
from shapely.geometry import Polygon

_ROTATION_STEP_DEG = 15
_MAX_ROTATION_STEPS = 24  # 0..345 — bounded loop per CbC


@dataclass(frozen=True)
class NestingCapabilities:
    """Documented MVP nesting targets (see ADR 0001)."""

    library: str
    supports_holes: bool
    supports_any_angle_rotation: bool
    spike_only: bool


@dataclass(frozen=True)
class Placement:
    """Translation (x, y) to apply after rotation so the piece AABB sits at margin inside the sheet."""

    x: float
    y: float
    rotation_deg: float


@dataclass(frozen=True)
class SpikeNestResult:
    placements: list[Placement]
    all_placed: bool


def capabilities() -> NestingCapabilities:
    return NestingCapabilities(
        library="libnest2d (target); shapely rotation sweep (P0 spike)",
        supports_holes=True,
        supports_any_angle_rotation=True,
        spike_only=True,
    )


def run_spike_nest(
    pieces: list[Polygon],
    bin_width: float,
    bin_height: float,
    *,
    margin: float = 1.0,
) -> SpikeNestResult:
    assert bin_width > 0 and bin_height > 0, "bin dimensions must be positive"
    assert margin >= 0, "margin must be non-negative"
    assert pieces, "at least one piece required"

    placements: list[Placement] = []

    for piece in pieces:
        assert isinstance(piece, Polygon), "each piece must be a Shapely Polygon"
        placement = _place_with_rotation(piece, bin_width, bin_height, margin=margin)
        if placement is None:
            return SpikeNestResult(placements, False)
        placements.append(placement)

    assert len(placements) == len(pieces)
    return SpikeNestResult(placements, True)


def _place_with_rotation(
    piece: Polygon,
    bin_width: float,
    bin_height: float,
    *,
    margin: float,
    obstacles: list[Polygon] | None = None,
) -> Placement | None:
    occupied = obstacles or []
    x_candidates = {margin}
    y_candidates = {margin}
    for obstacle in occupied:
        minx, miny, maxx, maxy = obstacle.bounds
        x_candidates.add(maxx + margin)
        y_candidates.add(miny)

    for step in range(_MAX_ROTATION_STEPS):
        angle = float(step * _ROTATION_STEP_DEG)
        rotated = rotate(piece, angle, origin="centroid")
        minx, miny, maxx, maxy = rotated.bounds
        width = maxx - minx
        height = maxy - miny

        if width + 2 * margin > bin_width or height + 2 * margin > bin_height:
            continue

        for y_anchor in sorted(y_candidates):
            for x_anchor in sorted(x_candidates):
                dx = x_anchor - minx
                dy = y_anchor - miny
                placed = translate(rotated, xoff=dx, yoff=dy)
                if not _fits_bin(placed, bin_width, bin_height, margin=margin):
                    continue
                if _overlaps_any(placed, occupied):
                    continue
                return Placement(dx, dy, angle)

    return None


def _fits_bin(placed: Polygon, bin_width: float, bin_height: float, *, margin: float) -> bool:
    minx, miny, maxx, maxy = placed.bounds
    return (
        minx >= margin - 1e-6
        and miny >= margin - 1e-6
        and maxx <= bin_width - margin + 1e-6
        and maxy <= bin_height - margin + 1e-6
    )


def _overlaps_any(placed: Polygon, obstacles: list[Polygon]) -> bool:
    for obstacle in obstacles:
        if placed.intersects(obstacle) and not placed.touches(obstacle):
            return True
    return False


def placed_polygon(piece: Polygon, placement: Placement) -> Polygon:
    rotated = rotate(piece, placement.rotation_deg, origin="centroid")
    return translate(rotated, xoff=placement.x, yoff=placement.y)
