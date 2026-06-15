# [REQ-FIT-NEST-001] Production capabilities; [REQ-FIT-NEST-002] nest_sheet + nest_multi_bin.
from __future__ import annotations

import json
from pathlib import Path

import pytest
from shapely.geometry import Polygon, box

from nesting_engine.nest import run_from_config

from nesting_engine.nest_bin import SheetStockSpec, _apply_kerf
from nesting_engine.nest_libnest2d import (
    ObstacleAwareSheetResult,
    SheetPiecePlacement,
    _placed_from_batch_result,
    _sheet_piece_world_polygon,
    _world_placement_valid,
    capabilities,
    nest_multi_bin,
    nest_sheet,
    nest_sheet_with_obstacles,
)
from nesting_engine.nest_placement import ROTATION_STEP_DEG, Placement, placed_polygon, polygons_overlap_significantly
from nesting_engine.piece_loader import load_pieces, piece_polygon

_EPS_MM = 1e-6


def test_world_placement_valid_rejects_in_bin_overlap() -> None:
    """[REQ-FIT-NEST-002] Overlap check must run for placements inside sheet bounds."""
    obstacle = box(10, 10, 40, 40)
    overlapping = box(30, 30, 60, 60)
    clear = box(50, 50, 80, 80)

    assert polygons_overlap_significantly(overlapping, obstacle)
    assert not _world_placement_valid(
        overlapping,
        bin_width_mm=100.0,
        bin_height_mm=100.0,
        margin_mm=0.0,
        obstacles=[obstacle],
        other_placed=[],
    )
    assert _world_placement_valid(
        clear,
        bin_width_mm=100.0,
        bin_height_mm=100.0,
        margin_mm=0.0,
        obstacles=[obstacle],
        other_placed=[],
    )


def test_capabilities_reports_libnest2d_production() -> None:
    caps = capabilities()

    assert caps.spike_only is False
    assert "libnest2d" in caps.library.lower()


def test_nest_sheet_packs_multiple_rectangles() -> None:
    pieces = [box(0, 0, 40, 20), box(0, 0, 30, 25)]

    placements = nest_sheet(pieces, bin_width_mm=200.0, bin_height_mm=200.0, margin_mm=1.0, kerf_mm=0.0)

    assert len(placements) == len(pieces)
    _assert_all_fit_bin(pieces, placements, bin_width_mm=200.0, bin_height_mm=200.0, margin_mm=1.0, kerf_mm=0.0)


def test_nest_sheet_places_piece_with_hole() -> None:
    outer = box(0, 0, 80, 40)
    hole = box(20, 10, 60, 30)
    piece = Polygon(outer.exterior.coords, [list(hole.exterior.coords)])

    placements = nest_sheet([piece], bin_width_mm=200.0, bin_height_mm=200.0, margin_mm=1.0, kerf_mm=0.0)

    assert len(placements) == 1
    assert placements[0].rotation_deg >= 0.0
    _assert_all_fit_bin([piece], placements, bin_width_mm=200.0, bin_height_mm=200.0, margin_mm=1.0, kerf_mm=0.0)


def test_nest_sheet_uses_non_zero_rotation_when_required() -> None:
    piece = box(0, 0, 90, 20)

    placements = nest_sheet([piece], bin_width_mm=50.0, bin_height_mm=100.0, margin_mm=0.0, kerf_mm=0.0)

    assert len(placements) == 1
    assert placements[0].rotation_deg != 0.0
    assert placements[0].rotation_deg >= ROTATION_STEP_DEG
    _assert_all_fit_bin([piece], placements, bin_width_mm=50.0, bin_height_mm=100.0, margin_mm=0.0, kerf_mm=0.0)


def test_nest_sheet_accepts_up_to_128_pieces() -> None:
    # [REQ-FIT-NEST-002] Full-sheet epic: batch up to 128 polygons per nest_sheet call.
    pieces = [box(0, 0, 5, 5) for _ in range(128)]

    placements = nest_sheet(
        pieces,
        bin_width_mm=2000.0,
        bin_height_mm=2000.0,
        margin_mm=1.0,
        kerf_mm=0.0,
    )

    assert len(placements) == 128
    _assert_all_fit_bin(
        pieces,
        placements,
        bin_width_mm=2000.0,
        bin_height_mm=2000.0,
        margin_mm=1.0,
        kerf_mm=0.0,
    )


def test_nest_sheet_with_obstacles_uses_cardinal_rotation_for_orthogonal_piece() -> None:
    # Orthogonal rectangles use NFP cardinal rotations (0/90/180/270°), not free tilt.
    piece = box(0, 0, 90, 20)
    margin_mm = 0.0
    kerf_mm = 0.0

    result = nest_sheet_with_obstacles(
        [piece],
        bin_width_mm=50.0,
        bin_height_mm=100.0,
        obstacles=[],
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )

    assert result.unplaced_indices == []
    resolved = result.placements[0]
    assert resolved.placement.rotation_deg in (0.0, 90.0, 180.0, 270.0)
    world = _sheet_piece_world_polygon(resolved)
    minx, miny, maxx, maxy = world.bounds
    assert minx >= margin_mm - _EPS_MM
    assert miny >= margin_mm - _EPS_MM
    assert maxx <= 50.0 - margin_mm + _EPS_MM
    assert maxy <= 100.0 - margin_mm + _EPS_MM


def test_nest_sheet_places_two_mm_square_after_integer_quantization() -> None:
    # libnest2d Item uses integer mm vertices; 2 mm features remain stable above 1 mm quantum.
    piece = box(0, 0, 2, 2)

    placements = nest_sheet([piece], bin_width_mm=50.0, bin_height_mm=50.0, margin_mm=0.0, kerf_mm=0.0)

    assert len(placements) == 1
    _assert_all_fit_bin([piece], placements, bin_width_mm=50.0, bin_height_mm=50.0, margin_mm=0.0, kerf_mm=0.0)


def _assert_all_fit_bin(
    pieces: list[Polygon],
    placements: list[Placement],
    *,
    bin_width_mm: float,
    bin_height_mm: float,
    margin_mm: float,
    kerf_mm: float,
) -> None:
    assert len(placements) == len(pieces)
    occupied: list[Polygon] = []
    for piece, placement in zip(pieces, placements, strict=True):
        fit_piece = _apply_kerf(piece, kerf_mm)
        placed = placed_polygon(fit_piece, placement)
        minx, miny, maxx, maxy = placed.bounds
        assert minx >= margin_mm - _EPS_MM
        assert miny >= margin_mm - _EPS_MM
        assert maxx <= bin_width_mm - margin_mm + _EPS_MM
        assert maxy <= bin_height_mm - margin_mm + _EPS_MM
        for obstacle in occupied:
            assert not (placed.intersects(obstacle) and not placed.touches(obstacle))
        occupied.append(placed)


def test_libnest2d_multi_bin_packs_multiple_pieces_on_one_sheet() -> None:
    pieces = [box(0, 0, 10, 10) for _ in range(3)]
    stocks = [SheetStockSpec(width_mm=50, height_mm=50, quantity=None, sort_order=0)]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=0.0,
        kerf_mm=0.0,
        sheet_gap_mm=10.0,
    )

    assert len(result.sheets) == 1
    assert len(result.sheets[0].pieces) == 3
    assert result.orphans == []


def test_libnest2d_margin_applies_at_sheet_edge_not_between_pieces() -> None:
    pieces = [box(0, 0, 10, 10), box(0, 0, 10, 10)]
    stocks = [SheetStockSpec(width_mm=50, height_mm=50, quantity=1, sort_order=0)]
    margin = 5.0

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=margin,
        kerf_mm=0.0,
        sheet_gap_mm=0.0,
    )

    assert result.orphans == []
    placed = sorted(
        result.sheets[0].pieces,
        key=lambda row: row.placement.x + row.placement.y,
    )
    first = placed_polygon(pieces[placed[0].piece_index], placed[0].placement)
    second = placed_polygon(pieces[placed[1].piece_index], placed[1].placement)

    assert margin <= first.bounds[0] <= margin + 1.05
    assert margin <= first.bounds[1] <= margin + 1.05
    assert (second.bounds[0] >= margin + 10.0 - 0.05) or (second.bounds[1] >= margin + 10.0 - 0.05)
    assert first.distance(second) >= 0.0


def test_libnest2d_kerf_keeps_minimum_gap_between_pieces() -> None:
    kerf = 4.0
    pieces = [box(0, 0, 10, 10), box(0, 0, 10, 10)]
    stocks = [SheetStockSpec(width_mm=50, height_mm=50, quantity=1, sort_order=0)]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=0.0,
        kerf_mm=kerf,
        sheet_gap_mm=0.0,
    )

    assert result.orphans == []
    polys = [
        placed_polygon(pieces[row.piece_index], row.placement)
        for row in result.sheets[0].pieces
    ]
    gap = polys[0].distance(polys[1])
    assert gap >= kerf - 0.2
    assert not polys[0].intersects(polys[1])


def test_finite_quantity_ten_matches_unlimited_sheet_count() -> None:
    # [REQ-FIT-NEST-002] Finite cap must not change layout when stock is plentiful.
    pieces = [box(0, 0, 15, 15) for _ in range(3)]
    params = {"margin_mm": 0.0, "kerf_mm": 0.0, "sheet_gap_mm": 10.0}
    unlimited = nest_multi_bin(
        pieces,
        [SheetStockSpec(width_mm=20, height_mm=20, quantity=None, sort_order=0)],
        **params,
    )
    finite = nest_multi_bin(
        pieces,
        [SheetStockSpec(width_mm=20, height_mm=20, quantity=10, sort_order=0)],
        **params,
    )

    assert len(finite.sheets) == len(unlimited.sheets)
    assert finite.orphans == []
    assert unlimited.orphans == []


def test_libnest2d_unlimited_stock_opens_extra_sheets_when_full() -> None:
    pieces = [box(0, 0, 15, 15) for _ in range(3)]
    stocks = [SheetStockSpec(width_mm=20, height_mm=20, quantity=None, sort_order=0)]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=0.0,
        kerf_mm=0.0,
        sheet_gap_mm=10.0,
    )

    assert len(result.sheets) == 3
    assert result.orphans == []
    assert result.sheets[1].offset_x_mm == pytest.approx(30.0, abs=0.05)
    assert result.sheets[2].offset_x_mm == pytest.approx(60.0, abs=0.05)


def test_multi_bin_consumes_finite_stocks_before_unlimited() -> None:
    # [REQ-FIT-NEST-002] Mis-ordered unlimited sort_order must not open the first sheet.
    pieces = [box(0, 0, 30, 30)]
    stocks = [
        SheetStockSpec(width_mm=500, height_mm=500, quantity=None, sort_order=0),
        SheetStockSpec(width_mm=50, height_mm=50, quantity=1, sort_order=1),
        SheetStockSpec(width_mm=50, height_mm=50, quantity=1, sort_order=2),
    ]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=0.0,
        kerf_mm=0.0,
        sheet_gap_mm=10.0,
    )

    assert result.orphans == []
    assert len(result.sheets) == 1
    assert result.sheets[0].stock_sort_order == 1


def test_libnest2d_finite_stock_then_next_sort_order() -> None:
    pieces = [box(0, 0, 30, 30)]
    stocks = [
        SheetStockSpec(width_mm=20, height_mm=20, quantity=1, sort_order=0),
        SheetStockSpec(width_mm=200, height_mm=200, quantity=1, sort_order=1),
    ]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=0.0,
        kerf_mm=0.0,
        sheet_gap_mm=15.0,
    )

    assert len(result.sheets) == 1
    assert result.sheets[0].stock_sort_order == 1
    assert result.orphans == []


def test_run_from_config_honors_time_limit_sec_with_partial_and_warning(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # [REQ-FIT-NEST-003] Cooperative cap: best-so-far placements + warning before hard stop.
    pieces = [box(0, 0, 12, 12) for _ in range(6)]

    monkeypatch.setattr(
        "nesting_engine.nest.load_pieces_from_config",
        lambda _config, warnings: pieces,
    )

    calls = {"count": 0}

    def fake_monotonic() -> float:
        calls["count"] += 1
        if calls["count"] <= 10:
            return 0.0
        return 100.0

    monkeypatch.setattr("nesting_engine.nest_libnest2d.time.monotonic", fake_monotonic)

    output_dir = tmp_path / "nest_out"
    config = {
        "output_dir": str(output_dir),
        "input_dxf_paths": [],
        "included_layers": ["PIECES"],
        "sheet_stocks": [
            {"width_mm": 25.0, "height_mm": 25.0, "quantity": None, "sort_order": 0},
        ],
        "kerf_mm": 0.0,
        "margin_mm": 0.0,
        "sheet_gap_mm": 0.0,
        "time_limit_sec": 1,
    }

    run_from_config(config)

    report = json.loads((output_dir / "report.json").read_text(encoding="utf-8"))
    placements = json.loads((output_dir / "placements.json").read_text(encoding="utf-8"))

    assert report["status"] == "partial"
    assert any("time_limit" in warning.lower() for warning in report["warnings"])
    placed_count = sum(len(sheet["pieces"]) for sheet in placements["sheets"])
    assert placed_count >= 1
    assert len(placements["orphans"]) >= 1


def test_placed_from_batch_result_rejects_overlapping_solver_placements() -> None:
    """[REQ-FIT-NEST-002] Obstacle-aware batch must not accept placements that overlap occupied area."""
    pieces = [box(0, 0, 10, 10), box(0, 0, 10, 10)]
    occupied = [box(5, 5, 20, 20)]
    batch_result = ObstacleAwareSheetResult(
        placements={
            0: SheetPiecePlacement(
                placement=Placement(15.0, 15.0, 0.0),
                geometry=box(0, 0, 10, 10),
            ),
        },
        unplaced_indices=[],
    )

    placed, pending, new_occupied = _placed_from_batch_result(
        pieces,
        [0],
        batch_result,
        [0],
        kerf_mm=0.0,
        occupied=occupied,
        bin_width_mm=100.0,
        bin_height_mm=100.0,
        margin_mm=0.0,
    )

    assert placed == []
    assert pending == [0]
    assert new_occupied == occupied


@pytest.mark.slow
def test_nest_multi_bin_six_fixture_files_have_no_overlaps_on_700x690() -> None:
    """[REQ-FIT-NEST-002] Regression: crowded multi-file layout must not overlap on sheet."""
    fixtures = Path(__file__).resolve().parent / "fixtures" / "individuals"
    names = ["010.dxf", "011.dxf", "012.dxf", "013.dxf", "014.dxf", "016.dxf"]
    paths = [str(fixtures / name) for name in names]
    warnings: list[str] = []
    loaded = load_pieces(paths, ["PIECES", "CORTE"], curve_tolerance_mm=0.25, warnings=warnings)
    pieces = [piece_polygon(piece) for piece in loaded]
    stocks = [SheetStockSpec(width_mm=700, height_mm=690, quantity=None, sort_order=0)]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=0.0,
        kerf_mm=0.0,
        sheet_gap_mm=0.0,
    )

    for sheet in result.sheets:
        occupied: list[Polygon] = []
        for placed in sheet.pieces:
            world = placed_polygon(pieces[placed.piece_index], placed.placement)
            for blocker in occupied:
                assert not polygons_overlap_significantly(world, blocker)
            occupied.append(world)


def test_nest_sheet_packs_pieces_with_negative_offset_coordinates() -> None:
    # Test that shapes at negative coordinates (similar to the user's DXFs)
    # are correctly nested on the sheet and mapped back without overlapping.
    pieces = [
        box(-4600, -600, -4550, -550),
        box(-3700, -800, -3650, -750),
    ]

    placements = nest_sheet(
        pieces,
        bin_width_mm=200.0,
        bin_height_mm=200.0,
        margin_mm=5.0,
        kerf_mm=2.0,
    )

    assert len(placements) == len(pieces)
    _assert_all_fit_bin(
        pieces,
        placements,
        bin_width_mm=200.0,
        bin_height_mm=200.0,
        margin_mm=5.0,
        kerf_mm=2.0,
    )





