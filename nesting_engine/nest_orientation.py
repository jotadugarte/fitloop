# [REQ-FIT-NEST-002] Orientation profiles for multi-start nesting seeds.
from __future__ import annotations

from shapely.affinity import rotate
from shapely.geometry import Polygon

from nesting_engine.nest_geometry_classify import is_orthogonal_for_cardinal_nesting
from nesting_engine.piece_loader import piece_polygon

_ORIENTATION_PROFILES = frozenset(
    {
        "as_extracted",
        "cardinal_90",
        "bar_parallel_long_edge",
    }
)


def apply_orientation_profile(
    pieces: list[Polygon],
    profile: str,
    *,
    sheet_width_mm: float,
    sheet_height_mm: float,
) -> list[Polygon]:
    assert profile in _ORIENTATION_PROFILES, f"unknown orientation profile: {profile}"
    if profile == "as_extracted":
        return pieces
    if profile == "cardinal_90":
        return [_rotate_cardinal_90(piece) for piece in pieces]
    return [_bar_parallel_to_long_edge(piece, sheet_width_mm, sheet_height_mm) for piece in pieces]


def orientation_profiles() -> tuple[str, ...]:
    return tuple(sorted(_ORIENTATION_PROFILES))


def _rotate_cardinal_90(piece: Polygon) -> Polygon:
    geometry = piece_polygon(piece)
    if not is_orthogonal_for_cardinal_nesting(geometry):
        return piece
    centroid = geometry.centroid
    return rotate(geometry, 90.0, origin=(centroid.x, centroid.y))


def _bar_parallel_to_long_edge(
    piece: Polygon,
    sheet_width_mm: float,
    sheet_height_mm: float,
) -> Polygon:
    geometry = piece_polygon(piece)
    minx, miny, maxx, maxy = geometry.bounds
    width = maxx - minx
    height = maxy - miny
    if width <= 0.0 or height <= 0.0:
        return piece
    aspect = max(width, height) / min(width, height)
    if aspect < 3.0:
        return piece
    sheet_long_horizontal = sheet_width_mm >= sheet_height_mm
    bar_horizontal = width >= height
    if sheet_long_horizontal == bar_horizontal:
        return piece
    centroid = geometry.centroid
    return rotate(geometry, 90.0, origin=(centroid.x, centroid.y))
