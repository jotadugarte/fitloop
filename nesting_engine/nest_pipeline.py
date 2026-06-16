# [REQ-FIT-NEST-002] Nest pipeline context, seeds, and run_pipeline entry point.
from __future__ import annotations

from dataclasses import dataclass, field

from shapely.geometry import Polygon

from nesting_engine.nest_objective import LayoutScore, layout_score_with_orphans, score_nested_layout
from nesting_engine.nest_types import MultiBinResult, NestedSheet, OrphanPiece, SheetStockSpec
from nesting_engine.sheet_stocks_config import stocks_in_consumption_order


@dataclass(frozen=True)
class NestSeed:
    name: str = "default"
    piece_order: tuple[int, ...] | None = None
    orientation_profile: str = "as_extracted"
    enable_void_pack: bool = False
    enable_local_search: bool = False


@dataclass
class NestPipelineContext:
    pieces: list[Polygon]
    sheet_stocks: list[SheetStockSpec]
    margin_mm: float
    kerf_mm: float
    sheet_gap_mm: float
    time_limit_sec: float | None
    progress_reporter: object | None = None
    max_seeds: int = 16
    max_local_search_iterations: int = 12


@dataclass(frozen=True)
class NestPipelineResult:
    sheets: list[NestedSheet]
    orphans: list[OrphanPiece]
    warnings: list[str]
    score: LayoutScore
    seed_name: str
    metadata: dict = field(default_factory=dict)

    def to_multi_bin_result(self) -> MultiBinResult:
        return MultiBinResult(sheets=self.sheets, orphans=self.orphans, warnings=self.warnings)


def default_seed() -> NestSeed:
    return NestSeed(name="default")


def _resolve_piece_order(pieces: list[Polygon], seed: NestSeed) -> list[int]:
    from nesting_engine.nest_libnest2d import _indices_by_descending_area

    if seed.piece_order is None:
        return _indices_by_descending_area(pieces)

    order = list(seed.piece_order)
    expected = set(range(len(pieces)))
    assert set(order) == expected, "piece_order must be a permutation of piece indices"
    return order


def _reference_sheet_area(stocks: list[SheetStockSpec]) -> float:
    if not stocks:
        return 1.0
    return stocks[0].width_mm * stocks[0].height_mm


def run_pipeline(ctx: NestPipelineContext, *, seed: NestSeed | None = None) -> NestPipelineResult:
    from nesting_engine.nest_libnest2d import (
        _nest_across_stocks,
        _orphans_for_remaining,
        _report_pipeline_progress,
        _run_post_fill_phases,
        _time_limit_deadline,
        multi_bin_layout_has_significant_overlaps,
    )

    active_seed = seed or default_seed()
    assert ctx.margin_mm >= 0 and ctx.kerf_mm >= 0 and ctx.sheet_gap_mm >= 0, "non-negative job parameters"
    assert ctx.sheet_stocks, "at least one sheet stock required"
    if ctx.time_limit_sec is not None:
        assert ctx.time_limit_sec > 0.0, "time_limit_sec must be positive when set"

    pieces = ctx.pieces
    deadline = _time_limit_deadline(ctx.time_limit_sec)
    remaining_indices = _resolve_piece_order(pieces, active_seed)
    stocks = stocks_in_consumption_order(ctx.sheet_stocks)
    total_pieces = len(pieces)

    _report_pipeline_progress(
        ctx.progress_reporter,
        "fill",
        12,
        pieces_total=total_pieces,
        pieces_placed=0,
    )
    sheets, remaining_indices, warnings = _nest_across_stocks(
        pieces,
        remaining_indices,
        stocks,
        margin_mm=ctx.margin_mm,
        kerf_mm=ctx.kerf_mm,
        sheet_gap_mm=ctx.sheet_gap_mm,
        time_limit_sec=ctx.time_limit_sec,
        deadline=deadline,
        progress_reporter=ctx.progress_reporter,
        pieces_total=total_pieces,
    )
    placed_count = total_pieces - len(remaining_indices)
    _report_pipeline_progress(
        ctx.progress_reporter,
        "fill",
        55,
        pieces_total=total_pieces,
        pieces_placed=placed_count,
    )
    sheets = _run_post_fill_phases(
        sheets,
        pieces,
        stocks,
        margin_mm=ctx.margin_mm,
        kerf_mm=ctx.kerf_mm,
        sheet_gap_mm=ctx.sheet_gap_mm,
        deadline=deadline,
        progress_reporter=ctx.progress_reporter,
        pieces_total=total_pieces,
        pieces_placed=placed_count,
        enable_void_pack=active_seed.enable_void_pack,
    )
    orphans = _orphans_for_remaining(
        pieces,
        remaining_indices,
        stocks,
        margin_mm=ctx.margin_mm,
        kerf_mm=ctx.kerf_mm,
    )
    assert not multi_bin_layout_has_significant_overlaps(sheets, pieces, kerf_mm=ctx.kerf_mm), (
        "run_pipeline produced overlapping placements"
    )

    score = layout_score_with_orphans(
        sheets,
        pieces,
        margin_mm=ctx.margin_mm,
        orphan_count=len(orphans),
        reference_sheet_area_mm2=_reference_sheet_area(stocks),
    )
    return NestPipelineResult(
        sheets=sheets,
        orphans=orphans,
        warnings=warnings,
        score=score,
        seed_name=active_seed.name,
    )


def pick_better_pipeline_result(
    left: NestPipelineResult,
    right: NestPipelineResult,
) -> NestPipelineResult:
    from nesting_engine.nest_objective import compare_layouts

    if compare_layouts(left.score, right.score) <= 0:
        return left
    return right


def run_thorough_multi_bin(ctx: NestPipelineContext) -> NestPipelineResult:
    from nesting_engine.nest_local_search import local_search_pipeline_result
    from nesting_engine.nest_libnest2d import multi_bin_layout_has_significant_overlaps
    from nesting_engine.nest_ordering import generate_seeds

    best: NestPipelineResult | None = None
    for seed in generate_seeds(len(ctx.pieces), ctx.pieces, max_seeds=ctx.max_seeds):
        thorough_seed = NestSeed(
            name=seed.name,
            piece_order=seed.piece_order,
            orientation_profile=seed.orientation_profile,
            enable_void_pack=True,
            enable_local_search=True,
        )
        candidate = run_pipeline(ctx, seed=thorough_seed)
        if multi_bin_layout_has_significant_overlaps(
            candidate.sheets,
            ctx.pieces,
            kerf_mm=ctx.kerf_mm,
        ):
            continue
        if best is None:
            best = candidate
            continue
        best = pick_better_pipeline_result(best, candidate)

    if best is None:
        best = run_pipeline(ctx, seed=default_seed())
    top_results = local_search_pipeline_result(
        ctx,
        best,
        max_iterations=ctx.max_local_search_iterations,
    )
    return top_results
