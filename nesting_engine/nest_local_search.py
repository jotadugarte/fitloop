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
    """[REQ-FIT-NEST-002] Iterative local search using two operators round-robin.

    Operators:
      1. _rotate_smallest_strip_seed  — intra-sheet: push smallest piece to end of order.
      2. _pull_from_donor_sheet_seed  — inter-sheet: pull largest piece off last (sparse) sheet.

    Pre-condition: max_iterations >= 0
    Post-condition: result.score <= baseline.score (lexicographic; never regresses)
    """
    from nesting_engine.nest_libnest2d import multi_bin_layout_has_significant_overlaps

    assert max_iterations >= 0
    best = baseline
    deadline = _deadline_from_ctx(ctx)
    operators = [_rotate_smallest_strip_seed, _pull_from_donor_sheet_seed]
    for iteration in range(max_iterations):
        if _time_limit_exceeded(deadline):
            break
        op = operators[iteration % len(operators)]
        neighbor = op(ctx, best)
        if neighbor is None:
            # Try the other operator before giving up
            other_op = operators[(iteration + 1) % len(operators)]
            neighbor = other_op(ctx, best)
        if neighbor is None:
            break
        candidate = run_pipeline(ctx, seed=neighbor)
        if multi_bin_layout_has_significant_overlaps(
            candidate.sheets,
            ctx.pieces,
            kerf_mm=ctx.kerf_mm,
        ):
            continue
        best = pick_better_pipeline_result(best, candidate)
    return best


def _rotate_smallest_strip_seed(
    ctx: NestPipelineContext,
    baseline: NestPipelineResult,
) -> NestSeed | None:
    """Intra-sheet operator: send the smallest piece on first sheet to the end of the order."""
    if not baseline.sheets:
        return None
    sheet = baseline.sheets[0]
    if len(sheet.pieces) < +2:
        return None
    smallest = min(
        sheet.pieces,
        key=lambda row: piece_polygon(ctx.pieces[row.piece_index]).area,
    )
    order = [index for index in range(len(ctx.pieces)) if index != smallest.piece_index]
    order.append(smallest.piece_index)
    profile = "cardinal_90" if smallest.placement.rotation_deg == 0.0 else "as_extracted"
    return NestSeed(
        name=f"local_rotate_{smallest.piece_index}",
        piece_order=tuple(order),
        orientation_profile=profile,
        enable_void_pack=True,
        enable_local_search=False,
    )


def _pull_from_donor_sheet_seed(
    ctx: NestPipelineContext,
    baseline: NestPipelineResult,
) -> NestSeed | None:
    """[REQ-FIT-NEST-002] Inter-sheet operator: pull the largest piece off the sparsest last sheet.

    Picks the last (sparsest) sheet as the donor.  Moves its largest piece to the front of the
    ordering so the main fill phase has the best chance of placing it onto an earlier sheet.

    Pre-condition: baseline.sheets has >= 2 sheets
    Post-condition: returned seed has a valid permutation of all piece indices
    """
    if len(baseline.sheets) < 2:
        return None

    # Find donor: last sheet (typically the sparsest)
    donor_sheet = baseline.sheets[-1]
    if not donor_sheet.pieces:
        return None

    # Pull the largest piece from the donor sheet to the front of the order
    donor_piece = max(
        donor_sheet.pieces,
        key=lambda row: piece_polygon(ctx.pieces[row.piece_index]).area,
    )
    pulled_index = donor_piece.piece_index

    # Build new order: pulled piece first, then all others in area-descending order
    remaining = [
        index for index in range(len(ctx.pieces)) if index != pulled_index
    ]
    remaining.sort(key=lambda i: piece_polygon(ctx.pieces[i]).area, reverse=True)
    order = [pulled_index] + remaining

    return NestSeed(
        name=f"local_pull_donor_{pulled_index}",
        piece_order=tuple(order),
        orientation_profile="as_extracted",
        enable_void_pack=True,
        enable_local_search=False,
    )


def _deadline_from_ctx(ctx: NestPipelineContext) -> float | None:
    from nesting_engine.nest_libnest2d import _time_limit_deadline

    return _time_limit_deadline(ctx.time_limit_sec)


def _time_limit_exceeded(deadline: float | None) -> bool:
    return deadline is not None and time.monotonic() >= deadline
