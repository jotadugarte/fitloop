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

**P0 spike:** In-repo **`nesting_engine/nest_spike.py`** uses a bounded Shapely rotation sweep (15° steps) to prove:

- Polygons with holes are accepted as valid pieces
- A piece that only fits after rotation (e.g. 90×20 mm into 50×100 mm bin at 90°) is placed correctly

This spike is **not** the shipping nest algorithm. It validates geometry assumptions and documents integration risk before binding libnest2d.

### Positive consequences

- Production path aligns with industry tooling (Cura/Prusa ecosystem)
- Holes and any-angle rotation remain in scope for MVP
- P0 delivers testable proof + ADR without delaying Rails/Python scaffold

### Negative consequences

- **Build complexity:** `pynest2d`/libnest2d may require `cmake`, Boost, and system packages on deploy hosts — document in deploy notes (P4).
- **Spike ≠ nest quality:** No multi-bin, kerf, margin, or time limit in `nest_spike`; P3 must implement `REQ-FIT-NEST-002`.
- **Fallback:** If libnest2d integration fails in P3, open ADR-0002 for evaluated fallback (e.g. SVGnest CLI) before changing architecture.

## Limits (v1 spike vs P3 production)

| Capability | P0 `nest_spike` | P3 `nest` (target) |
|------------|-----------------|---------------------|
| Holes | Yes (Shapely polygon) | Yes (libnest2d) |
| Any-angle rotation | 15° step sweep | libnest2d + time cap |
| Multi-bin / SheetStock order | No | Yes (REQ-FIT-NEST-002) |
| Kerf / margin | No | Yes |
| 600s best-so-far | No | Yes |

## More information

- P0 tests: `nesting_engine/tests/test_nest_spike.py`
- Extraction (separate): `nesting_engine/extract.py` — REQ-FIT-EXT-001
- Session decisions: `.agenticguild/active_sessions/task_dxf-nesting.md` (D10, D13, D27)
