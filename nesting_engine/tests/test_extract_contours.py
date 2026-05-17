# [REQ-FIT-EXT-001] Sample DXF yields at least one closed contour on selected layer.
# Fixture must be ezdxf-valid; regenerate with: python scripts/generate_sample_dxf.py
from __future__ import annotations

from pathlib import Path

import ezdxf
import pytest
from shapely.geometry import box

from nesting_engine.extract import _associate_nested_contours, extract_closed_contours

FIXTURES = Path(__file__).parent / "fixtures"
SAMPLE_DXF = FIXTURES / "sample_piece.dxf"
LAYER = "PIECES"


def test_extract_at_least_one_closed_contour_on_selected_layer() -> None:
    assert SAMPLE_DXF.is_file(), f"missing fixture: {SAMPLE_DXF}"

    contours = extract_closed_contours(SAMPLE_DXF, layer_name=LAYER)

    assert len(contours) >= 1
    polygon = contours[0]
    assert polygon.is_valid
    assert not polygon.is_empty
    assert polygon.area > 0


def test_concentric_circles_merge_into_one_piece_with_hole(tmp_path: Path) -> None:
    path = tmp_path / "washer.dxf"
    doc = ezdxf.new("R2010")
    msp = doc.modelspace()
    msp.add_circle(center=(0, 0), radius=50, dxfattribs={"layer": LAYER})
    msp.add_circle(center=(0, 0), radius=20, dxfattribs={"layer": LAYER})
    doc.saveas(path)

    contours = extract_closed_contours(path, layer_name=LAYER, curve_tolerance_mm=0.25)

    assert len(contours) == 1
    piece = contours[0]
    assert len(piece.interiors) == 1
    assert piece.area == pytest.approx(50 * 50 * 3.14159265 - 20 * 20 * 3.14159265, rel=0.02)


def test_separate_circles_remain_separate_pieces(tmp_path: Path) -> None:
    path = tmp_path / "two_circles.dxf"
    doc = ezdxf.new("R2010")
    msp = doc.modelspace()
    msp.add_circle(center=(0, 0), radius=30, dxfattribs={"layer": LAYER})
    msp.add_circle(center=(200, 0), radius=25, dxfattribs={"layer": LAYER})
    doc.saveas(path)

    contours = extract_closed_contours(path, layer_name=LAYER, curve_tolerance_mm=0.25)

    assert len(contours) == 2


def test_associate_nested_contours_builds_rect_with_hole() -> None:
    outer = box(0, 0, 100, 80)
    inner = box(20, 15, 60, 45)
    pieces = _associate_nested_contours([outer, inner], curve_tolerance_mm=0.1)

    assert len(pieces) == 1
    assert len(pieces[0].interiors) == 1
    assert pieces[0].area == pytest.approx(outer.area - inner.area)


def test_open_arc_is_not_extracted_as_phantom_piece(tmp_path: Path) -> None:
    path = tmp_path / "open_arc.dxf"
    doc = ezdxf.new("R2010")
    doc.modelspace().add_arc(
        center=(0, 0),
        radius=40,
        start_angle=20,
        end_angle=160,
        dxfattribs={"layer": LAYER},
    )
    doc.saveas(path)

    contours = extract_closed_contours(path, layer_name=LAYER, curve_tolerance_mm=0.25)

    assert contours == []


def test_rectangle_from_four_lines_is_extracted(tmp_path: Path) -> None:
    path = tmp_path / "line_rect.dxf"
    doc = ezdxf.new("R2010")
    msp = doc.modelspace()
    msp.add_line((0, 0), (200, 0), dxfattribs={"layer": LAYER})
    msp.add_line((200, 0), (200, 80), dxfattribs={"layer": LAYER})
    msp.add_line((200, 80), (0, 80), dxfattribs={"layer": LAYER})
    msp.add_line((0, 80), (0, 0), dxfattribs={"layer": LAYER})
    doc.saveas(path)

    contours = extract_closed_contours(path, layer_name=LAYER, curve_tolerance_mm=0.25)

    assert len(contours) == 1
    assert contours[0].area == pytest.approx(200 * 80, rel=0.01)


def test_nearly_closed_lwpolyline_is_extracted(tmp_path: Path) -> None:
    path = tmp_path / "open_rect.dxf"
    doc = ezdxf.new("R2010")
    doc.modelspace().add_lwpolyline(
        [(0, 0), (120, 0), (120, 50), (0.05, 0.05)],
        close=False,
        dxfattribs={"layer": LAYER},
    )
    doc.saveas(path)

    contours = extract_closed_contours(path, layer_name=LAYER, curve_tolerance_mm=0.25)

    assert len(contours) == 1
    assert contours[0].area > 0
