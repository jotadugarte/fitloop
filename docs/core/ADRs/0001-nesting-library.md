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

**P3 integration (2026-05-17):** **`nesting_engine/nest_libnest2d.py`** uses **`python-libnest2d`** (`pynest2d`) for single-bin batch placement (`nest_sheet`) and binding proofs. Multi-bin orchestration (`nest_multi_bin`) uses libnest2d where applicable; obstacle-aware per-piece placement with margin/kerf remains in **`nest_placement.py`** (Shapely sweep) until libnest2d exposes equivalent obstacle semantics.

### Positive consequences

- Production path aligns with industry tooling (Cura/Prusa ecosystem)
- Holes and any-angle rotation remain in scope for MVP
- P0 delivers testable proof + ADR without delaying Rails/Python scaffold

### Negative consequences

- **Build complexity:** Prebuilt `python-libnest2d` wheels on Linux x86_64; source builds may need `cmake`, Boost — see `docs/DEPLOY.md`.
- **Hybrid placement:** Obstacle/margin edge cases still use Shapely sweep in `nest_placement.py` (scores placements by **largest continuous free area** first, layout footprint second — see SPEC REQ-FIT-NEST-002); full libnest2d obstacle parity is future work.
- **Fallback:** If libnest2d regresses in production, open ADR-0002 before changing architecture.

## Limits (spike vs production — 2026-05-17)

| Capability | P0 spike / binding tests | P3 production (`nest_libnest2d` + CLI) |
|------------|--------------------------|----------------------------------------|
| Holes | Yes (`binding_spike_nest`) | Yes (libnest2d) |
| Any-angle rotation | Yes (libnest2d NFP / BLP) | Yes |
| Multi-bin / SheetStock order | No | Yes (`nest_multi_bin`, REQ-FIT-NEST-002) |
| Kerf / margin | No | Yes (`nest_placement` + `nest_bin`) |
| 600s best-so-far | No | Yes (`time_limit_sec`, REQ-FIT-NEST-003) |
| Deploy / CI | — | `docs/DEPLOY.md`, `.github/workflows/ci.yml` `nesting_engine` job |

## More information

- Binding / production tests: `nesting_engine/tests/test_libnest2d_binding.py`, `nesting_engine/tests/test_nest_libnest2d.py`
- ADR parity: `nesting_engine/tests/test_nest_spike.py`
- Package pin: `python-libnest2d==0.1.3` in repo `requirements.txt`
- Session: `.agenticguild/active_sessions/task_libnest2d-integration.md`
