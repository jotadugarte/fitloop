# [REQ-FIT-NEST-002] Maqueta 007–012 quality harness (fast baseline vs thorough target).
from __future__ import annotations

import json
from pathlib import Path

import pytest
from shapely.geometry import Polygon

from nesting_engine.nest_bin import nest_multi_bin
from nesting_engine.nest_objective import LayoutScore, compare_layouts, layout_score_with_orphans
from nesting_engine.nest_placement import placed_polygon, polygons_overlap_significantly
from nesting_engine.nest_types import MultiBinResult, SheetStockSpec
from nesting_engine.piece_loader import load_pieces, piece_polygon
from shapely.affinity import translate

_FIXTURES = Path(__file__).resolve().parent / "fixtures" / "individuals"
_BASELINE_PATH = _FIXTURES / "maqueta-quality-baseline.json"
_MAQUETA_NAMES = [f"{index:03d}.dxf" for index in range(7, 13)]
_MARGIN_MM = 5.0
_KERF_MM = 0.0
_SHEET_GAP_MM = 0.0
_BIN_W = 700.0
_BIN_H = 700.0
_USABLE_SHEET_AREA_MM2 = (_BIN_W - 2 * _MARGIN_MM) ** 2


def _load_maqueta_pieces() -> list[Polygon]:
    loaded = load_pieces(
        [str(_FIXTURES / name) for name in _MAQUETA_NAMES],
        ["CORTE"],
        curve_tolerance_mm=0.25,
        warnings=[],
    )
    return [piece_polygon(piece) for piece in loaded]


def _layout_score(result: MultiBinResult, pieces: list[Polygon]) -> LayoutScore:
    return layout_score_with_orphans(
        result.sheets,
        pieces,
        margin_mm=_MARGIN_MM,
        orphan_count=len(result.orphans),
        reference_sheet_area_mm2=_USABLE_SHEET_AREA_MM2,
    )


def _assert_no_foreign_hole_nesting(
    names: list[str],
    result: MultiBinResult,
    pieces: list[Polygon],
) -> None:
    worlds: list[tuple[str, Polygon]] = []
    for sheet in result.sheets:
        for row in sheet.pieces:
            local_poly = placed_polygon(pieces[row.piece_index], row.placement)
            world_poly = translate(local_poly, xoff=sheet.offset_x_mm)
            worlds.append((names[row.piece_index], world_poly))
    for left_name, left_poly in worlds:
        for right_name, right_poly in worlds:
            if left_name == right_name:
                continue
            assert not polygons_overlap_significantly(left_poly, right_poly)
            for ring in left_poly.interiors:
                hole = Polygon(ring)
                if hole.contains(right_poly.centroid) and left_poly.intersection(right_poly).area < 1.0:
                    pytest.fail(f"{right_name} placed inside hole of {left_name}")


def _assert_pieces_fit_sheets(result: MultiBinResult, pieces: list[Polygon]) -> None:
    for sheet in result.sheets:
        for row in sheet.pieces:
            local_poly = placed_polygon(pieces[row.piece_index], row.placement)
            world = translate(local_poly, xoff=sheet.offset_x_mm)
            minx, miny, maxx, maxy = world.bounds
            assert minx >= sheet.offset_x_mm + _MARGIN_MM - 1e-3
            assert miny >= _MARGIN_MM - 1e-3
            assert maxx <= sheet.offset_x_mm + sheet.width_mm - _MARGIN_MM + 1e-3
            assert maxy <= sheet.height_mm - _MARGIN_MM + 1e-3


def _run_nest(pieces: list[Polygon], *, quantity: int, optimization_mode: str, time_limit_sec: float) -> MultiBinResult:
    stocks = [
        SheetStockSpec(
            width_mm=_BIN_W,
            height_mm=_BIN_H,
            quantity=quantity,
            sort_order=0,
        )
    ]
    return nest_multi_bin(
        pieces,
        stocks,
        margin_mm=_MARGIN_MM,
        kerf_mm=_KERF_MM,
        sheet_gap_mm=_SHEET_GAP_MM,
        time_limit_sec=time_limit_sec,
        optimization_mode=optimization_mode,
        max_seeds=12,
        max_local_search_iterations=8,
    )


def test_maqueta_quality_baseline_json_structure() -> None:
    """Baseline records fast-mode metrics only (no golden coordinates)."""
    baseline = json.loads(_BASELINE_PATH.read_text())
    assert baseline["fixture"] == _MAQUETA_NAMES
    assert set(baseline["cases"]) == {"1", "2"}
    for case in baseline["cases"].values():
        fast = case["fast"]
        assert fast["sheet_count"] >= 1
        assert fast["total_waste_mm2"] > 0.0
        assert fast["total_free_area_mm2"] >= 0.0


@pytest.mark.slow
@pytest.mark.parametrize("quantity", [1, 2])
def test_maqueta_quality_thorough_beats_or_ties_fast(quantity: int) -> None:
    """Thorough must not regress the global lexicographic objective vs fast."""
    pieces = _load_maqueta_pieces()
    fast = _run_nest(pieces, quantity=quantity, optimization_mode="fast", time_limit_sec=120.0)
    thorough = _run_nest(pieces, quantity=quantity, optimization_mode="thorough", time_limit_sec=180.0)

    _assert_no_foreign_hole_nesting(_MAQUETA_NAMES, fast, pieces)
    _assert_no_foreign_hole_nesting(_MAQUETA_NAMES, thorough, pieces)
    _assert_pieces_fit_sheets(thorough, pieces)

    fast_score = _layout_score(fast, pieces)
    thorough_score = _layout_score(thorough, pieces)
    assert compare_layouts(thorough_score, fast_score) <= 0


@pytest.mark.slow
def test_maqueta_quality_v2_target_free_area_when_same_sheet_count() -> None:
    """[REQ-FIT-NEST-002] v2 target: same sheet count → more continuous free area than fast."""
    pieces = _load_maqueta_pieces()
    quantity = 2
    fast = _run_nest(pieces, quantity=quantity, optimization_mode="fast", time_limit_sec=120.0)
    thorough = _run_nest(pieces, quantity=quantity, optimization_mode="thorough", time_limit_sec=180.0)

    fast_score = _layout_score(fast, pieces)
    thorough_score = _layout_score(thorough, pieces)

    assert thorough_score.sheet_count == fast_score.sheet_count
    assert thorough_score.total_free_area_mm2 >= fast_score.total_free_area_mm2
