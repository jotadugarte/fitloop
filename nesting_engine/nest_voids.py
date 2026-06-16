# [REQ-FIT-NEST-002] Void rectangle detection on nested sheets.
from __future__ import annotations

from dataclasses import dataclass

from shapely.geometry import Polygon, box
from shapely.geometry.base import BaseGeometry

from nesting_engine.nest_placement import placed_polygon, sheet_occupancy_union
from nesting_engine.nest_types import NestedSheet


@dataclass(frozen=True)
class PlaceableRect:
    min_x: float
    min_y: float
    width: float
    height: float

    @property
    def area(self) -> float:
        return self.width * self.height


def find_placeable_rects(
    sheet: NestedSheet,
    pieces: list[Polygon],
    *,
    margin_mm: float,
    min_width_mm: float,
    min_height_mm: float,
) -> list[PlaceableRect]:
    assert min_width_mm > 0.0 and min_height_mm > 0.0
    usable = box(
        margin_mm,
        margin_mm,
        sheet.width_mm - margin_mm,
        sheet.height_mm - margin_mm,
    )
    placed = [
        placed_polygon(pieces[row.piece_index], row.placement) for row in sheet.pieces
    ]
    occupied = sheet_occupancy_union(placed)
    if occupied is None or occupied.is_empty:
        rect = _rect_from_bounds(usable.bounds, min_width_mm, min_height_mm)
        return [rect] if rect is not None else []

    free = usable.difference(occupied)
    return _rects_from_free_geometry(free, min_width_mm, min_height_mm)


def _rect_from_bounds(
    bounds: tuple[float, float, float, float],
    min_width_mm: float,
    min_height_mm: float,
) -> PlaceableRect | None:
    minx, miny, maxx, maxy = bounds
    width = maxx - minx
    height = maxy - miny
    if width < min_width_mm or height < min_height_mm:
        return None
    return PlaceableRect(min_x=minx, min_y=miny, width=width, height=height)


def _rects_from_free_geometry(
    geometry: BaseGeometry,
    min_width_mm: float,
    min_height_mm: float,
) -> list[PlaceableRect]:
    rects: list[PlaceableRect] = []
    if geometry.is_empty:
        return rects
    if geometry.geom_type == "Polygon":
        rect = _maximal_axis_rect_in_polygon(geometry, min_width_mm, min_height_mm)
        if rect is not None:
            rects.append(rect)
        return rects
    if geometry.geom_type == "MultiPolygon":
        for part in geometry.geoms:
            rects.extend(_rects_from_free_geometry(part, min_width_mm, min_height_mm))
        rects.sort(key=lambda row: row.area, reverse=True)
        return rects
    envelope = geometry.envelope
    if envelope.geom_type != "Polygon":
        return rects
    rect = _maximal_axis_rect_in_polygon(envelope, min_width_mm, min_height_mm)
    if rect is not None:
        rects.append(rect)
    return rects


def _maximal_axis_rect_in_polygon(
    polygon: Polygon,
    min_width_mm: float,
    min_height_mm: float,
) -> PlaceableRect | None:
    minx, miny, maxx, maxy = polygon.bounds
    width = maxx - minx
    height = maxy - miny
    if width < min_width_mm or height < min_height_mm:
        return None
    candidate = box(minx, miny, maxx, maxy)
    if not polygon.contains(candidate):
        candidate = polygon.envelope
        minx, miny, maxx, maxy = candidate.bounds
        width = maxx - minx
        height = maxy - miny
        if width < min_width_mm or height < min_height_mm:
            return None
    return PlaceableRect(min_x=minx, min_y=miny, width=width, height=height)
