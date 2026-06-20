# [REQ-FIT-NEST-002] Nest pipeline context, seeds, and run_pipeline entry point.
from __future__ import annotations

import math
import time as _time
from dataclasses import dataclass, field

from shapely.geometry import Polygon

from nesting_engine.nest_objective import LayoutScore, layout_score_with_orphans, score_nested_layout
from nesting_engine.nest_types import MultiBinResult, NestedSheet, OrphanPiece, SheetStockSpec
from nesting_engine.sheet_stocks_config import stocks_in_consumption_order


@dataclass
class WallClockEtaEstimator:
    """[REQ-FIT-JOB-001] Stable, monotonically-decreasing ETA for thorough nesting.

    Primary mode (time_limit_sec provided — thorough mode):
        eta = max(0, time_limit_sec - elapsed)
    This is a simple countdown anchored to the real wall clock — guaranteed
    monotonically decreasing, never jumps around.

    Fallback mode (time_limit_sec is None):
        eta = elapsed × (100 - smoothed_pct) / smoothed_pct
    Uses EWMA-smoothed percent (α = 0.3) to absorb sudden jumps. Requires
    at least 3 seconds of elapsed time and 5 % progress before emitting.

    A monotonic cap ensures the returned value never increases once set.

    Pre-conditions:
        time_limit_sec > 0 when provided
    Post-conditions:
        update() returns None when no meaningful estimate is available yet.
        update() returns a non-negative int otherwise.
    """

    time_limit_sec: float | None
    _start: float = field(init=False)
    _smoothed_pct: float = field(default=0.0, init=False)
    _last_eta: int | None = field(default=None, init=False)
    _ALPHA: float = field(default=0.3, init=False, repr=False)

    def __post_init__(self) -> None:
        self._start = _time.monotonic()

    def update(self, percent: int) -> int | None:
        """Feed current percent (0..100) and return eta_sec, or None if no estimate yet."""
        if percent <= 0:
            return self._last_eta

        pct = float(min(100, percent))
        # EWMA smoothing absorbs sudden percent jumps
        if self._smoothed_pct <= 0.0:
            self._smoothed_pct = pct
        else:
            self._smoothed_pct = self._ALPHA * pct + (1.0 - self._ALPHA) * self._smoothed_pct

        elapsed = _time.monotonic() - self._start

        if self._smoothed_pct >= 99.9:
            self._last_eta = 0
            return 0

        if self.time_limit_sec is not None:
            # Reliable countdown: monotonically decreasing by construction
            raw_eta = max(0.0, self.time_limit_sec - elapsed)
        else:
            # Fallback: need enough elapsed time and progress to project
            if elapsed < 3.0 or self._smoothed_pct < 5.0:
                return self._last_eta
            remaining_pct = 100.0 - self._smoothed_pct
            raw_eta = elapsed * remaining_pct / self._smoothed_pct

        eta = max(0, round(raw_eta))
        # Monotonic cap: once set, ETA never increases
        if self._last_eta is not None and eta > self._last_eta:
            eta = self._last_eta
        self._last_eta = eta
        return eta


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
    from nesting_engine.nest_orientation import apply_orientation_profile

    active_seed = seed or default_seed()
    assert ctx.margin_mm >= 0 and ctx.kerf_mm >= 0 and ctx.sheet_gap_mm >= 0, "non-negative job parameters"
    assert ctx.sheet_stocks, "at least one sheet stock required"
    if ctx.time_limit_sec is not None:
        assert ctx.time_limit_sec > 0.0, "time_limit_sec must be positive when set"

    # [REQ-FIT-NEST-002] Apply orientation profile pre-rotation when seed requests it.
    if active_seed.orientation_profile != "as_extracted":
        ref_stock = ctx.sheet_stocks[0]
        pieces = apply_orientation_profile(
            ctx.pieces,
            active_seed.orientation_profile,
            sheet_width_mm=ref_stock.width_mm,
            sheet_height_mm=ref_stock.height_mm,
        )
    else:
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
    from nesting_engine.nest_sheet_assignment import assignment_seeds

    # [REQ-FIT-NEST-002] Prepend multi-sheet assignment seeds in thorough mode.
    seeds = list(assignment_seeds(ctx.pieces, ctx.sheet_stocks, margin_mm=ctx.margin_mm))
    seeds.extend(
        generate_seeds(
            len(ctx.pieces),
            ctx.pieces,
            max_seeds=ctx.max_seeds,
            enable_orientation_profiles=True,
        )
    )

    # Deduplicate seeds by (piece_order, orientation_profile) and cap to max_seeds
    seen_seeds = set()
    unique_seeds = []
    for seed in seeds:
        key = (seed.piece_order, seed.orientation_profile)
        if key not in seen_seeds:
            seen_seeds.add(key)
            unique_seeds.append(seed)
    unique_seeds = unique_seeds[:ctx.max_seeds]

    # [REQ-FIT-JOB-001] Stable ETA: wall-clock countdown anchored to real start time.
    eta = WallClockEtaEstimator(time_limit_sec=ctx.time_limit_sec)
    n_seeds = len(unique_seeds)

    def _report_optimizing(pct: int) -> None:
        if ctx.progress_reporter is None:
            return
        bounded = min(95, max(10, pct))
        ctx.progress_reporter.report("optimizing", bounded, eta_sec=eta.update(bounded))

    best: NestPipelineResult | None = None
    for i, seed in enumerate(unique_seeds):
        thorough_seed = NestSeed(
            name=seed.name,
            piece_order=seed.piece_order,
            orientation_profile=seed.orientation_profile,
            enable_void_pack=True,
            enable_local_search=True,
        )
        candidate = run_pipeline(ctx, seed=thorough_seed)
        # Report after each seed — percent advances linearly through 10..70
        seed_pct = 10 + round(60 * (i + 1) / max(1, n_seeds))
        _report_optimizing(seed_pct)
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

    # [REQ-FIT-JOB-001] Pass eta estimator so local search reports per-iteration.
    return local_search_pipeline_result(
        ctx,
        best,
        max_iterations=ctx.max_local_search_iterations,
        eta_estimator=eta,
    )
