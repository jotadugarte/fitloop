# [REQ-FIT-DXF-002] Apply placement transform to auxiliary decorations with the primary piece.
from __future__ import annotations

from shapely.affinity import rotate, translate
from shapely.geometry import LineString, Point, Polygon

from nesting_engine.composite_extract import DecorationEntity
from nesting_engine.nest_placement import Placement


def transform_decorations(
    decorations: list[DecorationEntity],
    primary: Polygon,
    placement: Placement,
) -> list[DecorationEntity]:
    assert isinstance(primary, Polygon), "primary must be a polygon"
    if not decorations:
        return []

    return [
        _transform_decoration(decoration, primary, placement)
        for decoration in decorations
    ]


def _transform_decoration(
    decoration: DecorationEntity,
    primary: Polygon,
    placement: Placement,
) -> DecorationEntity:
    if decoration.geometry_type == "line":
        return _transform_line_decoration(decoration, primary, placement)
    if decoration.geometry_type in {"text", "insert"}:
        return _transform_point_decoration(decoration, primary, placement)
    return decoration


def _transform_line_decoration(
    decoration: DecorationEntity,
    primary: Polygon,
    placement: Placement,
) -> DecorationEntity:
    line = LineString(decoration.payload["coordinates"])
    placed = _place_geometry(line, primary, placement)
    return DecorationEntity(
        layer_name=decoration.layer_name,
        geometry_type=decoration.geometry_type,
        payload={"coordinates": list(placed.coords)},
    )


def _transform_point_decoration(
    decoration: DecorationEntity,
    primary: Polygon,
    placement: Placement,
) -> DecorationEntity:
    insert = decoration.payload["insert"]
    point = Point(float(insert[0]), float(insert[1]))
    placed = _place_geometry(point, primary, placement)
    payload = dict(decoration.payload)
    payload["insert"] = [float(placed.x), float(placed.y)]
    return DecorationEntity(
        layer_name=decoration.layer_name,
        geometry_type=decoration.geometry_type,
        payload=payload,
    )


def _place_geometry(geometry: LineString | Point, primary: Polygon, placement: Placement):
    rotated = rotate(geometry, placement.rotation_deg, origin=primary.centroid)
    return translate(rotated, xoff=placement.x, yoff=placement.y)
