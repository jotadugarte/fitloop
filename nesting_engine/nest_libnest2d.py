# [REQ-FIT-NEST-001] libnest2d binding spike via python-libnest2d (pynest2d).
from __future__ import annotations

import math
from dataclasses import dataclass

from pynest2d import BLConfig, Box, Item, NfpConfig, Point, nest, nest_blp
from shapely.affinity import rotate, translate
from shapely.geometry import Polygon
from shapely.geometry.polygon import orient

from nesting_engine.nest_bin import _apply_kerf
from nesting_engine.nest_spike import Placement

_BINDING_NAME = "python-libnest2d 0.1.3 (pynest2d)"
_MAX_PIECES = 64
_MIN_BIN_MM = 1.0
_ROTATION_STEPS_DEG = tuple(float(step) for step in range(0, 360, 15))
_PLACEMENT_AREA_TOLERANCE_MM2 = 150.0
_MAX_ANGLE_SEARCH_DEG = 360


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
