# [REQ-FIT-NEST-002] Orthogonal DXF fixtures nest axis-aligned on one sheet.
from __future__ import annotations

import math
from pathlib import Path

import pytest

from nesting_engine.nest_geometry_classify import ORTHO_ROTATIONS_DEG, is_axis_aligned_on_sheet
from nesting_engine.nest_libnest2d import nest_sheet
from nesting_engine.nest_placement import placed_polygon
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


@pytest.mark.slow
def test_nest_sheet_keeps_001_and_009_axis_aligned_on_one_sheet() -> None:
    """[REQ-FIT-NEST-002] Dynamic orthogonality: tilted/staircase rects stay sheet-parallel."""
    piece_a = _load_fixture_polygon("001.dxf")
    piece_b = _load_fixture_polygon("009.dxf")
    pieces = [piece_a, piece_b]
    kerf_mm = 0.0
    margin_mm = 5.0

    placements = nest_sheet(
        pieces,
        bin_width_mm=3000.0,
        bin_height_mm=3000.0,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )

    assert len(placements) == 2

    placed_polys = []
    for piece, placement in zip(pieces, placements, strict=True):
        fit = apply_kerf(piece_polygon(piece), kerf_mm)
        placed = placed_polygon(fit, placement)
        assert is_axis_aligned_on_sheet(placed), (
            f"piece must nest axis-aligned; rotation_deg={placement.rotation_deg}"
        )
        assert placement.rotation_deg in ORTHO_ROTATIONS_DEG
        placed_polys.append(placed)

    angle_a = _primary_edge_angle_deg(placed_polys[0])
    angle_b = _primary_edge_angle_deg(placed_polys[1])
    assert _angles_parallel(angle_a, angle_b, 5.0), (
        f"001 and 009 must share orientation; angles {angle_a:.2f} vs {angle_b:.2f}"
    )
