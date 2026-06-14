# [REQ-FIT-NEST-002] Orthogonal DXF fixtures nest axis-aligned on one sheet.
from __future__ import annotations

from pathlib import Path

import pytest

from nesting_engine.nest_geometry_classify import classify_geometry, is_axis_aligned_on_sheet
from nesting_engine.nest_libnest2d import nest_multi_bin, nest_sheet
from nesting_engine.nest_placement import placed_polygon, score_sheet_layout
from nesting_engine.nest_types import SheetStockSpec, apply_kerf
from nesting_engine.piece_loader import load_pieces, piece_polygon

_FIXTURES = Path(__file__).resolve().parent / "fixtures" / "individuals"


def _load_fixture_polygon(name: str):
    path = _FIXTURES / name
    assert path.is_file(), f"missing fixture: {path}"
    warnings: list[str] = []
    pieces = load_pieces([str(path)], ["PIECES", "CORTE"], curve_tolerance_mm=0.25, warnings=warnings)
    assert len(pieces) == 1
    return pieces[0]


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
    _assert_pieces_nest_axis_aligned(pieces, placements, kerf_mm=0.0)


# nest_blp without cardinal 90° (frozen DXF orientation): footprint ~4_045_357 mm².
# Cardinal NFP batch with valid in-bin placements: footprint ~257_000 mm².
_MAX_FOOTPRINT_001_002_003 = 300_000.0


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
    assert footprint <= _MAX_FOOTPRINT_001_002_003, (
        f"expected tighter layout footprint; got {footprint:.0f} mm² (free area {free_area:.0f})"
    )
    for poly in placed_polys:
        minx, miny, maxx, maxy = poly.bounds
        assert minx >= margin - 1e-3 and miny >= margin - 1e-3
        assert maxx <= bin_w - margin + 1e-3 and maxy <= bin_h - margin + 1e-3


@pytest.mark.slow
def test_nest_multi_bin_001_002_uses_cardinal_batch_fill() -> None:
    """[REQ-FIT-NEST-002] Fill phase must accept cardinal batch nest (not greedy fallback)."""
    pieces = [
        _load_fixture_polygon("001.dxf"),
        _load_fixture_polygon("002.dxf"),
    ]
    bin_w, bin_h, margin = 600.0, 700.0, 5.0
    stocks = [SheetStockSpec(width_mm=bin_w, height_mm=bin_h, quantity=1, sort_order=0)]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=margin,
        kerf_mm=0.0,
        sheet_gap_mm=0.0,
    )

    assert len(result.sheets) == 1
    assert not result.orphans
    assert len(result.sheets[0].pieces) == 2

    for placed_row in result.sheets[0].pieces:
        fit = apply_kerf(piece_polygon(pieces[placed_row.piece_index]), 0.0)
        poly = placed_polygon(fit, placed_row.placement)
        assert is_axis_aligned_on_sheet(poly), (
            f"greedy fallback tilts pieces; rotation_deg={placed_row.placement.rotation_deg}"
        )
        minx, _miny, _, _ = poly.bounds
        assert minx <= margin + _MARGIN_EPS_MM, "batch layout should compact to the left margin"


_MARGIN_EPS_MM = 1e-3


@pytest.mark.slow
def test_nest_multi_bin_001_002_pieces_pinned_to_sheet_margin() -> None:
    """[REQ-FIT-NEST-002] Layout must sit on the 5 mm sheet margin, not float inward."""
    pieces = [
        _load_fixture_polygon("001.dxf"),
        _load_fixture_polygon("002.dxf"),
    ]
    bin_w, bin_h, margin = 700.0, 800.0, 5.0
    stocks = [SheetStockSpec(width_mm=bin_w, height_mm=bin_h, quantity=1, sort_order=0)]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=margin,
        kerf_mm=0.0,
        sheet_gap_mm=0.0,
    )

    assert len(result.sheets) == 1
    placed_polys = [
        placed_polygon(
            apply_kerf(piece_polygon(pieces[row.piece_index]), 0.0),
            row.placement,
        )
        for row in result.sheets[0].pieces
    ]
    for poly in placed_polys:
        minx, miny, maxx, maxy = poly.bounds
        assert minx >= margin - _MARGIN_EPS_MM
        assert miny >= margin - _MARGIN_EPS_MM
        assert maxx <= bin_w - margin + _MARGIN_EPS_MM
        assert maxy <= bin_h - margin + _MARGIN_EPS_MM
        assert minx <= margin + _MARGIN_EPS_MM, "each piece should hug the left sheet margin"
    lowest = min(placed_polys, key=lambda poly: (poly.bounds[1], poly.bounds[0]))
    assert lowest.bounds[1] <= margin + _MARGIN_EPS_MM, "bottom piece should hug the lower sheet margin"
    assert lowest.bounds[0] <= margin + _MARGIN_EPS_MM
