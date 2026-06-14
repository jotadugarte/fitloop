# [REQ-FIT-NEST-002] Orthogonal DXF fixtures nest axis-aligned on one sheet.
from __future__ import annotations

import math
from pathlib import Path

import pytest

from nesting_engine.nest_geometry_classify import classify_geometry, is_axis_aligned_on_sheet
from nesting_engine.nest_libnest2d import nest_sheet
from nesting_engine.nest_placement import placed_polygon, score_sheet_layout
from nesting_engine.nest_types import apply_kerf
from nesting_engine.piece_loader import load_pieces, piece_polygon

_FIXTURES = Path(__file__).resolve().parent / "fixtures" / "individuals"


def _load_fixture_polygon(name: str):
    path = _FIXTURES / name
    assert path.is_file(), f"missing fixture: {path}"
    warnings: list[str] = []
    pieces = load_pieces([str(path)], ["PIECES", "CORTE"], curve_tolerance_mm=0.25, warnings=warnings)
    assert len(pieces) == 1
    return pieces[0]


def _primary_edge_angle_deg(poly) -> float:
    rect = poly.minimum_rotated_rectangle
    coords = list(rect.exterior.coords)
    best_len = -1.0
    best_angle = 0.0
    for index in range(4):
        x1, y1 = coords[index]
        x2, y2 = coords[index + 1]
        length = math.hypot(x2 - x1, y2 - y1)
        if length > best_len:
            best_len = length
            best_angle = math.degrees(math.atan2(y2 - y1, x2 - x1)) % 180.0
    return best_angle


def _angles_parallel(angle_a: float, angle_b: float, tolerance_deg: float) -> bool:
    delta = abs((angle_a - angle_b) % 180.0)
    return delta <= tolerance_deg or abs(delta - 180.0) <= tolerance_deg


def _assert_pieces_nest_axis_aligned(
    pieces: list,
    placements: list,
    *,
    kerf_mm: float,
) -> list:
    placed_polys = []
    for piece, placement in zip(pieces, placements, strict=True):
        fit = apply_kerf(piece_polygon(piece), kerf_mm)
        placed = placed_polygon(fit, placement)
        assert is_axis_aligned_on_sheet(placed), (
            f"piece must nest axis-aligned; rotation_deg={placement.rotation_deg}"
        )
        placed_polys.append(placed)
    return placed_polys


@pytest.mark.slow
def test_nest_sheet_keeps_001_and_002_axis_aligned_on_one_sheet() -> None:
    """[REQ-FIT-NEST-002] Rotated rectangle (002) must nest at right angles with 001."""
    piece_a = _load_fixture_polygon("001.dxf")
    piece_b = _load_fixture_polygon("002.dxf")
    poly_b = piece_polygon(piece_b)
    is_ortho_b, _angle_b = classify_geometry(poly_b)
    assert is_ortho_b is True, "002.dxf must classify as orthogonal"

    pieces = [piece_a, piece_b]
    placements = nest_sheet(
        pieces,
        bin_width_mm=600.0,
        bin_height_mm=500.0,
        margin_mm=5.0,
        kerf_mm=0.0,
    )

    assert len(placements) == 2
    _assert_pieces_nest_axis_aligned(pieces, placements, kerf_mm=0.0)


@pytest.mark.slow
def test_nest_sheet_keeps_001_and_009_axis_aligned_on_one_sheet() -> None:
    """[REQ-FIT-NEST-002] Dynamic orthogonality: tilted/staircase rects stay sheet-parallel."""
    piece_a = _load_fixture_polygon("001.dxf")
    piece_b = _load_fixture_polygon("009.dxf")
    pieces = [piece_a, piece_b]

    placements = nest_sheet(
        pieces,
        bin_width_mm=3000.0,
        bin_height_mm=3000.0,
        margin_mm=5.0,
        kerf_mm=0.0,
    )

    assert len(placements) == 2
    placed_polys = _assert_pieces_nest_axis_aligned(pieces, placements, kerf_mm=0.0)

    angle_a = _primary_edge_angle_deg(placed_polys[0])
    angle_b = _primary_edge_angle_deg(placed_polys[1])
    assert _angles_parallel(angle_a, angle_b, 5.0), (
        f"001 and 009 must share orientation; angles {angle_a:.2f} vs {angle_b:.2f}"
    )


# Baseline with nest_blp (no cardinal 90° in batch): ~354_830 mm² free on 700×600.
# Cardinal NFP batch (Option A) reaches ~393_000 mm² for the same fixtures.
_MIN_FREE_AREA_001_002_003 = 380_000.0


@pytest.mark.slow
def test_nest_sheet_001_002_003_uses_cardinal_rotation_for_material_efficiency() -> None:
    """[REQ-FIT-NEST-002] All-orthogonal batch must explore 90° to reduce layout footprint."""
    pieces = [
        _load_fixture_polygon("001.dxf"),
        _load_fixture_polygon("002.dxf"),
        _load_fixture_polygon("003.dxf"),
    ]
    bin_w, bin_h, margin = 700.0, 600.0, 5.0

    placements = nest_sheet(
        pieces,
        bin_width_mm=bin_w,
        bin_height_mm=bin_h,
        margin_mm=margin,
        kerf_mm=0.0,
    )

    assert len(placements) == 3
    placed_polys = _assert_pieces_nest_axis_aligned(pieces, placements, kerf_mm=0.0)
    free_area, footprint = score_sheet_layout(bin_w, bin_h, margin, placed_polys)
    assert free_area >= _MIN_FREE_AREA_001_002_003, (
        f"expected larger continuous free area; got {free_area:.0f} mm² (footprint {footprint:.0f})"
    )
