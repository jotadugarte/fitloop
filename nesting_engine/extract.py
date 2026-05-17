# [REQ-FIT-EXT-001] [REQ-FIT-EXT-002] Extract closed contours and INSERT pieces on a layer.
from __future__ import annotations

import math
from pathlib import Path

import ezdxf
from ezdxf.entities import Circle, Insert, LWPolyline, Line, Polyline
from ezdxf.math import Matrix44, Vec3
from ezdxf.path import make_path
from shapely.geometry import LineString, Polygon
from shapely.ops import polygonize
from shapely.validation import make_valid

_MAX_ENTITIES = 100_000
_DEFAULT_MAX_BLOCK_DEPTH = 8
_MIN_COMPACTNESS = 0.08


def extract_closed_contours(
    dxf_path: Path | str,
    layer_name: str,
    *,
    curve_tolerance_mm: float = 0.1,
    max_block_depth: int = _DEFAULT_MAX_BLOCK_DEPTH,
    warnings: list[str] | None = None,
) -> list[Polygon]:
    """Return piece polygons: loose contours and INSERT geometry, with nested contours merged as holes."""
    assert layer_name and layer_name.strip(), "layer_name is required"
    assert curve_tolerance_mm > 0, "curve_tolerance_mm must be positive"
    assert max_block_depth >= 1, "max_block_depth must be at least 1"

    path = Path(dxf_path)
    assert path.is_file(), f"DXF file not found: {path}"

    report: list[str] = warnings if warnings is not None else []
    doc = ezdxf.readfile(path)
    polygons: list[Polygon] = []
    line_segments: list[tuple[tuple[float, float], tuple[float, float]]] = []
    scanned = 0

    for entity in doc.modelspace():
        scanned += 1
        assert scanned <= _MAX_ENTITIES, "DXF entity limit exceeded"

        if entity.dxf.layer != layer_name:
            continue

        if isinstance(entity, Insert):
            block_polys, block_segments = _geometry_from_block(
                doc,
                entity.dxf.name,
                entity.matrix44(),
                depth=1,
                curve_tolerance_mm=curve_tolerance_mm,
                max_block_depth=max_block_depth,
                warnings=report,
            )
            polygons.extend(block_polys)
            line_segments.extend(block_segments)
            continue

        if isinstance(entity, Line):
            line_segments.append(_line_segment(entity))
            continue

        polygon = _closed_contour_polygon(entity, curve_tolerance_mm=curve_tolerance_mm)
        if polygon is not None:
            polygons.append(polygon)

    polygons.extend(_polygons_from_line_segments(line_segments))
    polygons = _filter_meaningful_polygons(polygons, curve_tolerance_mm=curve_tolerance_mm)
    return _associate_nested_contours(polygons, curve_tolerance_mm=curve_tolerance_mm)


def _geometry_from_block(
    doc: ezdxf.document.Drawing,
    block_name: str,
    transform: Matrix44,
    *,
    depth: int,
    curve_tolerance_mm: float,
    max_block_depth: int,
    warnings: list[str],
) -> tuple[list[Polygon], list[tuple[tuple[float, float], tuple[float, float]]]]:
    if depth > max_block_depth:
        warnings.append(f"Block nesting depth exceeded limit ({max_block_depth})")
        return [], []

    block = doc.blocks.get(block_name)
    if block is None:
        warnings.append(f"Missing block definition: {block_name}")
        return [], []

    polygons: list[Polygon] = []
    line_segments: list[tuple[tuple[float, float], tuple[float, float]]] = []

    for entity in block:
        if isinstance(entity, Insert):
            nested = entity.matrix44()
            combined = transform @ nested
            nested_polys, nested_segments = _geometry_from_block(
                doc,
                entity.dxf.name,
                combined,
                depth=depth + 1,
                curve_tolerance_mm=curve_tolerance_mm,
                max_block_depth=max_block_depth,
                warnings=warnings,
            )
            polygons.extend(nested_polys)
            line_segments.extend(nested_segments)
            continue

        if isinstance(entity, Line):
            line_segments.append(_transform_segment(_line_segment(entity), transform))
            continue

        polygon = _closed_contour_polygon(entity, curve_tolerance_mm=curve_tolerance_mm)
        if polygon is not None:
            polygons.append(_transform_polygon(polygon, transform))

    return polygons, line_segments


def _line_segment(entity: Line) -> tuple[tuple[float, float], tuple[float, float]]:
    start = entity.dxf.start
    end = entity.dxf.end
    return (
        (float(start.x), float(start.y)),
        (float(end.x), float(end.y)),
    )


def _transform_segment(
    segment: tuple[tuple[float, float], tuple[float, float]],
    matrix: Matrix44,
) -> tuple[tuple[float, float], tuple[float, float]]:
    start = matrix.transform(Vec3(segment[0][0], segment[0][1], 0))
    end = matrix.transform(Vec3(segment[1][0], segment[1][1], 0))
    return (
        (float(start.x), float(start.y)),
        (float(end.x), float(end.y)),
    )


def _polygons_from_line_segments(
    segments: list[tuple[tuple[float, float], tuple[float, float]]],
) -> list[Polygon]:
    if not segments:
        return []

    lines = [LineString(segment) for segment in segments if segment[0] != segment[1]]
    polygons: list[Polygon] = []
    for geometry in polygonize(lines):
        if not isinstance(geometry, Polygon):
            continue
        if geometry.is_empty or geometry.area <= 0:
            continue
        if not geometry.is_valid:
            geometry = make_valid(geometry)
        if geometry.is_empty or geometry.area <= 0:
            continue
        polygons.append(geometry)
    return polygons


def _filter_meaningful_polygons(
    polygons: list[Polygon],
    *,
    curve_tolerance_mm: float,
) -> list[Polygon]:
    min_area = curve_tolerance_mm * curve_tolerance_mm
    filtered: list[Polygon] = []
    for polygon in polygons:
        if polygon.area < min_area:
            continue
        if _compactness(polygon) < _MIN_COMPACTNESS:
            continue
        filtered.append(polygon)
    return filtered


def _compactness(polygon: Polygon) -> float:
    if polygon.length <= 0:
        return 0.0
    return (4.0 * math.pi * polygon.area) / (polygon.length**2)


def _associate_nested_contours(
    polygons: list[Polygon],
    *,
    curve_tolerance_mm: float,
) -> list[Polygon]:
    """Merge contours fully inside another into a single polygon with holes (e.g. washer)."""
    count = len(polygons)
    if count <= 1:
        return list(polygons)

    parent_of = _containment_parents(polygons, curve_tolerance_mm=curve_tolerance_mm)
    children_of: dict[int, list[int]] = {index: [] for index in range(count)}
    for index, parent in parent_of.items():
        if parent is not None:
            children_of[parent].append(index)

    pieces: list[Polygon] = []
    for index in range(count):
        if parent_of[index] is not None:
            continue

        hole_indices = children_of[index]
        if not hole_indices:
            pieces.append(polygons[index])
            continue

        hole_rings = [_hole_ring_from_polygon(polygons[hole_index]) for hole_index in hole_indices]
        piece = _polygon_from_points(list(polygons[index].exterior.coords), holes=hole_rings)
        if piece is None:
            pieces.append(polygons[index])
            pieces.extend(polygons[hole_index] for hole_index in hole_indices)
            continue

        pieces.append(piece)
        for hole_index in hole_indices:
            for island_index in children_of[hole_index]:
                pieces.extend(
                    _associate_nested_contours(
                        [polygons[island_index]],
                        curve_tolerance_mm=curve_tolerance_mm,
                    )
                )

    return pieces


def _containment_parents(
    polygons: list[Polygon],
    *,
    curve_tolerance_mm: float,
) -> dict[int, int | None]:
    parents: dict[int, int | None] = {}
    for index, inner in enumerate(polygons):
        parents[index] = _smallest_containing_parent(
            index,
            inner,
            polygons,
            curve_tolerance_mm=curve_tolerance_mm,
        )
    return parents


def _smallest_containing_parent(
    index: int,
    inner: Polygon,
    polygons: list[Polygon],
    *,
    curve_tolerance_mm: float,
) -> int | None:
    best_parent: int | None = None
    best_area = float("inf")

    for candidate_index, outer in enumerate(polygons):
        if candidate_index == index:
            continue
        if outer.area <= inner.area:
            continue
        if not _is_polygon_contained(inner, outer, curve_tolerance_mm=curve_tolerance_mm):
            continue
        if outer.area < best_area:
            best_area = outer.area
            best_parent = candidate_index

    return best_parent


def _is_polygon_contained(
    inner: Polygon,
    outer: Polygon,
    *,
    curve_tolerance_mm: float,
) -> bool:
    if not outer.envelope.covers(inner.envelope):
        return False

    tolerance = max(curve_tolerance_mm * 2.0, 0.5)
    padded = outer.buffer(tolerance)
    if padded.covers(inner):
        return True

    return _are_coaxial_circles(inner, outer, tolerance)


def _are_coaxial_circles(inner: Polygon, outer: Polygon, tolerance: float) -> bool:
    inner_radius = _equivalent_circle_radius(inner)
    outer_radius = _equivalent_circle_radius(outer)
    if inner_radius is None or outer_radius is None:
        return False
    if inner_radius >= outer_radius:
        return False

    center_gap = inner.centroid.distance(outer.centroid)
    return center_gap + inner_radius <= outer_radius + tolerance


def _equivalent_circle_radius(polygon: Polygon) -> float | None:
    compactness = _compactness(polygon)
    if compactness < 0.7:
        return None
    return math.sqrt(polygon.area / math.pi)


def _hole_ring_from_polygon(polygon: Polygon) -> list[tuple[float, float]]:
    coords = list(polygon.exterior.coords)
    if _signed_area(coords) > 0:
        coords = coords[::-1]
    return coords


def _signed_area(coords: list[tuple[float, float]]) -> float:
    area = 0.0
    for index in range(len(coords) - 1):
        x0, y0 = coords[index]
        x1, y1 = coords[index + 1]
        area += x0 * y1 - x1 * y0
    return area / 2.0


def _closed_contour_polygon(entity: object, *, curve_tolerance_mm: float) -> Polygon | None:
    if isinstance(entity, LWPolyline):
        return _lwpolyline_polygon(entity, curve_tolerance_mm=curve_tolerance_mm)
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
    if len(points) < 3:
        return None

    gap = _point_distance(points[0], points[-1])
    if gap > curve_tolerance_mm:
        return None

    if gap > 0:
        points.append(points[0])
    return _polygon_from_points(points)


def _lwpolyline_polygon(entity: LWPolyline, *, curve_tolerance_mm: float) -> Polygon | None:
    points = [(float(x), float(y)) for x, y, *_ in entity.get_points("xy")]
    if len(points) < 3:
        return None

    if not entity.closed:
        gap = _point_distance(points[0], points[-1])
        if gap > curve_tolerance_mm:
            return None

    return _polygon_from_points(points)


def _polyline_polygon(entity: Polyline) -> Polygon | None:
    points = [(float(v.dxf.location.x), float(v.dxf.location.y)) for v in entity.vertices]
    return _polygon_from_points(points)


def _circle_polygon(entity: Circle, *, curve_tolerance_mm: float) -> Polygon | None:
    return _flattened_path_polygon(entity, curve_tolerance_mm=curve_tolerance_mm)


def _point_distance(
    left: tuple[float, float],
    right: tuple[float, float],
) -> float:
    return math.hypot(left[0] - right[0], left[1] - right[1])


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
