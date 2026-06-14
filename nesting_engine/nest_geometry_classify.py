import math
from shapely.geometry import Polygon
from shapely.affinity import rotate

def classify_geometry(poly: Polygon, ortho_threshold: float = 0.70, angle_tolerance: float = 1.0, simplify_tolerance: float = 0.5) -> tuple[bool, float]:
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
