# [REQ-FIT-NEST-002] Orthogonal DXF fixtures nest axis-aligned on one sheet.
from __future__ import annotations

import json
import math
import tempfile
from pathlib import Path

import pytest
from shapely.affinity import rotate
from shapely.geometry import Polygon

from nesting_engine.nest import run_from_config
from nesting_engine.nest_geometry_classify import (
    _ombb_cardinal_deviation_deg,
    classify_geometry,
    is_ombb_axis_aligned_on_sheet,
    is_axis_aligned_on_sheet,
)
from nesting_engine.nest_libnest2d import nest_multi_bin, nest_sheet, _prepare_solver_piece
from nesting_engine.nest_placement import placed_polygon, score_sheet_layout
from nesting_engine.nest_types import SheetStockSpec, apply_kerf
from nesting_engine.piece_loader import load_pieces, piece_polygon

_FIXTURES = Path(__file__).resolve().parent / "fixtures" / "individuals"


def _load_fixture_polygon(name: str, *, curve_tolerance_mm: float = 0.25):
    path = _FIXTURES / name
    assert path.is_file(), f"missing fixture: {path}"
    warnings: list[str] = []
    pieces = load_pieces(
        [str(path)],
        ["PIECES", "CORTE"],
        curve_tolerance_mm=curve_tolerance_mm,
        warnings=warnings,
    )
    assert len(pieces) == 1
    return pieces[0]


def _assert_cardinal_rotation_deg(rotation_deg: float) -> None:
    residual = abs(rotation_deg % 90.0)
    assert residual <= _MARGIN_EPS_MM or abs(residual - 90.0) <= _MARGIN_EPS_MM, (
        f"expected cardinal rotation, got rotation_deg={rotation_deg}"
    )


def _effective_solver_rotation_deg(piece, placement) -> float:
    prep = _prepare_solver_piece(piece_polygon(piece))
    rotation_deg = placement.rotation_deg
    if prep.pre_align_deg is not None and abs(prep.pre_align_deg) > 1e-9:
        rotation_deg = (rotation_deg + prep.pre_align_deg) % 360.0
    return rotation_deg


def _assert_preview_ring_visually_axis_aligned(ring_poly: Polygon) -> None:
    assert is_ombb_axis_aligned_on_sheet(ring_poly), (
        "preview ring OMBB must be sheet-parallel (no ~5° staircase tilt)"
    )


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
        assert is_ombb_axis_aligned_on_sheet(placed), (
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

    placed_polys = []
    for placed_row in result.sheets[0].pieces:
        fit = apply_kerf(piece_polygon(pieces[placed_row.piece_index]), 0.0)
        poly = placed_polygon(fit, placed_row.placement)
        assert is_axis_aligned_on_sheet(poly), (
            f"greedy fallback tilts pieces; rotation_deg={placed_row.placement.rotation_deg}"
        )
        placed_polys.append(poly)
    min_minx = min(poly.bounds[0] for poly in placed_polys)
    assert min_minx <= margin + _MARGIN_EPS_MM, "batch layout should compact to the left margin"


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
    min_minx = min(poly.bounds[0] for poly in placed_polys)
    assert min_minx <= margin + _MARGIN_EPS_MM, "at least one piece should hug the left sheet margin"
    lowest = min(placed_polys, key=lambda poly: (poly.bounds[1], poly.bounds[0]))
    assert lowest.bounds[1] <= margin + _MARGIN_EPS_MM, "bottom piece should hug the lower sheet margin"
    assert lowest.bounds[0] <= margin + _MARGIN_EPS_MM


@pytest.mark.slow
def test_nest_multi_bin_001_002_003_left_column_order_on_700_square() -> None:
    """[REQ-FIT-NEST-002] Three-piece batch stays left-aligned; flip must not scatter pieces."""
    pieces = [
        _load_fixture_polygon("001.dxf"),
        _load_fixture_polygon("002.dxf"),
        _load_fixture_polygon("003.dxf"),
    ]
    bin_w, bin_h, margin = 700.0, 700.0, 5.0
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
    placed_polys = [
        placed_polygon(
            apply_kerf(piece_polygon(pieces[row.piece_index]), 0.0),
            row.placement,
        )
        for row in result.sheets[0].pieces
    ]
    assert len(placed_polys) == 3

    for poly in placed_polys:
        minx, miny, maxx, maxy = poly.bounds
        assert minx >= margin - _MARGIN_EPS_MM
        assert miny >= margin - _MARGIN_EPS_MM
        assert maxx <= bin_w - margin + _MARGIN_EPS_MM
        assert maxy <= bin_h - margin + _MARGIN_EPS_MM
        assert is_axis_aligned_on_sheet(poly)

    min_minx = min(poly.bounds[0] for poly in placed_polys)
    assert min_minx <= margin + _MARGIN_EPS_MM, "at least one piece should stay in the left margin column"
    lowest = min(placed_polys, key=lambda poly: (poly.bounds[1], poly.bounds[0]))
    assert lowest.bounds[1] <= margin + _MARGIN_EPS_MM
    layout_maxx = max(poly.bounds[2] for poly in placed_polys)
    assert layout_maxx <= 600.0, "layout must not scatter a piece to the far right of the sheet"


@pytest.mark.slow
def test_nest_multi_bin_seven_pieces_gravity_respects_layout_score_on_700x800() -> None:
    """[REQ-FIT-NEST-002] Post-fill gravity compacts when score-safe; may skip drops that fragment free area."""
    fixture_names = [
        "001.dxf",
        "002.dxf",
        "003.dxf",
        "005.dxf",
        "006.dxf",
        "007.dxf",
        "008.dxf",
    ]
    pieces = [ _load_fixture_polygon(name) for name in fixture_names ]
    name_by_index = { index: name for index, name in enumerate(fixture_names) }
    bin_w, bin_h, margin = 700.0, 800.0, 5.0
    stocks = [ SheetStockSpec(width_mm=bin_w, height_mm=bin_h, quantity=1, sort_order=0) ]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=margin,
        kerf_mm=0.0,
        sheet_gap_mm=0.0,
    )

    assert len(result.sheets) == 1
    assert not result.orphans
    placed_by_name: dict[str, object] = {}
    for row in result.sheets[0].pieces:
        poly = placed_polygon(
            apply_kerf(piece_polygon(pieces[row.piece_index]), 0.0),
            row.placement,
        )
        placed_by_name[name_by_index[row.piece_index]] = poly

    bottom_band = [
        poly for poly in placed_by_name.values()
        if poly.bounds[1] <= margin + _MARGIN_EPS_MM
    ]
    assert bottom_band, "at least one piece should compact into the bottom margin band"
    for poly in placed_by_name.values():
        minx, miny, maxx, maxy = poly.bounds
        assert minx >= margin - _MARGIN_EPS_MM
        assert miny >= margin - _MARGIN_EPS_MM
        assert maxx <= bin_w - margin + _MARGIN_EPS_MM
        assert maxy <= bin_h - margin + _MARGIN_EPS_MM


@pytest.mark.slow
def test_nest_multi_bin_009_single_piece_prefers_horizontal_cardinal_on_700x800() -> None:
    """[REQ-FIT-NEST-002] Single orthogonal 009 picks the smaller-footprint horizontal cardinal."""
    piece = _load_fixture_polygon("009.dxf")
    bin_w, bin_h, margin = 700.0, 800.0, 5.0
    stocks = [ SheetStockSpec(width_mm=bin_w, height_mm=bin_h, quantity=1, sort_order=0) ]

    result = nest_multi_bin(
        [ piece ],
        stocks,
        margin_mm=margin,
        kerf_mm=0.0,
        sheet_gap_mm=0.0,
    )

    assert len(result.sheets) == 1
    assert not result.orphans
    row = result.sheets[0].pieces[0]
    poly = placed_polygon(apply_kerf(piece_polygon(piece), 0.0), row.placement)
    minx, miny, maxx, maxy = poly.bounds
    width = maxx - minx
    height = maxy - miny
    assert minx <= margin + _MARGIN_EPS_MM and miny <= margin + _MARGIN_EPS_MM
    assert is_ombb_axis_aligned_on_sheet(poly)
    _assert_cardinal_rotation_deg(_effective_solver_rotation_deg(piece, row.placement))
    assert width > height, "009 should nest horizontal (wide) rather than vertical (tall)"


@pytest.mark.slow
def test_nest_multi_bin_009_single_piece_cardinal_on_700_square_workshop_tolerance() -> None:
    """[REQ-FIT-NEST-002] Finalize pass forces cardinal layout for 009 at project curve tolerance."""
    piece = _load_fixture_polygon("009.dxf", curve_tolerance_mm=0.1)
    bin_w, bin_h, margin = 700.0, 700.0, 5.0
    stocks = [ SheetStockSpec(width_mm=bin_w, height_mm=bin_h, quantity=1, sort_order=0) ]

    result = nest_multi_bin(
        [ piece ],
        stocks,
        margin_mm=margin,
        kerf_mm=0.0,
        sheet_gap_mm=0.0,
    )

    assert len(result.sheets) == 1
    assert not result.orphans
    row = result.sheets[0].pieces[0]
    poly = placed_polygon(apply_kerf(piece_polygon(piece), 0.0), row.placement)
    minx, miny, maxx, maxy = poly.bounds
    width = maxx - minx
    height = maxy - miny
    assert minx <= margin + _MARGIN_EPS_MM and miny <= margin + _MARGIN_EPS_MM
    assert is_ombb_axis_aligned_on_sheet(poly)
    _assert_cardinal_rotation_deg(_effective_solver_rotation_deg(piece, row.placement))
    assert width > height


@pytest.mark.slow
def test_run_from_config_009_placements_rings_stay_axis_aligned_for_preview() -> None:
    """[REQ-FIT-NEST-002] placements.json rings must not be Douglas-Peucker tilted for preview SVG."""
    path = _FIXTURES / "009.dxf"
    with tempfile.TemporaryDirectory() as tmp:
        config = {
            "output_dir": tmp,
            "input_files": [
                {
                    "path": str(path.resolve()),
                    "primary_layer": "CORTE",
                    "auxiliary_layers": [],
                }
            ],
            "sheet_stocks": [
                {"width_mm": 700.0, "height_mm": 700.0, "quantity": 1, "sort_order": 0}
            ],
            "margin_mm": 5.0,
            "kerf_mm": 0.0,
            "sheet_gap_mm": 0.0,
            "curve_tolerance_mm": 0.1,
            "time_limit_sec": 600,
        }
        run_from_config(config)
        piece = json.loads(Path(tmp, "placements.json").read_text())["sheets"][0]["pieces"][0]
        ring_poly = Polygon(piece["rings"][0])
        _assert_preview_ring_visually_axis_aligned(ring_poly)
        _assert_cardinal_rotation_deg(piece["rotation_deg"])
        assert piece["width_mm"] > piece["height_mm"]


@pytest.mark.slow
def test_run_from_config_009_placements_rings_axis_aligned_on_500_square() -> None:
    """[REQ-FIT-NEST-002] Workshop 500×500 preview must not show ~5° OMBB tilt for 009."""
    path = _FIXTURES / "009.dxf"
    with tempfile.TemporaryDirectory() as tmp:
        config = {
            "output_dir": tmp,
            "input_files": [
                {
                    "path": str(path.resolve()),
                    "primary_layer": "CORTE",
                    "auxiliary_layers": [],
                }
            ],
            "sheet_stocks": [
                {"width_mm": 500.0, "height_mm": 500.0, "quantity": 1, "sort_order": 0}
            ],
            "margin_mm": 5.0,
            "kerf_mm": 0.0,
            "sheet_gap_mm": 0.0,
            "curve_tolerance_mm": 0.1,
            "time_limit_sec": 600,
        }
        run_from_config(config)
        piece = json.loads(Path(tmp, "placements.json").read_text())["sheets"][0]["pieces"][0]
        ring_poly = Polygon(piece["rings"][0])
        _assert_preview_ring_visually_axis_aligned(ring_poly)
        _assert_cardinal_rotation_deg(piece["rotation_deg"])


@pytest.mark.slow
def test_restore_skewed_libnest2d_world_keeps_cardinal_for_orthogonal_009() -> None:
    """[REQ-FIT-NEST-002] Quantized libnest2d pose must not restore as ~5° off cardinal."""
    from shapely.affinity import rotate

    from nesting_engine.nest import _placed_world_polygon
    from nesting_engine.nest_libnest2d import _restore_placement_to_source

    piece = _load_fixture_polygon("009.dxf", curve_tolerance_mm=0.1)
    poly = piece_polygon(piece)
    result = nest_multi_bin(
        [ piece ],
        [ SheetStockSpec(width_mm=500.0, height_mm=500.0, quantity=1, sort_order=0) ],
        margin_mm=5.0,
        kerf_mm=0.0,
        sheet_gap_mm=0.0,
    )
    row = result.sheets[0].pieces[0]
    world = _placed_world_polygon(row)
    skewed_world = rotate(world, 5.0, origin="centroid")
    restored = _restore_placement_to_source(
        poly,
        poly,
        row.placement,
        world_geometry=skewed_world,
    )
    placed = placed_polygon(poly, restored)
    assert is_ombb_axis_aligned_on_sheet(placed)
    _assert_cardinal_rotation_deg(_effective_solver_rotation_deg(piece, restored))


@pytest.mark.slow
def test_nest_multi_bin_tilted_orthogonal_rectangle_nests_axis_aligned_on_500_square() -> None:
    """[REQ-FIT-NEST-002] Source-tilted orthogonal rects pre-align before cardinal pick (no ~5° drift)."""
    source = rotate(Polygon([(0, 0), (200, 0), (200, 40), (0, 40)]), 5.0, origin="centroid")
    bin_w, bin_h, margin = 500.0, 500.0, 5.0
    stocks = [ SheetStockSpec(width_mm=bin_w, height_mm=bin_h, quantity=1, sort_order=0) ]

    result = nest_multi_bin(
        [ source ],
        stocks,
        margin_mm=margin,
        kerf_mm=0.0,
        sheet_gap_mm=0.0,
    )

    assert len(result.sheets) == 1
    assert not result.orphans
    row = result.sheets[0].pieces[0]
    poly = placed_polygon(source, row.placement)
    assert is_axis_aligned_on_sheet(poly)
    minx, miny, _, _ = poly.bounds
    assert minx <= margin + _MARGIN_EPS_MM and miny <= margin + _MARGIN_EPS_MM
