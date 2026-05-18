# [REQ-FIT-NEST-002] Full-sheet libnest2d with fixed obstacles (kerf + margin invariants).
from __future__ import annotations

from shapely.geometry import box

from nesting_engine.nest_libnest2d import ObstacleAwareSheetResult, nest_sheet_with_obstacles
from nesting_engine.nest_placement import Placement, placed_polygon
from nesting_engine.nest_types import apply_kerf

_EPS_MM = 1e-6


def _obstacle_footprint(
    piece: object,
    *,
    placement: Placement,
    kerf_mm: float,
) -> object:
    fit = apply_kerf(piece, kerf_mm)
    return placed_polygon(fit, placement)


def _assert_placed_fit_bin(
    piece: object,
    placement: Placement,
    *,
    bin_width_mm: float,
    bin_height_mm: float,
    margin_mm: float,
    kerf_mm: float,
) -> object:
    fit = apply_kerf(piece, kerf_mm)
    placed = placed_polygon(fit, placement)
    minx, miny, maxx, maxy = placed.bounds
    assert minx >= margin_mm - _EPS_MM
    assert miny >= margin_mm - _EPS_MM
    assert maxx <= bin_width_mm - margin_mm + _EPS_MM
    assert maxy <= bin_height_mm - margin_mm + _EPS_MM
    return placed


def _assert_kerf_clearance(poly_a: object, poly_b: object, kerf_mm: float) -> None:
    """Minimum gap between raw piece outlines (obstacles are kerf-buffered footprints)."""
    gap = poly_a.distance(poly_b)
    assert gap >= kerf_mm - 0.2
    assert not (poly_a.intersects(poly_b) and not poly_a.touches(poly_b))


def _assert_fit_clear_of_obstacles(fit_placed: object, obstacles: list[object]) -> None:
    for obstacle in obstacles:
        assert not (fit_placed.intersects(obstacle) and not fit_placed.touches(obstacle))


def test_nest_sheet_with_obstacles_places_fit_pieces_and_reports_unplaced() -> None:
    # [REQ-FIT-NEST-002] Obstacle blocks lower-left; two small rects fit; one oversized stays unplaced.
    bin_w, bin_h = 300.0, 300.0
    margin_mm = 5.0
    kerf_mm = 4.0

    obstacles = [
        _obstacle_footprint(
            box(0, 0, 100, 100),
            placement=Placement(x=margin_mm, y=margin_mm, rotation_deg=0.0),
            kerf_mm=kerf_mm,
        )
    ]
    pieces = [
        box(0, 0, 40, 40),
        box(0, 0, 40, 40),
        box(0, 0, 250, 250),
    ]

    result = nest_sheet_with_obstacles(
        pieces,
        bin_width_mm=bin_w,
        bin_height_mm=bin_h,
        obstacles=obstacles,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )

    assert isinstance(result, ObstacleAwareSheetResult)
    assert result.unplaced_indices == [2]
    assert set(result.placements.keys()) == {0, 1}

    raw_placed: list[object] = []
    for piece_index, resolved in result.placements.items():
        placement = resolved.placement
        fit_placed = _assert_placed_fit_bin(
            pieces[piece_index],
            placement,
            bin_width_mm=bin_w,
            bin_height_mm=bin_h,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
        )
        _assert_fit_clear_of_obstacles(fit_placed, obstacles)
        raw_placed.append(placed_polygon(pieces[piece_index], placement))

    _assert_kerf_clearance(raw_placed[0], raw_placed[1], kerf_mm)


def test_nest_sheet_with_obstacles_returns_all_unplaced_when_no_room() -> None:
    # [REQ-FIT-NEST-002] Entire usable bin covered by obstacles → explicit empty placement map.
    bin_w, bin_h = 200.0, 200.0
    margin_mm = 2.0
    kerf_mm = 0.0
    usable_w = bin_w - 2.0 * margin_mm
    usable_h = bin_h - 2.0 * margin_mm

    obstacles = [box(margin_mm, margin_mm, margin_mm + usable_w, margin_mm + usable_h)]
    pieces = [box(0, 0, 10, 10), box(0, 0, 12, 12)]

    result = nest_sheet_with_obstacles(
        pieces,
        bin_width_mm=bin_w,
        bin_height_mm=bin_h,
        obstacles=obstacles,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )

    assert result.placements == {}
    assert sorted(result.unplaced_indices) == [0, 1]
