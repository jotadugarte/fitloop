# [REQ-FIT-NEST-002] Local search operators for thorough nesting mode.
from __future__ import annotations

import time

from nesting_engine.nest_pipeline import NestPipelineContext, NestPipelineResult, NestSeed, pick_better_pipeline_result, run_pipeline
from nesting_engine.piece_loader import piece_polygon


def local_search_pipeline_result(
    ctx: NestPipelineContext,
    baseline: NestPipelineResult,
    *,
    max_iterations: int,
) -> NestPipelineResult:
    from nesting_engine.nest_libnest2d import multi_bin_layout_has_significant_overlaps

    assert max_iterations >= 0
    best = baseline
    deadline = _deadline_from_ctx(ctx)
    for _ in range(max_iterations):
        if _time_limit_exceeded(deadline):
            break
        neighbor = _rotate_smallest_strip_seed(ctx, best)
        if neighbor is None:
            break
        candidate = run_pipeline(ctx, seed=neighbor)
        if multi_bin_layout_has_significant_overlaps(
            candidate.sheets,
            ctx.pieces,
            kerf_mm=ctx.kerf_mm,
        ):
            break
        best = pick_better_pipeline_result(best, candidate)
    return best


def _rotate_smallest_strip_seed(
    ctx: NestPipelineContext,
    baseline: NestPipelineResult,
) -> NestSeed | None:
    if not baseline.sheets:
        return None
    sheet = baseline.sheets[0]
    if len(sheet.pieces) < +2:
        return None
    smallest = min(
        sheet.pieces,
        key=lambda row: piece_polygon(ctx.pieces[row.piece_index]).area,
    )
    order = [row.piece_index for row in sheet.pieces if row.piece_index != smallest.piece_index]
    order.append(smallest.piece_index)
    profile = "cardinal_90" if smallest.placement.rotation_deg == 0.0 else "as_extracted"
    return NestSeed(
        name=f"local_rotate_{smallest.piece_index}",
        piece_order=tuple(order),
        orientation_profile=profile,
        enable_void_pack=True,
        enable_local_search=False,
    )


def _deadline_from_ctx(ctx: NestPipelineContext) -> float | None:
    from nesting_engine.nest_libnest2d import _time_limit_deadline

    return _time_limit_deadline(ctx.time_limit_sec)


def _time_limit_exceeded(deadline: float | None) -> bool:
    return deadline is not None and time.monotonic() >= deadline
