# [REQ-FIT-NEST-002] Real DXF acceptance: intra-sheet repack vs baseline pipeline.
from __future__ import annotations

from pathlib import Path

import nesting_engine.nest_libnest2d as nest_libnest2d
import pytest

from nesting_engine.nest_bin import SheetStockSpec
from nesting_engine.nest_libnest2d import (
    _indices_by_descending_area,
    _intra_sheet_repack_search,
    _nest_across_stocks,
    _time_limit_deadline,
)
from nesting_engine.nest_placement import placed_polygon, score_sheet_layout
from nesting_engine.nest_types import NestedSheet, apply_kerf
from nesting_engine.piece_loader import load_pieces

PELUO_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "archivo_corte_peluo.dxf"
_LAYER = "CORTE"
_EPS_MM2 = 1.0


def _per_sheet_free_areas_mm2(
    sheets: list[NestedSheet],
    pieces: list[object],
    *,
    margin_mm: float,
    kerf_mm: float,
) -> list[float]:
    ordered = sorted(sheets, key=lambda sheet: (sheet.stock_sort_order, sheet.sheet_index))
    areas: list[float] = []
    for sheet in ordered:
        polys = [
            placed_polygon(apply_kerf(pieces[row.piece_index], kerf_mm), row.placement)
            for row in sheet.pieces
        ]
        free_area, _footprint = score_sheet_layout(
            sheet.width_mm,
            sheet.height_mm,
            margin_mm,
            polys,
        )
        areas.append(free_area)
    return areas


def _peluo_fill_sheets(
    pieces: list[object],
    stocks: list[SheetStockSpec],
    *,
    margin_mm: float,
    kerf_mm: float,
    sheet_gap_mm: float,
    time_limit_sec: float,
) -> list[NestedSheet]:
    deadline = _time_limit_deadline(time_limit_sec)
    remaining = _indices_by_descending_area(pieces)
    sheets, _remaining, _warnings = _nest_across_stocks(
        pieces,
        remaining,
        stocks,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=sheet_gap_mm,
        time_limit_sec=time_limit_sec,
        deadline=deadline,
    )
    assert not _remaining, "peluo CORTE pieces must fit within time limit"
    return sheets


@pytest.mark.slow
def test_nest_multi_bin_peluo_intra_phase_improves_or_maintains_layout() -> None:
    """[REQ-FIT-NEST-002] Post-fill peluo layouts: intra repack does not regress per-sheet free area."""
    assert PELUO_FIXTURE.is_file(), f"missing fixture DXF: {PELUO_FIXTURE}"

    warnings: list[str] = []
    pieces = load_pieces(
        [str(PELUO_FIXTURE)],
        [_LAYER],
        curve_tolerance_mm=0.25,
        warnings=warnings,
    )
    assert len(pieces) >= 2, "peluo CORTE layer must yield multiple pieces"

    stocks = [SheetStockSpec(width_mm=1000.0, height_mm=900.0, quantity=None, sort_order=0)]
    margin_mm = 5.0
    kerf_mm = 2.0
    sheet_gap_mm = 15.0
    time_limit_sec = 120.0

    fill_sheets = _peluo_fill_sheets(
        pieces,
        stocks,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=sheet_gap_mm,
        time_limit_sec=time_limit_sec,
    )
    assert sum(len(sheet.pieces) for sheet in fill_sheets) == len(pieces)

    deadline = _time_limit_deadline(time_limit_sec)

    def _passthrough_intra(sheets: list[NestedSheet], *args: object, **kwargs: object) -> list[NestedSheet]:
        return sheets

    original = nest_libnest2d._intra_sheet_repack_search
    nest_libnest2d._intra_sheet_repack_search = _passthrough_intra
    try:
        baseline_sheets = _intra_sheet_repack_search(
            fill_sheets,
            pieces,
            stocks,
            margin_mm=margin_mm,
            kerf_mm=kerf_mm,
            sheet_gap_mm=sheet_gap_mm,
            deadline=deadline,
        )
    finally:
        nest_libnest2d._intra_sheet_repack_search = original

    with_intra = _intra_sheet_repack_search(
        fill_sheets,
        pieces,
        stocks,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
        sheet_gap_mm=sheet_gap_mm,
        deadline=deadline,
    )

    assert sum(len(sheet.pieces) for sheet in with_intra) == len(pieces)

    if len(with_intra) < len(baseline_sheets):
        return

    baseline_areas = _per_sheet_free_areas_mm2(
        baseline_sheets,
        pieces,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    intra_areas = _per_sheet_free_areas_mm2(
        with_intra,
        pieces,
        margin_mm=margin_mm,
        kerf_mm=kerf_mm,
    )
    assert len(intra_areas) == len(baseline_areas)

    for improved, base in zip(intra_areas, baseline_areas, strict=True):
        assert improved + _EPS_MM2 >= base, (
            "per-sheet largest continuous free area must not decrease when sheet count is unchanged"
        )
