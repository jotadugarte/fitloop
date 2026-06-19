# ADR-0011: Thorough nesting optimization objective and modes

**Status:** Accepted  
**Date:** 2026-06-14  
**REQ:** REQ-FIT-NEST-002

## Context and problem statement

`nest_multi_bin` uses a fixed heuristic pipeline (fill → repack → consolidate → inter-sheet search → gravity → flip). Layout quality depends on piece order and local minima. Workshop users need better packing on irregular jobs (frames with holes, thin bars) without breaking the existing fast path used in production.

## Decision drivers

- Single comparable objective for multi-start, void-pack, and local-search acceptance
- `fast` mode must preserve legacy behavior (one default seed)
- `thorough` mode may spend extra CPU within `time_limit_sec`
- Invariant-based tests; no golden x/y coordinates

## Decision outcome

**Chosen option:** Add `nesting_engine/nest_objective.py` as the global layout comparator and optional `optimization_mode` (`fast` | `thorough`) on the CLI job config.

### Global objective (lexicographic)

1. **Sheet count** (fewer is better; orphans penalized as extra virtual sheets)
2. **Total waste** (usable sheet area minus placed material per sheet)
3. **Total layout footprint** (sum of per-sheet bounding envelopes)
4. **Max layout max-Y** across sheets (prefer lower vertical envelope)
5. **Total largest continuous free area** (tie-break; higher is better)
6. **Bottom-left** (`min_y`, then `min_x`)

Per-sheet placement during Shapely fallback and intra-sheet repack continues to use `score_sheet_layout` (largest continuous free area, then footprint, then bottom-left) as documented in REQ-FIT-NEST-002.

### Thorough pipeline extensions

When `optimization_mode` is `thorough`:
 
 1. Multi-start over piece order and orientation profiles (`nest_ordering`, `nest_orientation`). In v2, this includes:
    - Orientation profiles: `as_extracted`, `cardinal_90`, and `bar_parallel_long_edge`.
    - Configurable shuffle seed pool with base `FITLOOP_NESTING_SHUFFLE_SEED_BASE` (default 42) and pool size `shuffle_count` (default 4) to generate random seed variations.
 2. Void detection and strip packing (`nest_voids`, `nest_void_pack`) after intra-sheet repack, before gravity
 3. Local search on top-K layouts (`nest_local_search`) using two operators round-robin:
    - Intra-sheet: `_rotate_smallest_strip_seed` (sends the smallest piece of first sheet to end of ordering).
    - Inter-sheet (v2): `_pull_from_donor_sheet_seed` (pulls the largest piece off the sparsest last sheet to the front of the order to pack it on an earlier sheet).
 4. Multi-sheet assignment heuristics (`nest_sheet_assignment`) before fill when stocks allow. In v2, `assignment_seeds()` generates and prepends FFD sheet-aware ordering seeds.
 
 `fast` runs one pipeline invocation with the legacy default seed (area-descending order, as-extracted orientation).

### Positive consequences

- Measurable improvement path for bar-in-void cases without replacing libnest2d
- Clear revert point via checkpoint commit and mode flag

### Negative consequences

- Longer CPU time in `thorough` mode; bounded by existing `time_limit_sec`
- More modules to maintain in `nesting_engine/`

## Limits

- No exact global solver; heuristics only
- Rails `Nesting::JobParameters` may omit `optimization_mode` until product exposes UI; Python defaults to `fast`
