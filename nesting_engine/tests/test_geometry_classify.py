import math
from pathlib import Path
from shapely.geometry import Polygon, Point
from shapely.affinity import rotate
from nesting_engine.nest_geometry_classify import (
    classify_geometry,
    is_axis_aligned_on_sheet,
    is_orthogonal_for_cardinal_nesting,
    needs_pre_align_orthogonal,
    pre_align_orthogonal,
    _ombb_cardinal_deviation_deg,
)
from nesting_engine.piece_loader import load_pieces, piece_polygon

def test_basic_shapes():
    # 1. Clean rectangle (aligned)
    rect = Polygon([(0, 0), (100, 0), (100, 50), (0, 50)])
    is_ortho, angle = classify_geometry(rect)
    assert is_ortho is True
    assert abs(angle) < 1.0 or abs(angle - 90) < 1.0
    
    # 2. Rotated rectangle
    rotated_rect = rotate(rect, 30.0, origin=(0, 0))
    is_ortho, angle = classify_geometry(rotated_rect)
    assert is_ortho is True
    assert abs(angle - 30.0) < 1.0 or abs(angle - 120.0) < 1.0
    
    # 3. Circle (approximated, should NOT be orthogonal)
    circle = Point(0, 0).buffer(50.0, resolution=16)
    is_ortho, angle = classify_geometry(circle)
    assert is_ortho is False

    # 4. Triangle (right triangle, should NOT be orthogonal under 70% threshold)
    triangle = Polygon([(0, 0), (10, 0), (0, 10)])
    is_ortho, angle = classify_geometry(triangle)
    assert is_ortho is False

def test_real_fixtures():
    workspace = Path(__file__).parent.parent.parent
    warnings = []
    
    # 001.dxf (orthogonal rectangle)
    p001_path = workspace / "nesting_engine/tests/fixtures/individuals/001.dxf"
    pieces = load_pieces([str(p001_path)], ["PIECES", "CORTE"], curve_tolerance_mm=0.25, warnings=warnings)
    poly_001 = piece_polygon(pieces[0])
    is_ortho_001, angle_001 = classify_geometry(poly_001)
    assert is_ortho_001 is True
    
    # 009.dxf (orthogonal with step staircase and tilt)
    p009_path = workspace / "nesting_engine/tests/fixtures/individuals/009.dxf"
    pieces = load_pieces([str(p009_path)], ["PIECES", "CORTE"], curve_tolerance_mm=0.25, warnings=warnings)
    poly_009 = piece_polygon(pieces[0])
    is_ortho_009, angle_009 = classify_geometry(poly_009)
    assert is_ortho_009 is True

    # 002.dxf (rotated rectangle with internal line decorations)
    p002_path = workspace / "nesting_engine/tests/fixtures/individuals/002.dxf"
    pieces = load_pieces([str(p002_path)], ["PIECES", "CORTE"], curve_tolerance_mm=0.25, warnings=warnings)
    poly_002 = piece_polygon(pieces[0])
    is_ortho_002, angle_002 = classify_geometry(poly_002)
    assert is_ortho_002 is True
    assert not is_axis_aligned_on_sheet(poly_002)
    
    # 011.dxf (complex orthogonal shape rotated by 45° with tiny corner chamfers)
    p011_path = workspace / "nesting_engine/tests/fixtures/individuals/011.dxf"
    pieces = load_pieces([str(p011_path)], ["PIECES", "CORTE"], curve_tolerance_mm=0.25, warnings=warnings)
    poly_011 = piece_polygon(pieces[0])
    is_ortho_011, angle_011 = classify_geometry(poly_011)
    assert is_ortho_011 is True
    assert abs(angle_011 - 45.0) < 1.0


def test_needs_pre_align_when_ombb_tilted_but_segments_are_sheet_parallel() -> None:
    """[REQ-FIT-NEST-002] Staircase 009: OMBB ~85° must pre-align even when segment ratio passes."""
    workspace = Path(__file__).parent.parent.parent
    warnings: list[str] = []
    p009_path = workspace / "nesting_engine/tests/fixtures/individuals/009.dxf"
    pieces = load_pieces([str(p009_path)], ["PIECES", "CORTE"], curve_tolerance_mm=0.25, warnings=warnings)
    poly_009 = piece_polygon(pieces[0])
    _is_ortho, principal = classify_geometry(poly_009)
    assert _is_ortho is True
    assert abs(principal - 85.0) < 2.0
    assert needs_pre_align_orthogonal(poly_009) is True
    aligned, offset = pre_align_orthogonal(poly_009)
    assert offset is not None
    assert _ombb_cardinal_deviation_deg(aligned) <= 1.0
    assert is_orthogonal_for_cardinal_nesting(poly_009) is True


def test_pre_align_uses_exact_ombb_for_arbitrary_tilt():
    # [REQ-FIT-NEST-002] 38° tilt must pre-align by -38°, not snap to -45°.
    rect = Polygon([(0, 0), (100, 0), (100, 50), (0, 50)])
    tilted = rotate(rect, 38.0, origin=(0, 0))
    _is_ortho, principal = classify_geometry(tilted)
    assert _is_ortho is True
    aligned, offset = pre_align_orthogonal(tilted)
    assert offset is not None
    assert abs(offset - principal) < 1.0
    assert abs(offset - 45.0) > 1.0
    assert is_axis_aligned_on_sheet(aligned)


def test_pre_align_snaps_when_principal_near_cardinal():
    rect = Polygon([(0, 0), (100, 0), (100, 50), (0, 50)])
    tilted = rotate(rect, 44.6, origin=(0, 0))
    _is_ortho, _principal = classify_geometry(tilted)
    assert _is_ortho is True
    _aligned, offset = pre_align_orthogonal(tilted)
    assert offset is not None
    assert abs(offset - 45.0) < 1.0


def test_pointed_fixture_013_is_not_orthogonal_for_cardinal_nesting() -> None:
    """[REQ-FIT-NEST-002] Pointed 013 must use fine rotation steps, not cardinal-only."""
    workspace = Path(__file__).parent.parent.parent
    warnings: list[str] = []
    p013_path = workspace / "nesting_engine/tests/fixtures/individuals/013.dxf"
    pieces = load_pieces([str(p013_path)], ["PIECES", "CORTE"], curve_tolerance_mm=0.25, warnings=warnings)
    poly_013 = piece_polygon(pieces[0])
    is_ortho_013, _principal = classify_geometry(poly_013)
    assert is_ortho_013 is False
    assert is_orthogonal_for_cardinal_nesting(poly_013) is False
    assert needs_pre_align_orthogonal(poly_013) is False
