from __future__ import annotations

import math
from pathlib import Path
import numpy as np
import scipy.ndimage
import skimage.measure
from skimage.morphology import closing, disk
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import ezdxf
from ezdxf.path import make_path
from shapely.geometry import Polygon, LineString

from nesting_engine.composite_extract import CompositePiece, DecorationEntity


class BBox:
    def __init__(self, min_x: float, min_y: float, max_x: float, max_y: float):
        self.min_x = min_x
        self.min_y = min_y
        self.max_x = max_x
        self.max_y = max_y

    @property
    def width(self) -> float:
        return self.max_x - self.min_x

    @property
    def height(self) -> float:
        return self.max_y - self.min_y


def _collect_points_recursive(entity: object, doc: object, curve_tolerance_mm: float, points: list[tuple[float, float]], depth: int = 0) -> None:
    if depth > 8:
        return
    etype = entity.dxftype()
    if etype == "INSERT":
        block = doc.blocks.get(entity.dxf.name)
        if block:
            matrix = entity.matrix44()
            for sub_entity in block:
                sub_pts = []
                _collect_points_recursive(sub_entity, doc, curve_tolerance_mm, sub_pts, depth + 1)
                for p in sub_pts:
                    transformed = matrix.transform(ezdxf.math.Vec3(p[0], p[1], 0))
                    points.append((transformed.x, transformed.y))
        return

    try:
        path = make_path(entity)
        pts = [(float(v.x), float(v.y)) for v in path.flattening(curve_tolerance_mm)]
        points.extend(pts)
    except Exception:
        pass


def _compute_dxf_bounds(doc: object, layer_name: str, curve_tolerance_mm: float) -> BBox:
    points: list[tuple[float, float]] = []
    for entity in doc.modelspace():
        if entity.dxf.layer == layer_name:
            _collect_points_recursive(entity, doc, curve_tolerance_mm, points)
    if not points:
        return BBox(0.0, 0.0, 100.0, 100.0)
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return BBox(min(xs), min(ys), max(xs), max(ys))


def _render_entity_recursive(
    ax: object,
    entity: object,
    doc: object,
    curve_tolerance_mm: float,
    depth: int = 0,
    transform: object = None,
    auto_close_gaps: bool = False,
) -> None:
    if depth > 8:
        return
    etype = entity.dxftype()
    if etype == "INSERT":
        block = doc.blocks.get(entity.dxf.name)
        if block:
            matrix = entity.matrix44()
            combined = matrix if transform is None else transform @ matrix
            for sub_entity in block:
                _render_entity_recursive(ax, sub_entity, doc, curve_tolerance_mm, depth + 1, combined, auto_close_gaps)
        return

    try:
        path = make_path(entity)
        pts = [(float(v.x), float(v.y)) for v in path.flattening(curve_tolerance_mm)]
    except Exception:
        return

    if len(pts) < 2:
        return

    if transform is not None:
        pts = [(float(p.x), float(p.y)) for p in (transform.transform(ezdxf.math.Vec3(pt[0], pt[1], 0)) for pt in pts)]

    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]

    closed = False
    if etype in ("LWPOLYLINE", "POLYLINE"):
        closed = getattr(entity, "closed", False) or getattr(entity, "is_closed", False)
        if not closed:
            x0, y0 = pts[0]
            x1, y1 = pts[-1]
            dist = math.hypot(x1 - x0, y1 - y0)
            if dist <= 2.0 or (dist <= 15.0 and auto_close_gaps):
                closed = True

    if closed and (xs[0] != xs[-1] or ys[0] != ys[-1]):
        xs.append(xs[0])
        ys.append(ys[0])

    ax.plot(xs, ys, color="white", linewidth=1.0, antialiased=False)


def _rasterize_dxf_entities(
    entities: list[object],
    doc: object,
    bounds: BBox,
    scale_px_per_mm: float = 4.0,
    curve_tolerance_mm: float = 0.25,
    auto_close_gaps: bool = False,
) -> np.ndarray:
    margin = 5.0  # mm
    width_mm = bounds.width + 2 * margin
    height_mm = bounds.height + 2 * margin

    width_inches = width_mm / 25.4
    height_inches = height_mm / 25.4
    dpi = scale_px_per_mm * 25.4

    fig = plt.figure(figsize=(width_inches, height_inches), dpi=dpi, facecolor="black")
    ax = fig.add_axes([0.0, 0.0, 1.0, 1.0], facecolor="black")
    ax.axis("off")
    ax.set_xlim(bounds.min_x - margin, bounds.max_x + margin)
    ax.set_ylim(bounds.min_y - margin, bounds.max_y + margin)

    for entity in entities:
        _render_entity_recursive(ax, entity, doc, curve_tolerance_mm, auto_close_gaps=auto_close_gaps)

    fig.canvas.draw()
    rgba = np.asarray(fig.canvas.buffer_rgba())
    plt.close(fig)

    gray = rgba[:, :, 0]
    binary = gray > 128
    return binary


def _cluster_entities(doc: object, layer_name: str, curve_tolerance_mm: float) -> list[tuple[list[object], BBox]]:
    entities_with_bboxes = []
    for entity in doc.modelspace():
        if entity.dxf.layer == layer_name:
            pts = []
            _collect_points_recursive(entity, doc, curve_tolerance_mm, pts)
            if pts:
                xs = [p[0] for p in pts]
                ys = [p[1] for p in pts]
                bbox = BBox(min(xs), min(ys), max(xs), max(ys))
                entities_with_bboxes.append((entity, bbox))

    if not entities_with_bboxes:
        return []

    n = len(entities_with_bboxes)
    parent = list(range(n))

    def find(i):
        path = []
        while parent[i] != i:
            path.append(i)
            i = parent[i]
        for node in path:
            parent[node] = i
        return i

    def union(i, j):
        root_i = find(i)
        root_j = find(j)
        if root_i != root_j:
            parent[root_i] = root_j

    gap_threshold = 15.0  # mm
    for i in range(n):
        for j in range(i + 1, n):
            b1 = entities_with_bboxes[i][1]
            b2 = entities_with_bboxes[j][1]
            overlap = not (b1.max_x + gap_threshold < b2.min_x - gap_threshold or
                           b1.min_x - gap_threshold > b2.max_x + gap_threshold or
                           b1.max_y + gap_threshold < b2.min_y - gap_threshold or
                           b1.min_y - gap_threshold > b2.max_y + gap_threshold)
            if overlap:
                union(i, j)

    groups = {}
    for i in range(n):
        root = find(i)
        if root not in groups:
            groups[root] = []
        groups[root].append(entities_with_bboxes[i])

    clustered = []
    for group in groups.values():
        entities_list = [item[0] for item in group]
        min_x = min(item[1].min_x for item in group)
        min_y = min(item[1].min_y for item in group)
        max_x = max(item[1].max_x for item in group)
        max_y = max(item[1].max_y for item in group)
        clustered.append((entities_list, BBox(min_x, min_y, max_x, max_y)))

    return clustered


def _bridge_gaps(binary: np.ndarray, gap_bridge_px: int) -> np.ndarray:
    if gap_bridge_px < 1:
        return binary
    return closing(binary, footprint=disk(gap_bridge_px))


def _separate_shapes(binary: np.ndarray, scale_px_per_mm: float) -> list[np.ndarray]:
    labeled_lines = skimage.measure.label(binary)
    num_features = labeled_lines.max()
    
    masks = []
    for label in range(1, num_features + 1):
        line_mask = labeled_lines == label
        filled_mask = scipy.ndimage.binary_fill_holes(line_mask)
        
        line_area = np.sum(line_mask)
        filled_area = np.sum(filled_mask)
        
        if line_area <= 0:
            continue
            
        fill_ratio = filled_area / line_area
        # A true closed shape must enclose space, so its filled area must be significantly larger than the boundary line itself.
        if fill_ratio < 1.3:
            continue
            
        min_area_px = (5.0 * scale_px_per_mm) ** 2
        if filled_area > min_area_px:
            masks.append(filled_mask)
            
    return masks


def _mask_to_polygon(mask: np.ndarray, bounds: BBox, scale: float, img_height: int, curve_tolerance_mm: float) -> Polygon | None:
    from shapely.validation import make_valid

    margin = 5.0
    contours = skimage.measure.find_contours(mask, level=0.5)
    if not contours:
        return None
    
    contour = max(contours, key=len)
    approx_contour = skimage.measure.approximate_polygon(contour, tolerance=0.2)
    
    pts = []
    for row, col in approx_contour:
        x_mm = col / scale + bounds.min_x - margin
        y_mm = (img_height - row) / scale + bounds.min_y - margin
        pts.append((x_mm, y_mm))
        
    if len(pts) < 3:
        return None
        
    poly = Polygon(pts)
    poly = poly.buffer(-1.75 / scale, join_style=2)
    if not poly.is_valid:
        poly = make_valid(poly)
        
    if poly.is_empty:
        return None
        
    if poly.geom_type == "MultiPolygon":
        polys = [p for p in poly.geoms if not p.is_empty and p.area > 0]
        if not polys:
            return None
        poly = max(polys, key=lambda p: p.area)
    elif poly.geom_type != "Polygon":
        return None
        
    if poly.area < (curve_tolerance_mm * 4.0) ** 2:
        return None
        
    return poly


def image_extract_pieces(
    dxf_path: Path | str,
    layer_name: str,
    *,
    curve_tolerance_mm: float = 0.25,
    max_block_depth: int = 8,
    warnings: list[str] | None = None,
    auto_close_gaps: bool = False,
) -> list[CompositePiece]:
    path = Path(dxf_path)
    assert path.is_file(), f"DXF file not found: {path}"
    doc = ezdxf.readfile(path)

    from nesting_engine.extract import (
        _geometry_from_block,
        _collect_entity_geometry,
        _extract_line_strings,
    )

    # 1. Clustering & Extraction
    clusters = _cluster_entities(doc, layer_name, curve_tolerance_mm)
    polygons = []
    scale = 10.0

    for entities, bounds in clusters:
        binary = _rasterize_dxf_entities(
            entities,
            doc,
            bounds,
            scale,
            curve_tolerance_mm,
            auto_close_gaps=auto_close_gaps,
        )

        # 2. Gap bridging (always small for raster/aliasing gaps since vector gaps are closed during rendering)
        gap_bridge_px = 2
        bridged = _bridge_gaps(binary, gap_bridge_px)

        # 3. Labeling and filling
        masks = _separate_shapes(bridged, scale)

        # 4. Mask to polygon conversion
        img_height, img_width = bridged.shape
        for mask in masks:
            poly = _mask_to_polygon(mask, bounds, scale, img_height, curve_tolerance_mm)
            if poly is not None:
                polygons.append(poly)

    # 5. Nesting / association (G)
    from nesting_engine.extract import _associate_nested_contours
    polygons = _associate_nested_contours(polygons, curve_tolerance_mm=curve_tolerance_mm)

    # 6. Reconstruct the raw/absorbed structure from the DXF like the legacy engine does:
    raw_polygons = []
    circle_specs = []
    line_segments = []
    report = warnings if warnings is not None else []
    
    for entity in doc.modelspace():
        if entity.dxf.layer != layer_name:
            continue
        if entity.dxftype() == "INSERT":
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
        else:
            _collect_entity_geometry(
                entity,
                polygons=raw_polygons,
                circle_specs=circle_specs,
                line_segments=line_segments,
                curve_tolerance_mm=curve_tolerance_mm,
                auto_close_gaps=auto_close_gaps,
            )

    # Run legacy helper functions to get merged_polygons and absorbed_map
    from nesting_engine.extract import (
        _filter_meaningful_polygons,
        _circle_specs_from_polygons,
        _merge_circle_specs,
        _merge_overlapping_roots_with_absorbed,
    )
    
    legacy_polys = list(raw_polygons)
    legacy_polys = _filter_meaningful_polygons(legacy_polys, curve_tolerance_mm=curve_tolerance_mm)
    inferred_specs, legacy_polys = _circle_specs_from_polygons(legacy_polys, curve_tolerance_mm=curve_tolerance_mm)
    legacy_polys = _merge_circle_specs(circle_specs + inferred_specs, curve_tolerance_mm=curve_tolerance_mm) + legacy_polys
    
    merged_polygons, absorbed_map = _merge_overlapping_roots_with_absorbed(
        legacy_polys, curve_tolerance_mm=curve_tolerance_mm
    )

    pieces = []
    for i, polygon in enumerate(polygons):
        decorations = []
        
        # Match with a legacy merged polygon to get its absorbed shapes
        best_idx = None
        best_intersection = 0.0
        for idx, legacy_poly in enumerate(merged_polygons):
            if legacy_poly.intersects(polygon):
                inter_area = legacy_poly.intersection(polygon).area
                if inter_area > best_intersection:
                    best_intersection = inter_area
                    best_idx = idx

        matched_polygon = polygon
        if best_idx is not None:
            legacy_poly = merged_polygons[best_idx]
            # Check overlap percentage to ensure it's the same shape
            overlap_ratio = best_intersection / max(polygon.area, legacy_poly.area)
            if overlap_ratio > 0.85:
                matched_polygon = legacy_poly
                    
        # Add absorbed polygons boundaries as line decorations
        if best_idx is not None:
            absorbed = absorbed_map.get(best_idx, [])
            for absorbed_poly in absorbed:
                ring_coords = list(absorbed_poly.exterior.coords)
                if len(ring_coords) >= 2:
                    decorations.append(
                        DecorationEntity(
                            layer_name=layer_name,
                            geometry_type="line",
                            payload={"coordinates": ring_coords},
                        )
                    )
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

        # Also add any open line segments from the primary layer that lie inside the polygon
        boundary_buffered = matched_polygon.boundary.buffer(curve_tolerance_mm)
        for segment in line_segments:
            line = LineString(segment)
            if line.intersects(matched_polygon):
                clipped = line.intersection(matched_polygon)
                if not clipped.is_empty:
                    decor = clipped.difference(boundary_buffered)
                    if not decor.is_empty and decor.length > curve_tolerance_mm:
                        for part in _extract_line_strings(decor):
                            if part.length > curve_tolerance_mm:
                                decorations.append(
                                    DecorationEntity(
                                        layer_name=layer_name,
                                        geometry_type="line",
                                        payload={"coordinates": list(part.coords)},
                                    )
                                )
        pieces.append(
            CompositePiece(
                polygon=matched_polygon,
                decorations=decorations,
                piece_index=i,
                primary_layer_name=layer_name,
            )
        )

    return pieces
