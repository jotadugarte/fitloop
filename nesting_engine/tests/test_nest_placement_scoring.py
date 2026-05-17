# [REQ-FIT-NEST-002] Placement scoring prioritizes largest continuous free area.
from __future__ import annotations

from shapely.affinity import rotate, translate
from shapely.geometry import box
from shapely.ops import unary_union

from nesting_engine.nest_bin import SheetStockSpec, nest_multi_bin
from nesting_engine.nest_placement import (
    _largest_continuous_free_area,
    _placement_score,
    place_with_rotation,
    placed_polygon,
)

_EPS_MM = 1e-6


def test_placement_score_prefers_larger_continuous_free_area_over_smaller_footprint() -> None:
    bin_w, bin_h, margin = 400.0, 400.0, 0.0
    obstacle = box(0, 0, 300, 250)
    occupied_union = unary_union([obstacle])
    bar = box(0, 0, 120, 25)

    compact = translate(bar, xoff=180, yoff=250)
    expanded = translate(rotate(bar, 45, origin="centroid"), xoff=300, yoff=250)
    assert compact.intersection(obstacle).area < 1e-6
    assert expanded.intersection(obstacle).area < 1e-6

    _, _, layout_cx, layout_cy = _layout_bounds_public(compact, [obstacle])
    _, _, layout_ex, layout_ey = _layout_bounds_public(expanded, [obstacle])
    footprint_c = layout_cx * layout_cy
    footprint_e = layout_ex * layout_ey
    assert footprint_c < footprint_e, "fixture: compact layout has smaller footprint"

    free_c = _largest_continuous_free_area(
        bin_w, bin_h, margin, layout_cx, layout_cy, compact, occupied_union
    )
    free_e = _largest_continuous_free_area(
        bin_w, bin_h, margin, layout_ex, layout_ey, expanded, occupied_union
    )
    assert free_e > free_c, "fixture: expanded layout leaves more continuous free area"

    score_c = _placement_score(
        compact,
        bin_w,
        bin_h,
        margin=margin,
        footprint=footprint_c,
        layout_maxx=layout_cx,
        layout_maxy=layout_cy,
        occupied_union=occupied_union,
    )
    score_e = _placement_score(
        expanded,
        bin_w,
        bin_h,
        margin=margin,
        footprint=footprint_e,
        layout_maxx=layout_ex,
        layout_maxy=layout_ey,
        occupied_union=occupied_union,
    )
    assert score_e < score_c

    legacy_c = (footprint_c, -free_c, score_c[2], score_c[3], score_c[4])
    legacy_e = (footprint_e, -free_e, score_e[2], score_e[3], score_e[4])
    assert legacy_c < legacy_e, "footprint-first legacy ordering would prefer compact layout"


def test_largest_continuous_free_area_uses_geometry_with_many_obstacles() -> None:
    bin_w, bin_h, margin = 600.0, 600.0, 5.0
    obstacles = [box(10 + 40 * i, 10, 30 + 40 * i, 590) for i in range(12)]
    occupied_union = unary_union(obstacles)
    piece = box(0, 0, 80, 80)
    placed = translate(piece, xoff=520, yoff=520)

    _, _, layout_maxx, layout_maxy = _layout_bounds_public(placed, obstacles)
    geometric = _largest_continuous_free_area(
        bin_w,
        bin_h,
        margin,
        layout_maxx,
        layout_maxy,
        placed,
        occupied_union,
    )
    assert geometric > 50_000.0


def test_place_long_strip_prefers_near_horizontal_orientation() -> None:
    obstacle = box(0, 0, 220, 420)
    strip = box(0, 0, 200, 35)

    placement = place_with_rotation(
        strip,
        500.0,
        500.0,
        margin=0.0,
        obstacles=[obstacle],
    )

    assert placement is not None
    assert placement.rotation_deg <= 10.0 or placement.rotation_deg >= 350.0


def test_nest_multi_bin_packs_rectangles_on_one_sheet() -> None:
    pieces = [box(0, 0, 180, 120), box(0, 0, 180, 120), box(0, 0, 180, 120), box(0, 0, 180, 120)]
    stocks = [SheetStockSpec(width_mm=500.0, height_mm=500.0, quantity=None, sort_order=0)]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=5.0,
        kerf_mm=0.0,
        sheet_gap_mm=15.0,
        time_limit_sec=30.0,
    )

    assert not result.orphans
    assert len(result.sheets) == 1


def _layout_bounds_public(placed, occupied: list) -> tuple[float, float, float, float]:
    minx, miny, maxx, maxy = placed.bounds
    for obstacle in occupied:
        o_minx, o_miny, o_maxx, o_maxy = obstacle.bounds
        minx = min(minx, o_minx)
        miny = min(miny, o_miny)
        maxx = max(maxx, o_maxx)
        maxy = max(maxy, o_maxy)
    return minx, miny, maxx, maxy
