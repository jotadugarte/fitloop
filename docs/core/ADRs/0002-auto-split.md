# ADR-0002: Opt-in auto-split for orphan pieces (v1.1)

**Status:** Accepted  
**Date:** 2026-05-19  
**REQ:** REQ-FIT-SPLIT-001

## Context and problem statement

After a partial nest, oversized or unplaced pieces appear as orphans. Users need a guided way to split pieces in CAD off-app or via Fitloop straight-cut planning before re-nesting, without auto-modifying source DXFs or conflating kerf with split cut planes.

## Decision drivers

- Ephemeral workspace only; per-orphan opt-in (`pending` | `system_split` | `manual` | `resolved`)
- Stable `Nesting::PieceKey` across re-nests (not `piece_index` alone)
- Two CLI modes: `plan_splits` (preview JSON only) vs normal nest with `excluded_piece_keys` + `derived_pieces`
- Preview mandatory before accept; mother excluded after accept
- Sheet inventory or nest cancel invalidates draft previews

## Decision outcome

**Chosen:** Rails orchestrates split workflow; Python `split_planner.py` performs hole-aware straight-cut partitioning; inline SVG previews from engine geometry.

### Workflow

1. User marks orphan `system_split` → `Nesting::SplitPlanJob` → CLI `mode: plan_splits` → `SplitProposal` draft.
2. User accepts preview → `DerivedPiece` rows + mother `piece_key` excluded on next nest.
3. CTA **Nest with updated pieces** enqueues normal nest with derived geometry in `config.json`.
4. Manual path: 3-step CAD copy + **I updated my DXF** → pre-flight → `resolved` when mother no longer extracts.

### Positive consequences

- Clear separation: Rails state/UI, Python geometry and nest
- Re-nest uses same CLI contract with exclusion/injection fields
- `split_not_feasible` surfaced without blocking other resolution paths

### Negative consequences

- Cancel/sheet change drops draft previews (user must re-plan)
- Cut lines in `nested.dxf` use mother-local coordinates from accepted proposals (reference only)

## Validation

- RSpec: orphan resolutions, split proposals, config builder, manual confirm, nest CTA, cancel invalidation
- pytest: `test_split_planner.py`, `test_cli_plan_splits.py`, `test_piece_loader_split.py`, nest pipeline derived labels/cuts
