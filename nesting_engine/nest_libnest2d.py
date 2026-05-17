# [REQ-FIT-NEST-001] libnest2d binding spike via python-libnest2d (pynest2d).
from __future__ import annotations

import math
from dataclasses import dataclass

from pynest2d import Box, Item, NfpConfig, Point, nest
from shapely.geometry import Polygon
from shapely.geometry.polygon import orient

_BINDING_NAME = "python-libnest2d 0.1.3 (pynest2d)"
_MAX_PIECES = 64
_MIN_BIN_MM = 1.0


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
    config.rotations = [float(step) for step in range(0, 360, 15)]
    return config


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
