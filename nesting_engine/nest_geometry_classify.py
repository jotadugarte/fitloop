# [REQ-FIT-NEST-002] Dynamic orthogonality classification for axis-aligned nesting.
from __future__ import annotations

import math

from shapely.affinity import rotate
from shapely.geometry import Polygon

ORTHO_ROTATIONS_DEG: tuple[float, ...] = (0.0, 90.0, 180.0, 270.0)
_SNAP_PRINCIPAL_CANDIDATES_DEG: tuple[float, ...] = (0.0, 45.0, 90.0)
_PRINCIPAL_SNAP_TOLERANCE_DEG = 1.0


def _pre_align_offset_deg(principal_deg: float, snap_tolerance_deg: float = _PRINCIPAL_SNAP_TOLERANCE_DEG) -> float:
    """OMMB principal angle for pre-align; snap to 0/45/90 only when already within tolerance."""
    principal = principal_deg % 180.0
    best_candidate = _SNAP_PRINCIPAL_CANDIDATES_DEG[0]
    best_delta = float("inf")
    for candidate in _SNAP_PRINCIPAL_CANDIDATES_DEG:
        delta = min(
            abs(principal - candidate),
            abs(principal - candidate - 180.0),
            abs(principal - candidate + 180.0),
        )
        if delta < best_delta:
            best_delta = delta
            best_candidate = candidate
    if best_delta <= snap_tolerance_deg:
        return best_candidate
    return principal


def classify_geometry(
    poly: Polygon,
    ortho_threshold: float = 0.70,
    angle_tolerance: float = 1.0,
    simplify_tolerance: float = 0.5,
) -> tuple[bool, float]:
    """
    Analyzes a shapely Polygon to determine if it is predominantly orthogonal.
    
    Returns:
        is_orthogonal (bool): True if orthogonal perimeter ratio >= ortho_threshold.
        best_angle (float): The principal axis angle of the OMBB in degrees [0, 180).
                            Rotating the polygon by -best_angle aligns it to X/Y axes.
    """
    if poly.is_empty:
        return False, 0.0
        
    if simplify_tolerance > 0.0:
        poly_to_analyze = poly.simplify(simplify_tolerance, preserve_topology=True)
    else:
        poly_to_analyze = poly

    rect = poly_to_analyze.minimum_rotated_rectangle
    if rect.geom_type != 'Polygon':
        # Point, LineString, or other degenerate cases
        return False, 0.0
        
    coords = list(rect.exterior.coords)
    max_len = -1.0
    best_angle = 0.0
    # The exterior of the minimum rotated rectangle always has 5 coords (0 to 4)
    for i in range(4):
        x1, y1 = coords[i]
        x2, y2 = coords[i+1]
        dist = math.hypot(x2 - x1, y2 - y1)
        if dist > max_len:
            max_len = dist
            best_angle = math.degrees(math.atan2(y2 - y1, x2 - x1)) % 180
            
    # Rotate by -best_angle to temporarily align with axes
    aligned = rotate(poly_to_analyze, -best_angle, origin="centroid")
    aligned_coords = list(aligned.exterior.coords)
    
    total_len = 0.0
    ortho_len = 0.0
    
    for i in range(len(aligned_coords) - 1):
        x1, y1 = aligned_coords[i]
        x2, y2 = aligned_coords[i+1]
        dx = abs(x2 - x1)
        dy = abs(y2 - y1)
        dist = math.hypot(dx, dy)
        total_len += dist
        
        if dist > 1e-5:
            angle_seg = math.degrees(math.atan2(dy, dx))
            # Check if aligned to 0° or 90° within the tolerance
            is_ortho = False
            for target in [0.0, 90.0]:
                if abs(angle_seg - target) < angle_tolerance:
                    is_ortho = True
                    break
            if is_ortho:
                ortho_len += dist
                
    if total_len == 0.0:
        return False, 0.0
        
    ortho_ratio = ortho_len / total_len
    is_orthogonal = ortho_ratio >= ortho_threshold
    
    return is_orthogonal, best_angle


def is_orthogonal_for_cardinal_nesting(
    poly: Polygon,
    *,
    ortho_threshold: float = 0.70,
) -> bool:
    """[REQ-FIT-NEST-002] True when piece should use cardinal 0/90/180/270° nesting.

    Dense contours with pointed features (e.g. 013.dxf) may pass a raw segment-ratio
    check while failing ``classify_geometry`` after simplify; trust classify only so
    the solver can explore finer rotation steps.
    """
    is_orthogonal, _principal_deg = classify_geometry(poly, ortho_threshold=ortho_threshold)
    return is_orthogonal


def _ombb_cardinal_deviation_deg(poly: Polygon) -> float:
    """Degrees from OMBB longest edge to the nearest sheet axis (0° or 90°)."""
    is_orthogonal, principal_deg = classify_geometry(poly)
    if not is_orthogonal:
        return float("inf")
    principal = principal_deg % 180.0
    return min(
        principal,
        abs(principal - 90.0),
        abs(principal - 180.0),
    )


def is_ombb_axis_aligned_on_sheet(
    poly: Polygon,
    angle_tolerance: float = _PRINCIPAL_SNAP_TOLERANCE_DEG,
) -> bool:
    """True when the OMBB is parallel to sheet axes within tolerance (visual alignment)."""
    return _ombb_cardinal_deviation_deg(poly) <= angle_tolerance


def needs_pre_align_orthogonal(poly: Polygon) -> bool:
    """[REQ-FIT-NEST-002] Pre-align when orthogonal but OMBB is not sheet-parallel."""
    is_orthogonal, _principal_deg = classify_geometry(poly)
    if not is_orthogonal:
        return False
    return _ombb_cardinal_deviation_deg(poly) > _PRINCIPAL_SNAP_TOLERANCE_DEG


def pre_align_orthogonal(poly: Polygon) -> tuple[Polygon, float | None]:
    """Rotate predominantly orthogonal polygons to sheet axes; return (geometry, offset_deg)."""
    if not needs_pre_align_orthogonal(poly):
        return poly, None
    _is_orthogonal, principal_deg = classify_geometry(poly)
    offset_deg = _pre_align_offset_deg(principal_deg)
    return rotate(poly, -offset_deg, origin="centroid"), offset_deg


def is_axis_aligned_on_sheet(poly: Polygon, angle_tolerance: float = 1.0) -> bool:
    """True when exterior segments are parallel to sheet X or Y within tolerance."""
    coords = list(poly.exterior.coords)
    total_len = 0.0
    ortho_len = 0.0
    for index in range(len(coords) - 1):
        x1, y1 = coords[index]
        x2, y2 = coords[index + 1]
        dx = abs(x2 - x1)
        dy = abs(y2 - y1)
        dist = math.hypot(dx, dy)
        total_len += dist
        if dist <= 1e-5:
            continue
        angle_seg = math.degrees(math.atan2(dy, dx))
        if any(abs(angle_seg - target) < angle_tolerance for target in (0.0, 90.0)):
            ortho_len += dist
    if total_len <= 1e-5:
        return False
    return (ortho_len / total_len) >= 0.70
