from __future__ import annotations

import math
from pathlib import Path
import pytest
from shapely.geometry import Polygon

from nesting_engine.image_extract import image_extract_pieces
from nesting_engine.composite_extract import CompositePiece

FIXTURES = Path(__file__).parent / "fixtures" / "individuals"
LAYER = "CORTE"  # Or whatever the default primary layer is in these files. Let's make sure we check.


def test_001_simple_rect() -> None:
    dxf_path = FIXTURES / "001.dxf"
    assert dxf_path.exists()
    
    pieces = image_extract_pieces(dxf_path, LAYER, curve_tolerance_mm=0.25)
    
    assert len(pieces) == 1
    piece = pieces[0]
    assert isinstance(piece, CompositePiece)
    assert piece.polygon.is_valid
    # 001.dxf is a simple rectangle. Let's assert area is close to ~43200 (±5%)
    assert piece.polygon.area == pytest.approx(43200.0, rel=0.05)


def test_002_rotated_with_lines() -> None:
    dxf_path = FIXTURES / "002.dxf"
    assert dxf_path.exists()
    
    pieces = image_extract_pieces(dxf_path, LAYER, curve_tolerance_mm=0.25)
    
    assert len(pieces) == 1
    piece = pieces[0]
    assert piece.polygon.is_valid
    # Check that it has internal line decorations from the DXF
    line_decorations = [d for d in piece.decorations if d.geometry_type == "line"]
    assert len(line_decorations) > 0


def test_004_gap_14mm_auto_bridged() -> None:
    dxf_path = FIXTURES / "004.dxf"
    assert dxf_path.exists()
    
    # Gap is ~14.8mm. The image extraction has auto_close_gaps or gap bridging.
    pieces = image_extract_pieces(dxf_path, LAYER, curve_tolerance_mm=0.25, auto_close_gaps=True)
    
    assert len(pieces) == 1
    piece = pieces[0]
    assert piece.polygon.is_valid
    assert piece.polygon.area > 0


def test_006_complex_notches() -> None:
    dxf_path = FIXTURES / "006.dxf"
    assert dxf_path.exists()
    
    pieces = image_extract_pieces(dxf_path, LAYER, curve_tolerance_mm=0.25)
    
    assert len(pieces) == 1
    piece = pieces[0]
    assert piece.polygon.is_valid
    assert piece.polygon.area > 0


def test_008_thin_crossbar_lines() -> None:
    dxf_path = FIXTURES / "008.dxf"
    assert dxf_path.exists()
    
    pieces = image_extract_pieces(dxf_path, LAYER, curve_tolerance_mm=0.25)
    
    assert len(pieces) == 1
    piece = pieces[0]
    assert piece.polygon.is_valid
    assert piece.polygon.area > 0
