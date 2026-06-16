# [REQ-FIT-NEST-002] Pipeline context and default seed regression tests.
from __future__ import annotations

from shapely.geometry import box

from nesting_engine.nest_bin import nest_multi_bin
from nesting_engine.nest_pipeline import NestPipelineContext, default_seed, run_pipeline
from nesting_engine.nest_types import SheetStockSpec


def test_run_pipeline_default_seed_matches_fast_multi_bin() -> None:
    pieces = [box(0, 0, 40, 20), box(0, 0, 30, 30), box(0, 0, 25, 15)]
    stocks = [SheetStockSpec(width_mm=200.0, height_mm=200.0, quantity=1, sort_order=0)]
    ctx = NestPipelineContext(
        pieces=pieces,
        sheet_stocks=stocks,
        margin_mm=1.0,
        kerf_mm=0.0,
        sheet_gap_mm=0.0,
        time_limit_sec=30.0,
    )
    pipeline = run_pipeline(ctx, seed=default_seed())
    fast = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=1.0,
        kerf_mm=0.0,
        sheet_gap_mm=0.0,
        time_limit_sec=30.0,
        optimization_mode="fast",
    )
    assert len(pipeline.sheets) == len(fast.sheets)
    assert len(pipeline.orphans) == len(fast.orphans)
