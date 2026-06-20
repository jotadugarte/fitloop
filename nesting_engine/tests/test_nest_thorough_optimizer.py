# [REQ-FIT-NEST-002] Thorough optimizer integration and invariant tests.
from __future__ import annotations

from pathlib import Path

import pytest
from shapely.geometry import Polygon

from nesting_engine.nest_bin import nest_multi_bin
from nesting_engine.nest_objective import score_nested_layout
from nesting_engine.nest_placement import placed_polygon, polygons_overlap_significantly
from nesting_engine.nest_types import SheetStockSpec
from nesting_engine.piece_loader import load_pieces, piece_polygon


def _load_fixture_pieces(names: list[str]) -> list:
    fixtures = Path(__file__).resolve().parent / "fixtures" / "individuals"
    loaded = load_pieces(
        [str(fixtures / name) for name in names],
        ["CORTE"],
        curve_tolerance_mm=0.25,
        warnings=[],
    )
    return [piece_polygon(piece) for piece in loaded]


def _assert_no_foreign_hole_nesting(names: list[str], worlds: list[tuple[str, Polygon]]) -> None:
    for left_name, left_poly in worlds:
        for right_name, right_poly in worlds:
            if left_name == right_name:
                continue
            assert not polygons_overlap_significantly(left_poly, right_poly)
            for ring in left_poly.interiors:
                hole = Polygon(ring)
                if hole.contains(right_poly.centroid) and left_poly.intersection(right_poly).area < 1.0:
                    pytest.fail(f"{right_name} placed inside hole of {left_name}")


@pytest.mark.slow
def test_thorough_mode_007_through_011_meets_invariants_and_scores() -> None:
    names = ["007.dxf", "008.dxf", "009.dxf", "010.dxf", "011.dxf"]
    pieces = _load_fixture_pieces(names)
    stocks = [SheetStockSpec(width_mm=700.0, height_mm=700.0, quantity=1, sort_order=0)]

    fast = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=5.0,
        kerf_mm=0.0,
        sheet_gap_mm=0.0,
        time_limit_sec=120.0,
        optimization_mode="fast",
    )
    thorough = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=5.0,
        kerf_mm=0.0,
        sheet_gap_mm=0.0,
        time_limit_sec=180.0,
        optimization_mode="thorough",
        max_seeds=6,
        max_local_search_iterations=4,
    )

    assert len(thorough.sheets) == 1
    assert not thorough.orphans
    worlds = [
        (names[row.piece_index], placed_polygon(pieces[row.piece_index], row.placement))
        for row in thorough.sheets[0].pieces
    ]
    _assert_no_foreign_hole_nesting(names, worlds)

    fast_score = score_nested_layout(fast.sheets, pieces, margin_mm=5.0)
    thorough_score = score_nested_layout(thorough.sheets, pieces, margin_mm=5.0)
    assert thorough_score.sheet_count <= fast_score.sheet_count
    assert thorough_score.total_waste_mm2 <= fast_score.total_waste_mm2 + 1.0
