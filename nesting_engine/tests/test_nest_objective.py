# [REQ-FIT-NEST-002] Global layout objective comparator tests.
from __future__ import annotations

from nesting_engine.nest_objective import LayoutScore, SheetScore, compare_layouts, layout_better_than


def _score(
    *,
    sheet_count: int,
    waste: float,
    footprint: float,
    maxy: float,
    free: float = 0.0,
    min_y: float = 0.0,
    min_x: float = 0.0,
) -> LayoutScore:
    sheet = SheetScore(
        free_area_mm2=free,
        footprint_mm2=footprint,
        layout_maxy=maxy,
        min_y=min_y,
        min_x=min_x,
        waste_mm2=waste,
    )
    return LayoutScore(
        sheet_count=sheet_count,
        total_waste_mm2=waste,
        total_footprint_mm2=footprint,
        max_layout_maxy=maxy,
        min_min_y=min_y,
        min_min_x=min_x,
        total_free_area_mm2=free,
        sheets=(sheet,) if sheet_count > 0 else (),
    )


def test_compare_layouts_prefers_fewer_sheets() -> None:
    fewer = _score(sheet_count=1, waste=100.0, footprint=200.0, maxy=50.0)
    more = _score(sheet_count=2, waste=10.0, footprint=50.0, maxy=40.0)
    assert compare_layouts(fewer, more) < 0
    assert layout_better_than(fewer, more)


def test_compare_layouts_then_waste_then_footprint() -> None:
    low_waste = _score(sheet_count=1, waste=50.0, footprint=200.0, maxy=50.0)
    high_waste = _score(sheet_count=1, waste=80.0, footprint=100.0, maxy=40.0)
    assert compare_layouts(low_waste, high_waste) < 0

    smaller_fp = _score(sheet_count=1, waste=50.0, footprint=120.0, maxy=50.0)
    larger_fp = _score(sheet_count=1, waste=50.0, footprint=180.0, maxy=40.0)
    assert compare_layouts(smaller_fp, larger_fp) < 0


def test_compare_layouts_tie_is_zero() -> None:
    left = _score(sheet_count=1, waste=10.0, footprint=20.0, maxy=5.0, free=100.0)
    right = _score(sheet_count=1, waste=10.0, footprint=20.0, maxy=5.0, free=100.0)
    assert compare_layouts(left, right) == 0
