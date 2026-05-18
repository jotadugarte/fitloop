# ADR-0001: Nesting engine library (libnest2d target)

**Status:** Accepted  
**Date:** 2026-05-16  
**REQ:** REQ-FIT-NEST-001

## Context and problem statement

Fitloop must nest irregular polygons with **holes** and **any-angle rotation** (see `docs/core/SPEC.md`, decisions D3, D13). Nesting math runs in Python (`nesting_engine/`), not in Rails. We need a library choice before implementing the P3 CLI nest pipeline.

## Decision drivers

- Hole-aware geometry (interior rings), not just bounding boxes
- Rotation not limited to 90° increments
- Deployable on the same host as Rails (WSL/Linux v1)
- Deterministic, testable spike in P0 without blocking on C++ toolchain
- Time-capped iterative nesting with best-so-far (D10, D19) — full behavior in P3

## Considered options

1. **libnest2d (via pynest2d / Cura stack)** — NFP-based 2D nesting, holes and rotation; requires native build or prebuilt bindings.
2. **rectpack / shelf heuristics** — Easy pip install; rectangles only, no holes, limited rotation.
3. **Custom Shapely heuristic only** — Full control; poor density; not acceptable as production solver.

## Decision outcome

**Chosen option:** **libnest2d** as the **production** nesting core for MVP v1 integration in P3.

**P0 spike (2026-05-16):** Validated hole-aware polygons and any-angle rotation via `binding_spike_nest` / tests in `test_libnest2d_binding.py`. The former `nest_spike.py` rotation sweep was removed in favor of production bindings.

**P3 integration (2026-05-17):** **`nesting_engine/nest_libnest2d.py`** uses **`python-libnest2d`** (`pynest2d`) for single-bin batch placement (`nest_sheet`) and binding proofs.

**Obstacle-aware full-sheet addendum (2026-05-17):** `nest_sheet_with_obstacles` models kerf-buffered footprints as **fixed `Item`s** via `markAsFixedInBin(0)` with vertices pre-positioned in the libnest2d frame (`translate(world, -frame_origin)`). Nestable pieces batch through `nest_blp` alongside fixed items. A piece is **unplaced** when `binId() < 0` or post-check shows margin violation / overlap with obstacles or prior placements — no kerf/margin downgrade.

**Full-sheet multi-bin epic (2026-05-18):** `nest_multi_bin` runs under one `time_limit_sec` deadline: (1) **fill** — `_place_on_one_sheet` uses full-sheet `nest_sheet` / `nest_sheet_with_obstacles` (batch ≤128 pieces) with Shapely per-piece fallback when batch places zero; (2) **intra-sheet repack** (×2, post-fill and post-consolidate) — `_intra_sheet_repack_search` full re-nests each bin with ≥2 pieces, accepts on `score_sheet_layout` / layout-score improvement or pull from a later same-stock sheet; (3) **consolidate** — pairwise merge plus `_try_repack_merge_sheets` for sparse donors; (4) **inter-sheet local search** — repack from last sparse sheet onto earlier same-size sheets. Shapely in `nest_placement.py` remains for fallback placement, whole-sheet scoring, and largest-free-area tie-breaks.

### Positive consequences

- Production path aligns with industry tooling (Cura/Prusa ecosystem)
- Holes and any-angle rotation remain in scope for MVP
- P0 delivers testable proof + ADR without delaying Rails/Python scaffold

### Negative consequences

- **Build complexity:** Prebuilt `python-libnest2d` wheels on Linux x86_64; source builds may need `cmake`, Boost — see `docs/DEPLOY.md`.
- **Hybrid fallback:** Shapely sweep in `nest_placement.py` is used only when libnest2d batch places zero pieces or for scoring tie-breaks (largest continuous free area — SPEC REQ-FIT-NEST-002).
- **Fallback:** If libnest2d regresses in production, open ADR-0002 before changing architecture.

## Limits (spike vs production — 2026-05-17)

| Capability | P0 spike / binding tests | P3 production (`nest_libnest2d` + CLI) |
|------------|--------------------------|----------------------------------------|
| Holes | Yes (`binding_spike_nest`) | Yes (libnest2d) |
| Any-angle rotation | Yes (libnest2d NFP / BLP) | Yes |
| Multi-bin / SheetStock order | No | Yes (`nest_multi_bin`, REQ-FIT-NEST-002) |
| Kerf / margin | No | Yes (`nest_types.apply_kerf`; full-sheet fill + obstacle `Item`s in `nest_libnest2d`) |
| Obstacle-aware full-sheet | No | Yes (`nest_sheet_with_obstacles`, `_MAX_PIECES` 128) |
| Multi-bin consolidate / inter-sheet | No | Yes (`_consolidate_sheets` repack + `_inter_sheet_local_search`) |
| Intra-sheet repack (void closure) | No | Yes (`_intra_sheet_repack_search`, post-fill and post-consolidate) |
| 600s best-so-far | No | Yes (`time_limit_sec`, REQ-FIT-NEST-003) |
| Deploy / CI | — | `docs/DEPLOY.md`, `.github/workflows/ci.yml` `nesting_engine` job |

## More information

- Binding / production tests: `nesting_engine/tests/test_libnest2d_binding.py`, `nesting_engine/tests/test_nest_libnest2d.py`, `nesting_engine/tests/test_nest_full_sheet_*.py`, `nesting_engine/tests/test_nest_multi_bin_epic_integration.py`
- ADR parity: `nesting_engine/tests/test_nest_spike.py`
- Package pin: `python-libnest2d==0.1.3` in repo `requirements.txt`
- Sessions: `task_libnest2d-integration.md`, `task_full-sheet-libnest2d-epic.md` (under `.agenticguild/active_sessions/`)
