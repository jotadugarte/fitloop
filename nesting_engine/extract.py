# [REQ-FIT-EXT-001] Extract closed contours on a selected layer from DXF input.
from __future__ import annotations

from pathlib import Path

import ezdxf
from ezdxf.entities import Circle, LWPolyline, Polyline
from shapely.geometry import Polygon
from shapely.validation import make_valid

_MAX_ENTITIES = 100_000


def extract_closed_contours(dxf_path: Path | str, layer_name: str) -> list[Polygon]:
    """Return valid Shapely polygons for closed contours on the given layer."""
    assert layer_name and layer_name.strip(), "layer_name is required"

    path = Path(dxf_path)
    assert path.is_file(), f"DXF file not found: {path}"

    doc = ezdxf.readfile(path)
    contours: list[Polygon] = []
    scanned = 0

    for entity in doc.modelspace():
        scanned += 1
        assert scanned <= _MAX_ENTITIES, "DXF entity limit exceeded"

        if entity.dxf.layer != layer_name:
            continue

        polygon = _closed_contour_polygon(entity)
        if polygon is not None:
            contours.append(polygon)

    assert isinstance(contours, list)
    return contours


def _closed_contour_polygon(entity: object) -> Polygon | None:
    if isinstance(entity, LWPolyline):
        return _lwpolyline_polygon(entity)
    if isinstance(entity, Polyline) and entity.is_closed:
        return _polyline_polygon(entity)
    if isinstance(entity, Circle):
        return _circle_polygon(entity)
    return None


def _lwpolyline_polygon(entity: LWPolyline) -> Polygon | None:
    if not entity.closed:
        return None
    points = [(float(x), float(y)) for x, y, *_ in entity.get_points("xy")]
    return _polygon_from_points(points)


def _polyline_polygon(entity: Polyline) -> Polygon | None:
    points = [(float(v.dxf.location.x), float(v.dxf.location.y)) for v in entity.vertices]
    return _polygon_from_points(points)


def _circle_polygon(entity: Circle) -> Polygon | None:
    center = entity.dxf.center
    radius = float(entity.dxf.radius)
    assert radius > 0, "circle radius must be positive"
    return Polygon.from_bounds(
        center.x - radius,
        center.y - radius,
        center.x + radius,
        center.y + radius,
    )


def _polygon_from_points(points: list[tuple[float, float]]) -> Polygon | None:
    if len(points) < 3:
        return None

    polygon = Polygon(points)
    if not polygon.is_valid:
        polygon = make_valid(polygon)
    if polygon.is_empty or polygon.area <= 0:
        return None

    assert polygon.is_valid
    return polygon
