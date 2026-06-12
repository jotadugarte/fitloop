# [REQ-FIT-EXT-001] [REQ-FIT-EXT-002] Extract closed contours and INSERT pieces on a layer.
from __future__ import annotations

import math
from pathlib import Path
from typing import TYPE_CHECKING

import ezdxf
from ezdxf.entities import Circle, Insert, LWPolyline, Line, Polyline
from ezdxf.math import Matrix44, Vec3
from ezdxf.path import make_path
from shapely.geometry import LineString, MultiLineString, Polygon
from shapely.ops import polygonize
from shapely.validation import make_valid

if TYPE_CHECKING:
    from nesting_engine.composite_extract import CompositePiece, DecorationEntity

_MAX_ENTITIES = 100_000
_DEFAULT_MAX_BLOCK_DEPTH = 8
_MIN_COMPACTNESS = 0.08
_MIN_CIRCLE_COMPACTNESS = 0.55
_CircleSpec = tuple[float, float, float, Polygon]  # center_x, center_y, radius, polygon


def extract_closed_contours(
    dxf_path: Path | str,
    layer_name: str,
    *,
    curve_tolerance_mm: float = 0.1,
    max_block_depth: int = _DEFAULT_MAX_BLOCK_DEPTH,
    warnings: list[str] | None = None,
    auto_close_gaps: bool = False,
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
    circle_specs: list[_CircleSpec] = []
    line_segments: list[tuple[tuple[float, float], tuple[float, float]]] = []
    scanned = 0

    for entity in doc.modelspace():
        scanned += 1
        assert scanned <= _MAX_ENTITIES, "DXF entity limit exceeded"

        if entity.dxf.layer != layer_name:
            continue

        if isinstance(entity, Insert):
            block_polys, block_circles, block_segments = _geometry_from_block(
                doc,
                entity.dxf.name,
                entity.matrix44(),
                depth=1,
                curve_tolerance_mm=curve_tolerance_mm,
                max_block_depth=max_block_depth,
                warnings=report,
                auto_close_gaps=auto_close_gaps,
            )
            polygons.extend(block_polys)
            circle_specs.extend(block_circles)
            line_segments.extend(block_segments)
            continue

        _collect_entity_geometry(
            entity,
            polygons=polygons,
            circle_specs=circle_specs,
            line_segments=line_segments,
            curve_tolerance_mm=curve_tolerance_mm,
            auto_close_gaps=auto_close_gaps,
        )

    polygons.extend(_polygons_from_line_segments(line_segments, curve_tolerance_mm=curve_tolerance_mm))
    polygons = _filter_meaningful_polygons(polygons, curve_tolerance_mm=curve_tolerance_mm)
    inferred_specs, polygons = _circle_specs_from_polygons(polygons, curve_tolerance_mm=curve_tolerance_mm)
    polygons = _merge_circle_specs(circle_specs + inferred_specs, curve_tolerance_mm=curve_tolerance_mm) + polygons
    polygons = _merge_overlapping_roots(polygons, curve_tolerance_mm=curve_tolerance_mm)
    polygons = _associate_nested_contours(polygons, curve_tolerance_mm=curve_tolerance_mm)
    polygons = _drop_redundant_hole_fillers(polygons, curve_tolerance_mm=curve_tolerance_mm)
    polygons = _absorb_touching_fragments(polygons, curve_tolerance_mm=curve_tolerance_mm)
    return _drop_micro_fragments(polygons, curve_tolerance_mm=curve_tolerance_mm)


def _geometry_from_block(
    doc: ezdxf.document.Drawing,
    block_name: str,
    transform: Matrix44,
    *,
    depth: int,
    curve_tolerance_mm: float,
    max_block_depth: int,
    warnings: list[str],
    auto_close_gaps: bool = False,
) -> tuple[list[Polygon], list[_CircleSpec], list[tuple[tuple[float, float], tuple[float, float]]]]:
    if depth > max_block_depth:
        warnings.append(f"Block nesting depth exceeded limit ({max_block_depth})")
        return [], [], []

    block = doc.blocks.get(block_name)
    if block is None:
        warnings.append(f"Missing block definition: {block_name}")
        return [], [], []

    polygons: list[Polygon] = []
    circle_specs: list[_CircleSpec] = []
    line_segments: list[tuple[tuple[float, float], tuple[float, float]]] = []

    for entity in block:
        if isinstance(entity, Insert):
            nested = entity.matrix44()
            combined = transform @ nested
            nested_polys, nested_circles, nested_segments = _geometry_from_block(
                doc,
                entity.dxf.name,
                combined,
                depth=depth + 1,
                curve_tolerance_mm=curve_tolerance_mm,
                max_block_depth=max_block_depth,
                warnings=warnings,
                auto_close_gaps=auto_close_gaps,
            )
            polygons.extend(nested_polys)
            circle_specs.extend(nested_circles)
            line_segments.extend(nested_segments)
            continue

        block_polygons: list[Polygon] = []
        block_circles: list[_CircleSpec] = []
        block_segments: list[tuple[tuple[float, float], tuple[float, float]]] = []
        _collect_entity_geometry(
            entity,
            polygons=block_polygons,
            circle_specs=block_circles,
            line_segments=block_segments,
            curve_tolerance_mm=curve_tolerance_mm,
            auto_close_gaps=auto_close_gaps,
        )
        polygons.extend(_transform_polygon(polygon, transform) for polygon in block_polygons)
        circle_specs.extend(_transform_circle_spec(spec, transform) for spec in block_circles)
        line_segments.extend(_transform_segment(segment, transform) for segment in block_segments)

    return polygons, circle_specs, line_segments


def _collect_entity_geometry(
    entity: object,
    *,
    polygons: list[Polygon],
    circle_specs: list[_CircleSpec],
    line_segments: list[tuple[tuple[float, float], tuple[float, float]]],
    curve_tolerance_mm: float,
    auto_close_gaps: bool = False,
) -> None:
    if isinstance(entity, Line):
        line_segments.append(_line_segment(entity))
        return

    if _is_full_circle_entity(entity):
        spec = _circle_spec(entity, curve_tolerance_mm=curve_tolerance_mm)
        if spec is not None:
            circle_specs.append(spec)
        return

    polygon = _closed_contour_polygon(
        entity,
        curve_tolerance_mm=curve_tolerance_mm,
        auto_close_gaps=auto_close_gaps,
    )
    if polygon is not None:
        polygons.append(polygon)
        return

    line_segments.extend(_open_curve_segments(entity, curve_tolerance_mm=curve_tolerance_mm))
    line_segments.extend(_open_polyline_segments(entity, curve_tolerance_mm=curve_tolerance_mm))


def _is_full_circle_entity(entity: object) -> bool:
    return hasattr(entity, "dxftype") and entity.dxftype() == "CIRCLE"


def _circle_spec(entity: Circle, *, curve_tolerance_mm: float) -> _CircleSpec | None:
    polygon = _circle_polygon(entity, curve_tolerance_mm=curve_tolerance_mm)
    if polygon is None:
        return None

    center = entity.dxf.center
    return (float(center.x), float(center.y), float(entity.dxf.radius), polygon)


def _transform_circle_spec(spec: _CircleSpec, matrix: Matrix44) -> _CircleSpec:
    center_x, center_y, radius, polygon = spec
    transformed = _transform_polygon(polygon, matrix)
    point = matrix.transform(Vec3(center_x, center_y, 0))
    return (float(point.x), float(point.y), radius, transformed)


def _circle_specs_from_polygons(
    polygons: list[Polygon],
    *,
    curve_tolerance_mm: float,
) -> tuple[list[_CircleSpec], list[Polygon]]:
    specs: list[_CircleSpec] = []
    remaining: list[Polygon] = []

    for polygon in polygons:
        spec = _circle_spec_from_polygon(polygon, curve_tolerance_mm=curve_tolerance_mm)
        if spec is None:
            remaining.append(polygon)
        else:
            specs.append(spec)

    return specs, remaining


def _circle_spec_from_polygon(
    polygon: Polygon,
    *,
    curve_tolerance_mm: float,
) -> _CircleSpec | None:
    if len(polygon.interiors) > 0:
        return None
    if _compactness(polygon) < _MIN_CIRCLE_COMPACTNESS:
        return None

    tolerance = max(curve_tolerance_mm * 4.0, 1.0)
    centroid = polygon.centroid
    radius = math.sqrt(polygon.area / math.pi)
    if radius <= tolerance:
        return None

    return (float(centroid.x), float(centroid.y), radius, polygon)


def _drop_redundant_hole_fillers(
    polygons: list[Polygon],
    *,
    curve_tolerance_mm: float,
) -> list[Polygon]:
    """Remove solid disks that duplicate an existing hole (common with arc-only circle outlines)."""
    if len(polygons) <= 1:
        return list(polygons)

    tolerance = max(curve_tolerance_mm * 4.0, 1.0)
    drop: set[int] = set()

    for outer_index, outer in enumerate(polygons):
        if not outer.interiors:
            continue
        for inner_index, inner in enumerate(polygons):
            if inner_index == outer_index or inner_index in drop:
                continue
            if _polygon_fills_existing_hole(inner, outer, tolerance=tolerance):
                drop.add(inner_index)

    return [polygon for index, polygon in enumerate(polygons) if index not in drop]


def _polygon_fills_existing_hole(inner: Polygon, outer: Polygon, *, tolerance: float) -> bool:
    for hole_coords in outer.interiors:
        hole = Polygon(hole_coords)
        padded = hole.buffer(tolerance)
        if not padded.covers(inner.representative_point()):
            continue
        if inner.area > hole.area * 1.05:
            continue
        if _compactness(inner) >= _MIN_CIRCLE_COMPACTNESS:
            return _holes_match_circle(inner, hole, tolerance=tolerance)
        return True
    return False


def _holes_match_circle(inner: Polygon, hole: Polygon, *, tolerance: float) -> bool:
    if _compactness(inner) < _MIN_CIRCLE_COMPACTNESS:
        return False

    inner_radius = math.sqrt(inner.area / math.pi)
    hole_radius = math.sqrt(hole.area / math.pi)
    center_gap = inner.centroid.distance(hole.centroid)
    return center_gap <= tolerance * 2 and abs(inner_radius - hole_radius) <= tolerance * 2


def _drop_micro_fragments(
    polygons: list[Polygon],
    *,
    curve_tolerance_mm: float,
) -> list[Polygon]:
    """Drop tiny loops (e.g. arc-line join slivers) that are separate from the main piece."""
    if len(polygons) <= 1:
        return list(polygons)

    tolerance = max(curve_tolerance_mm * 4.0, 1.0)
    max_area = max(polygon.area for polygon in polygons)
    min_area = max(max_area * 0.015, (curve_tolerance_mm * 4.0) ** 2 * 20.0)
    drop: set[int] = set()

    for index, fragment in enumerate(polygons):
        if fragment.area >= min_area:
            continue
        drop.add(index)

    return [polygon for index, polygon in enumerate(polygons) if index not in drop]


def _merge_circle_specs(
    circle_specs: list[_CircleSpec],
    *,
    curve_tolerance_mm: float,
) -> list[Polygon]:
    if not circle_specs:
        return []

    tolerance = max(curve_tolerance_mm * 4.0, 1.0)
    ordered = sorted(circle_specs, key=lambda spec: spec[2], reverse=True)
    used: set[int] = set()
    pieces: list[Polygon] = []

    for outer_index, (outer_cx, outer_cy, outer_r, outer_poly) in enumerate(ordered):
        if outer_index in used:
            continue

        hole_rings: list[list[tuple[float, float]]] = []
        for inner_index, (inner_cx, inner_cy, inner_r, inner_poly) in enumerate(ordered):
            if inner_index == outer_index or inner_index in used:
                continue
            if inner_r >= outer_r:
                continue
            center_gap = math.hypot(outer_cx - inner_cx, outer_cy - inner_cy)
            center_tolerance = max(tolerance, outer_r * 0.02)
            if center_gap > center_tolerance:
                continue
            if not _circle_fits_inside(outer_poly, inner_poly, tolerance=tolerance):
                continue

            hole_rings.append(_hole_ring_from_polygon(inner_poly))
            used.add(inner_index)

        if hole_rings:
            piece = _polygon_from_points(list(outer_poly.exterior.coords), holes=hole_rings)
            if piece is not None:
                pieces.append(piece)
                used.add(outer_index)
                continue

        if outer_index not in used:
            pieces.append(outer_poly)
            used.add(outer_index)

    return pieces


def _circle_fits_inside(outer: Polygon, inner: Polygon, *, tolerance: float) -> bool:
    if outer.buffer(tolerance).covers(inner):
        return True

    return outer.buffer(tolerance).covers(inner.representative_point())


def _open_curve_segments(
    entity: object,
    *,
    curve_tolerance_mm: float,
) -> list[tuple[tuple[float, float], tuple[float, float]]]:
    if not hasattr(entity, "dxftype"):
        return []

    if entity.dxftype() not in {"ARC", "ELLIPSE", "SPLINE"}:
        return []

    path = make_path(entity)
    points = [(float(v.x), float(v.y)) for v in path.flattening(curve_tolerance_mm)]
    points = _pin_curve_path_endpoints(entity, points)
    if len(points) < 2:
        return []

    gap = _point_distance(points[0], points[-1])
    if gap <= curve_tolerance_mm:
        return []

    return _chain_segments(points)


def _open_polyline_segments(
    entity: object,
    *,
    curve_tolerance_mm: float,
) -> list[tuple[tuple[float, float], tuple[float, float]]]:
    if isinstance(entity, LWPolyline) and entity.closed:
        return []
    if isinstance(entity, Polyline) and entity.is_closed:
        return []

    if not isinstance(entity, (LWPolyline, Polyline)):
        return []

    try:
        path = make_path(entity)
    except (TypeError, ValueError):
        return []

    points = [(float(v.x), float(v.y)) for v in path.flattening(curve_tolerance_mm)]
    if len(points) < 2:
        return []

    gap = _point_distance(points[0], points[-1])
    if gap <= curve_tolerance_mm:
        return []

    return _chain_segments(points)


def _pin_curve_path_endpoints(
    entity: object,
    points: list[tuple[float, float]],
) -> list[tuple[float, float]]:
    if len(points) < 2 or not hasattr(entity, "dxftype"):
        return points

    if entity.dxftype() == "ARC":
        start = entity.start_point
        end = entity.end_point
        points[0] = (float(start.x), float(start.y))
        points[-1] = (float(end.x), float(end.y))

    return points


def _chain_segments(points: list[tuple[float, float]]) -> list[tuple[tuple[float, float], tuple[float, float]]]:
    segments: list[tuple[tuple[float, float], tuple[float, float]]] = []
    for index in range(len(points) - 1):
        start = points[index]
        end = points[index + 1]
        if start != end:
            segments.append((start, end))
    return segments


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
    *,
    curve_tolerance_mm: float,
) -> list[Polygon]:
    if not segments:
        return []

    grid_mm = max(curve_tolerance_mm, 0.05)
    segments = _normalize_segment_endpoints(segments, grid_mm=grid_mm)
    lines = [LineString(segment) for segment in segments if segment[0] != segment[1]]
    if not lines:
        return []

    # Large self-snap tolerances collapse fine arc tessellation and drop straight edges
    # (e.g. slot sides at curve_tolerance_mm=0.1). Polygonize the linework directly.
    linework = MultiLineString(lines)
    polygons: list[Polygon] = []
    for geometry in polygonize(linework):
        if not isinstance(geometry, Polygon):
            continue
        if geometry.is_empty or geometry.area <= 0:
            continue
        if not geometry.is_valid:
            geometry = make_valid(geometry)
        if geometry.is_empty or geometry.area <= 0:
            continue
        polygons.append(geometry)
    return _filter_polygon_slivers(polygons, curve_tolerance_mm=curve_tolerance_mm)


def _filter_polygon_slivers(
    polygons: list[Polygon],
    *,
    curve_tolerance_mm: float,
) -> list[Polygon]:
    if len(polygons) <= 1:
        return polygons

    max_area = max(polygon.area for polygon in polygons)
    min_area = max(max_area * 0.015, (curve_tolerance_mm * 4.0) ** 2 * 20.0)
    return [polygon for polygon in polygons if polygon.area >= min_area]


def _normalize_segment_endpoints(
    segments: list[tuple[tuple[float, float], tuple[float, float]]],
    *,
    grid_mm: float,
) -> list[tuple[tuple[float, float], tuple[float, float]]]:
    def snap_point(point: tuple[float, float]) -> tuple[float, float]:
        return (round(point[0] / grid_mm) * grid_mm, round(point[1] / grid_mm) * grid_mm)

    return [(snap_point(start), snap_point(end)) for start, end in segments]


def _absorb_touching_fragments(
    polygons: list[Polygon],
    *,
    curve_tolerance_mm: float,
) -> list[Polygon]:
    """Merge small caps/tips that touch a larger piece (e.g. slot end features)."""
    if len(polygons) <= 1:
        return list(polygons)

    tolerance = max(curve_tolerance_mm * 4.0, 0.5)
    result = sorted(polygons, key=lambda polygon: polygon.area, reverse=True)
    changed = True
    while changed and len(result) > 1:
        changed = False
        largest = result[0]
        rest: list[Polygon] = []
        for fragment in result[1:]:
            if fragment.area >= largest.area * 0.05:
                rest.append(fragment)
                continue
            if largest.buffer(tolerance).intersects(fragment):
                largest = largest.union(fragment)
                changed = True
            else:
                rest.append(fragment)
        result = [largest, *rest]

    return result


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

    tolerance = _containment_tolerance(inner, outer, curve_tolerance_mm=curve_tolerance_mm)
    padded = outer.buffer(tolerance)
    if padded.covers(inner):
        return True

    if _are_coaxial_circles(inner, outer, tolerance):
        return True

    return inner.within(padded)


def _containment_tolerance(
    inner: Polygon,
    outer: Polygon,
    *,
    curve_tolerance_mm: float,
) -> float:
    tolerance = max(curve_tolerance_mm * 4.0, 1.0)
    inner_radius = _equivalent_circle_radius(inner)
    outer_radius = _equivalent_circle_radius(outer)
    if inner_radius is None or outer_radius is None:
        return tolerance

    return max(tolerance, outer_radius * 0.02, inner_radius * 0.02)


def _are_coaxial_circles(inner: Polygon, outer: Polygon, tolerance: float) -> bool:
    inner_radius = _equivalent_circle_radius(inner)
    outer_radius = _equivalent_circle_radius(outer)
    if inner_radius is None or outer_radius is None:
        return False
    if inner_radius >= outer_radius:
        return False

    center_gap = inner.centroid.distance(outer.centroid)
    return center_gap + inner_radius <= outer_radius + tolerance * 2.0


def _equivalent_circle_radius(polygon: Polygon) -> float | None:
    compactness = _compactness(polygon)
    if compactness < _MIN_CIRCLE_COMPACTNESS:
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


def _force_close_polygon(points: list[tuple[float, float]]) -> Polygon | None:
    if len(points) < 3:
        return None
    if points[0] != points[-1]:
        closed_pts = points + [points[0]]
    else:
        closed_pts = points
    try:
        poly = Polygon(closed_pts)
        if poly.is_valid:
            if poly.area > 0:
                return poly
        valid_geom = make_valid(poly)
        if valid_geom.is_empty:
            return None
        if valid_geom.geom_type == "Polygon":
            if valid_geom.area > 0:
                return valid_geom
        elif valid_geom.geom_type == "MultiPolygon":
            polys = [p for p in valid_geom.geoms if not p.is_empty and p.area > 0]
            if polys:
                return max(polys, key=lambda p: p.area)
        elif hasattr(valid_geom, "geoms"):
            polys = [p for p in valid_geom.geoms if p.geom_type == "Polygon" and not p.is_empty and p.area > 0]
            if polys:
                return max(polys, key=lambda p: p.area)
    except Exception:
        pass
    return None


def _closed_contour_polygon(
    entity: object,
    *,
    curve_tolerance_mm: float,
    auto_close_gaps: bool = False,
) -> Polygon | None:
    if _is_full_circle_entity(entity):
        return None
    if isinstance(entity, LWPolyline):
        if _lwpolyline_has_bulge(entity):
            return _flattened_path_polygon(entity, curve_tolerance_mm=curve_tolerance_mm, auto_close_gaps=auto_close_gaps)
        polygon = _lwpolyline_polygon(entity, curve_tolerance_mm=curve_tolerance_mm, auto_close_gaps=auto_close_gaps)
        if polygon is not None:
            return polygon
        return _flattened_path_polygon(entity, curve_tolerance_mm=curve_tolerance_mm, auto_close_gaps=auto_close_gaps)
    if isinstance(entity, Polyline):
        if _polyline_has_bulge(entity):
            return _flattened_path_polygon(entity, curve_tolerance_mm=curve_tolerance_mm, auto_close_gaps=auto_close_gaps)
        return _polyline_polygon(entity, curve_tolerance_mm=curve_tolerance_mm, auto_close_gaps=auto_close_gaps)
    if hasattr(entity, "dxftype") and entity.dxftype() in {"ARC", "ELLIPSE", "SPLINE"}:
        return _flattened_path_polygon(entity, curve_tolerance_mm=curve_tolerance_mm, auto_close_gaps=auto_close_gaps)
    return None


def _flattened_path_polygon(
    entity: object,
    *,
    curve_tolerance_mm: float,
    auto_close_gaps: bool = False,
) -> Polygon | None:
    path = make_path(entity)
    points = [(float(v.x), float(v.y)) for v in path.flattening(curve_tolerance_mm)]
    if len(points) < 3:
        return None

    gap = _point_distance(points[0], points[-1])
    if gap > curve_tolerance_mm:
        etype = getattr(entity, "dxftype", lambda: "")()
        if etype in ("LWPOLYLINE", "POLYLINE"):
            if gap <= 2.0 or (gap <= 15.0 and auto_close_gaps):
                return _force_close_polygon(points)
        return None

    if gap > 0:
        points.append(points[0])
    return _polygon_from_points(points)


def _lwpolyline_has_bulge(entity: LWPolyline) -> bool:
    return any(abs(bulge) > 1e-9 for *_, bulge in entity.get_points("xyb"))


def _polyline_has_bulge(entity: Polyline) -> bool:
    return any(abs(float(vertex.dxf.bulge)) > 1e-9 for vertex in entity.vertices)


def _lwpolyline_polygon(
    entity: LWPolyline,
    *,
    curve_tolerance_mm: float,
    auto_close_gaps: bool = False,
) -> Polygon | None:
    points = [(float(x), float(y)) for x, y, *_ in entity.get_points("xy")]
    if len(points) < 3:
        return None

    if not entity.closed:
        gap = _point_distance(points[0], points[-1])
        if gap > curve_tolerance_mm:
            if gap <= 2.0 or (gap <= 15.0 and auto_close_gaps):
                return _force_close_polygon(points)
            return None

    return _polygon_from_points(points)


def _polyline_polygon(
    entity: Polyline,
    *,
    curve_tolerance_mm: float,
    auto_close_gaps: bool = False,
) -> Polygon | None:
    points = [(float(v.dxf.location.x), float(v.dxf.location.y)) for v in entity.vertices]
    if len(points) < 3:
        return None

    if not entity.is_closed:
        gap = _point_distance(points[0], points[-1])
        if gap > curve_tolerance_mm:
            if gap <= 2.0 or (gap <= 15.0 and auto_close_gaps):
                return _force_close_polygon(points)
            return None

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


def _coerce_single_polygon(geometry: object) -> Polygon | None:
    if geometry is None:
        return None
    if isinstance(geometry, Polygon):
        if geometry.is_empty or geometry.area <= 0:
            return None
        return geometry
    if hasattr(geometry, "geoms"):
        polygons = [
            part
            for part in geometry.geoms
            if isinstance(part, Polygon) and not part.is_empty and part.area > 0
        ]
        if not polygons:
            return None
        return max(polygons, key=lambda part: part.area)
    return None


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
    polygon = _coerce_single_polygon(polygon)
    if polygon is None:
        return None

    assert polygon.is_valid
    return polygon


def _merge_overlapping_roots(
    polygons: list[Polygon],
    curve_tolerance_mm: float,
) -> list[Polygon]:
    """Union overlapping or intersecting outer root polygons to form a single combined shape."""
    merged, _ = _merge_overlapping_roots_with_absorbed(polygons, curve_tolerance_mm)
    return merged


def _merge_overlapping_roots_with_absorbed(
    polygons: list[Polygon],
    curve_tolerance_mm: float,
) -> tuple[list[Polygon], dict[int, list[Polygon]]]:
    """Union overlapping roots and return (merged_polygons, absorbed_by_merged_index).

    The second return value maps each index in the returned list to ALL the
    original polygons that were merged into it.  Any of these original polygons
    can have edges that run INSIDE the union polygon (interior cut lines) — not
    just the smaller one.  When polygons partially protrude beyond each other,
    the larger polygon can also have interior edges.  All rings must be preserved
    in the output DXF so the cutting machine receives every required cut path.
    """
    if len(polygons) <= 1:
        return list(polygons), {0: [] if polygons else []}

    parent_of = _containment_parents(polygons, curve_tolerance_mm=curve_tolerance_mm)
    roots = [poly for i, poly in enumerate(polygons) if parent_of[i] is None]
    children = [poly for i, poly in enumerate(polygons) if parent_of[i] is not None]

    if len(roots) <= 1:
        return list(polygons), {i: [] for i in range(len(polygons))}

    # Make sure all root geometries are valid
    valid_roots = []
    for p in roots:
        if not p.is_valid:
            p = make_valid(p)
        if not p.is_empty:
            valid_roots.append(p)

    if not valid_roots:
        return children, {i: [] for i in range(len(children))}

    # Group valid_roots into connected components based on significant overlap
    # overlap condition: intersection area > 10% of the smaller polygon area
    components: list[list[Polygon]] = []
    for poly in valid_roots:
        overlap_indices = []
        for idx, comp in enumerate(components):
            overlaps = False
            for comp_poly in comp:
                if poly.intersects(comp_poly):
                    try:
                        inter_area = poly.intersection(comp_poly).area
                        min_area = min(poly.area, comp_poly.area)
                        if inter_area > min_area * 0.1:
                            overlaps = True
                            break
                    except Exception:
                        pass
            if overlaps:
                overlap_indices.append(idx)

        if not overlap_indices:
            components.append([poly])
        elif len(overlap_indices) == 1:
            components[overlap_indices[0]].append(poly)
        else:
            new_comp = [poly]
            for idx in sorted(overlap_indices, reverse=True):
                new_comp.extend(components.pop(idx))
            components.append(new_comp)

    # Union each component; track which polygons were absorbed
    from shapely.ops import unary_union
    merged_roots: list[Polygon] = []
    absorbed_map: dict[int, list[Polygon]] = {}

    for comp in components:
        if len(comp) == 1:
            idx = len(merged_roots)
            merged_roots.append(comp[0])
            absorbed_map[idx] = []
        else:
            merged_geom = unary_union(comp)
            # ALL polygons in the component carry interior cut lines:
            # - the "smaller" polygon has edges that run inside the larger's notch areas
            # - the "larger" polygon may have edges that run inside the smaller's protrusion areas
            # Storing all rings ensures no cut path is lost in the output DXF.
            absorbed = list(comp)

            if merged_geom.geom_type == "Polygon":
                if not merged_geom.is_empty:
                    idx = len(merged_roots)
                    merged_roots.append(merged_geom)
                    absorbed_map[idx] = absorbed
            elif merged_geom.geom_type == "MultiPolygon":
                for p in merged_geom.geoms:
                    if not p.is_empty:
                        idx = len(merged_roots)
                        merged_roots.append(p)
                        absorbed_map[idx] = absorbed
                        absorbed = []  # only attach to first fragment
            elif hasattr(merged_geom, "geoms"):
                for geom in merged_geom.geoms:
                    if geom.geom_type == "Polygon" and not geom.is_empty:
                        idx = len(merged_roots)
                        merged_roots.append(geom)
                        absorbed_map[idx] = absorbed
                        absorbed = []

    # Append children with no absorbed info
    for child in children:
        idx = len(merged_roots)
        merged_roots.append(child)
        absorbed_map[idx] = []

    return merged_roots, absorbed_map


def extract_pieces_with_internal_lines(
    dxf_path: Path | str,
    layer_name: str,
    *,
    curve_tolerance_mm: float = 0.1,
    max_block_depth: int = _DEFAULT_MAX_BLOCK_DEPTH,
    warnings: list[str] | None = None,
    auto_close_gaps: bool = False,
) -> list:
    """Like extract_closed_contours but returns CompositePiece objects.

    When two overlapping polylines on the same layer are merged into one outer
    polygon for nesting, the boundary of each absorbed (smaller) polygon is
    preserved as an internal line decoration on the same layer.  This ensures
    the output DXF contains ALL original cut lines, not only the union outline.

    Returns a list of CompositePiece objects (from composite_extract).
    """
    # Late import to avoid circular dependency
    from nesting_engine.composite_extract import CompositePiece, DecorationEntity  # noqa: PLC0415

    assert layer_name and layer_name.strip(), "layer_name is required"
    assert curve_tolerance_mm > 0, "curve_tolerance_mm must be positive"
    assert max_block_depth >= 1, "max_block_depth must be at least 1"

    path = Path(dxf_path)
    assert path.is_file(), f"DXF file not found: {path}"

    report: list[str] = warnings if warnings is not None else []
    doc = ezdxf.readfile(path)
    raw_polygons: list[Polygon] = []
    circle_specs: list[_CircleSpec] = []
    line_segments: list[tuple[tuple[float, float], tuple[float, float]]] = []
    scanned = 0

    for entity in doc.modelspace():
        scanned += 1
        assert scanned <= _MAX_ENTITIES, "DXF entity limit exceeded"

        if entity.dxf.layer != layer_name:
            continue

        if isinstance(entity, Insert):
            block_polys, block_circles, block_segments = _geometry_from_block(
                doc,
                entity.dxf.name,
                entity.matrix44(),
                depth=1,
                curve_tolerance_mm=curve_tolerance_mm,
                max_block_depth=max_block_depth,
                warnings=report,
                auto_close_gaps=auto_close_gaps,
            )
            raw_polygons.extend(block_polys)
            circle_specs.extend(block_circles)
            line_segments.extend(block_segments)
            continue

        _collect_entity_geometry(
            entity,
            polygons=raw_polygons,
            circle_specs=circle_specs,
            line_segments=line_segments,
            curve_tolerance_mm=curve_tolerance_mm,
            auto_close_gaps=auto_close_gaps,
        )

    raw_polygons.extend(_polygons_from_line_segments(line_segments, curve_tolerance_mm=curve_tolerance_mm))
    raw_polygons = _filter_meaningful_polygons(raw_polygons, curve_tolerance_mm=curve_tolerance_mm)
    inferred_specs, raw_polygons = _circle_specs_from_polygons(raw_polygons, curve_tolerance_mm=curve_tolerance_mm)
    raw_polygons = _merge_circle_specs(circle_specs + inferred_specs, curve_tolerance_mm=curve_tolerance_mm) + raw_polygons

    # --- merge overlapping roots and collect absorbed polygons ---
    merged_polygons, absorbed_map = _merge_overlapping_roots_with_absorbed(
        raw_polygons, curve_tolerance_mm=curve_tolerance_mm
    )

    # Continue with standard post-processing on merged polygons
    processed = _associate_nested_contours(merged_polygons, curve_tolerance_mm=curve_tolerance_mm)
    processed = _drop_redundant_hole_fillers(processed, curve_tolerance_mm=curve_tolerance_mm)
    processed = _absorb_touching_fragments(processed, curve_tolerance_mm=curve_tolerance_mm)
    processed = _drop_micro_fragments(processed, curve_tolerance_mm=curve_tolerance_mm)

    # Build CompositePiece objects: add absorbed polygon boundaries as line decorations
    pieces: list[CompositePiece] = []
    for i, polygon in enumerate(processed):
        decorations: list[DecorationEntity] = []
        absorbed = absorbed_map.get(i, [])
        for absorbed_poly in absorbed:
            # Add the exterior ring of each absorbed polygon as a line decoration
            ring_coords = list(absorbed_poly.exterior.coords)
            if len(ring_coords) >= 2:
                decorations.append(
                    DecorationEntity(
                        layer_name=layer_name,
                        geometry_type="line",
                        payload={"coordinates": ring_coords},
                    )
                )
            # Also add any interior rings of the absorbed polygon
            for interior in absorbed_poly.interiors:
                interior_coords = list(interior.coords)
                if len(interior_coords) >= 2:
                    decorations.append(
                        DecorationEntity(
                            layer_name=layer_name,
                            geometry_type="line",
                            payload={"coordinates": interior_coords},
                        )
                    )
        pieces.append(
            CompositePiece(
                polygon=polygon,
                decorations=decorations,
                piece_index=i,
                primary_layer_name=layer_name,
            )
        )

    return pieces
