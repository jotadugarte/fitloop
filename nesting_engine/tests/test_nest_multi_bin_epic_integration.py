# [REQ-FIT-NEST-002] End-to-end epic pipeline: fill → intra repack → consolidate → intra → inter-sheet.
from __future__ import annotations

import nesting_engine.nest_libnest2d as nest_libnest2d
import pytest
from shapely.geometry import box

from nesting_engine.nest_bin import SheetStockSpec
from nesting_engine.nest_libnest2d import nest_multi_bin


def test_nest_multi_bin_runs_epic_phases_in_locked_order(monkeypatch: pytest.MonkeyPatch) -> None:
    """[REQ-FIT-NEST-002] `nest_multi_bin` runs fill, intra repack (×2), consolidate, then inter-sheet search."""
    phase_calls: list[str] = []
    original_fill = nest_libnest2d._nest_across_stocks
    original_intra = nest_libnest2d._intra_sheet_repack_search
    original_consolidate = nest_libnest2d._consolidate_sheets
    original_search = nest_libnest2d._inter_sheet_local_search

    def tracked_fill(*args, **kwargs):
        phase_calls.append("fill")
        return original_fill(*args, **kwargs)

    def tracked_intra(*args, **kwargs):
        phase_calls.append("intra_sheet_repack")
        return original_intra(*args, **kwargs)

    def tracked_consolidate(*args, **kwargs):
        phase_calls.append("consolidate")
        return original_consolidate(*args, **kwargs)

    def tracked_search(*args, **kwargs):
        phase_calls.append("inter_sheet")
        return original_search(*args, **kwargs)

    monkeypatch.setattr(nest_libnest2d, "_nest_across_stocks", tracked_fill)
    monkeypatch.setattr(nest_libnest2d, "_intra_sheet_repack_search", tracked_intra)
    monkeypatch.setattr(nest_libnest2d, "_consolidate_sheets", tracked_consolidate)
    monkeypatch.setattr(nest_libnest2d, "_inter_sheet_local_search", tracked_search)

    pieces = [box(0, 0, 40, 20) for _ in range(4)]
    stocks = [SheetStockSpec(width_mm=200.0, height_mm=200.0, quantity=None, sort_order=0)]

    nest_multi_bin(
        pieces,
        stocks,
        margin_mm=1.0,
        kerf_mm=0.0,
        sheet_gap_mm=0.0,
        time_limit_sec=30.0,
    )

    assert phase_calls == [
        "fill",
        "intra_sheet_repack",
        "consolidate",
        "intra_sheet_repack",
        "inter_sheet",
    ]


def test_nest_multi_bin_respects_time_limit_sec_with_best_so_far(monkeypatch: pytest.MonkeyPatch) -> None:
    """[REQ-FIT-NEST-002] Cooperative deadline returns partial placements and a time-limit warning."""
    tick = {"count": 0}

    def fake_monotonic() -> float:
        tick["count"] += 1
        if tick["count"] <= 10:
            return 0.0
        return 100.0

    monkeypatch.setattr(nest_libnest2d.time, "monotonic", fake_monotonic)

    pieces = [box(0, 0, 12, 12) for _ in range(6)]
    stocks = [SheetStockSpec(width_mm=25.0, height_mm=25.0, quantity=None, sort_order=0)]

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=0.0,
        kerf_mm=0.0,
        sheet_gap_mm=0.0,
        time_limit_sec=0.1,
    )

    assert any("time_limit" in warning.lower() for warning in result.warnings)
    placed_count = sum(len(sheet.pieces) for sheet in result.sheets)
    assert placed_count >= 1
    assert placed_count + len(result.orphans) == len(pieces)
