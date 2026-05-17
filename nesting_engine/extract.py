# [REQ-FIT-EXT-001] [REQ-FIT-EXT-002] Extract closed contours and INSERT pieces on a layer.
from __future__ import annotations

from pathlib import Path

import ezdxf
from ezdxf.entities import Circle, Insert, LWPolyline, Polyline
from ezdxf.math import Matrix44, Vec3
from ezdxf.path import make_path
from shapely.geometry import Polygon
from shapely.ops import unary_union
from shapely.validation import make_valid

_MAX_ENTITIES = 100_000
_DEFAULT_MAX_BLOCK_DEPTH = 8


def extract_closed_contours(
    dxf_path: Path | str,
    layer_name: str,
    *,
    curve_tolerance_mm: float = 0.1,
    max_block_depth: int = _DEFAULT_MAX_BLOCK_DEPTH,
    warnings: list[str] | None = None,
) -> list[Polygon]:
    """Return piece polygons: loose contours plus one polygon per INSERT on the layer."""
    assert layer_name and layer_name.strip(), "layer_name is required"
    assert curve_tolerance_mm > 0, "curve_tolerance_mm must be positive"
    assert max_block_depth >= 1, "max_block_depth must be at least 1"

    path = Path(dxf_path)
    assert path.is_file(), f"DXF file not found: {path}"

    report: list[str] = warnings if warnings is not None else []
    doc = ezdxf.readfile(path)
    contours: list[Polygon] = []
    scanned = 0

    for entity in doc.modelspace():
        scanned += 1
        assert scanned <= _MAX_ENTITIES, "DXF entity limit exceeded"

        if entity.dxf.layer != layer_name:
            continue

        if isinstance(entity, Insert):
            piece = _piece_from_insert(
                doc,
                entity,
                curve_tolerance_mm=curve_tolerance_mm,
                max_block_depth=max_block_depth,
                warnings=report,
            )
            if piece is not None:
                contours.append(piece)
            continue

        polygon = _closed_contour_polygon(entity, curve_tolerance_mm=curve_tolerance_mm)
        if polygon is not None:
            contours.append(polygon)

    assert isinstance(contours, list)
    return contours


def _piece_from_insert(
    doc: ezdxf.document.Drawing,
    insert: Insert,
    *,
    curve_tolerance_mm: float,
    max_block_depth: int,
    warnings: list[str],
) -> Polygon | None:
    block_polys = _polygons_from_block(
        doc,
        insert.dxf.name,
        insert.matrix44(),
        depth=1,
        curve_tolerance_mm=curve_tolerance_mm,
        max_block_depth=max_block_depth,
        warnings=warnings,
    )
    return _merge_piece_polygons(block_polys)


def _polygons_from_block(
    doc: ezdxf.document.Drawing,
    block_name: str,
    transform: Matrix44,
    *,
    depth: int,
    curve_tolerance_mm: float,
    max_block_depth: int,
    warnings: list[str],
) -> list[Polygon]:
    if depth > max_block_depth:
        warnings.append(f"Block nesting depth exceeded limit ({max_block_depth})")
        return []

    block = doc.blocks.get(block_name)
    if block is None:
        warnings.append(f"Missing block definition: {block_name}")
        return []

    polygons: list[Polygon] = []
    for entity in block:
        if isinstance(entity, Insert):
            nested = entity.matrix44()
            combined = transform @ nested
            polygons.extend(
                _polygons_from_block(
                    doc,
                    entity.dxf.name,
                    combined,
                    depth=depth + 1,
                    curve_tolerance_mm=curve_tolerance_mm,
                    max_block_depth=max_block_depth,
                    warnings=warnings,
                )
            )
            continue

        polygon = _closed_contour_polygon(entity, curve_tolerance_mm=curve_tolerance_mm)
        if polygon is not None:
            polygons.append(_transform_polygon(polygon, transform))

    return polygons


def _merge_piece_polygons(polygons: list[Polygon]) -> Polygon | None:
    if not polygons:
        return None

    merged = unary_union(polygons)
    if merged.geom_type == "Polygon":
        return merged if not merged.is_empty and merged.area > 0 else None
    if merged.geom_type == "MultiPolygon":
        largest = max(merged.geoms, key=lambda geom: geom.area)
        return largest if largest.area > 0 else None
    return None


def _closed_contour_polygon(entity: object, *, curve_tolerance_mm: float) -> Polygon | None:
    if isinstance(entity, LWPolyline):
        return _lwpolyline_polygon(entity)
    if isinstance(entity, Polyline) and entity.is_closed:
        return _polyline_polygon(entity)
    if isinstance(entity, Circle):
        return _circle_polygon(entity, curve_tolerance_mm=curve_tolerance_mm)
    if hasattr(entity, "dxftype") and entity.dxftype() in {"ARC", "ELLIPSE", "SPLINE"}:
        return _flattened_path_polygon(entity, curve_tolerance_mm=curve_tolerance_mm)
    return None


def _flattened_path_polygon(entity: object, *, curve_tolerance_mm: float) -> Polygon | None:
    path = make_path(entity)
    points = [(float(v.x), float(v.y)) for v in path.flattening(curve_tolerance_mm)]
    if len(points) >= 2 and points[0] != points[-1]:
        points.append(points[0])
    return _polygon_from_points(points)


def _lwpolyline_polygon(entity: LWPolyline) -> Polygon | None:
    if not entity.closed:
        return None
    points = [(float(x), float(y)) for x, y, *_ in entity.get_points("xy")]
    return _polygon_from_points(points)


def _polyline_polygon(entity: Polyline) -> Polygon | None:
    points = [(float(v.dxf.location.x), float(v.dxf.location.y)) for v in entity.vertices]
    return _polygon_from_points(points)


def _circle_polygon(entity: Circle, *, curve_tolerance_mm: float) -> Polygon | None:
    return _flattened_path_polygon(entity, curve_tolerance_mm=curve_tolerance_mm)


def _transform_polygon(polygon: Polygon, matrix: Matrix44) -> Polygon:
    exterior = _transform_coords(polygon.exterior.coords, matrix)
    holes = [_transform_coords(interior.coords, matrix) for interior in polygon.interiors]
    return _polygon_from_points(exterior, holes=holes)


def _transform_coords(coords, matrix: Matrix44) -> list[tuple[float, float]]:
    transformed: list[tuple[float, float]] = []
    for x, y, *_ in coords:
        point = matrix.transform(Vec3(float(x), float(y), 0))
        transformed.append((float(point.x), float(point.y)))
    return transformed


def _polygon_from_points(
    points: list[tuple[float, float]],
    *,
    holes: list[list[tuple[float, float]]] | None = None,
) -> Polygon | None:
    if len(points) < 3:
        return None

    polygon = Polygon(points, holes or [])
    if not polygon.is_valid:
        polygon = make_valid(polygon)
    if polygon.is_empty or polygon.area <= 0:
        return None

    assert polygon.is_valid
    return polygon
