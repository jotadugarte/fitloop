# Task: Full-sheet libnest2d epic (kerf + obstacles + heuristics)

**Source:** `docs/ROADMAP.md` (backlog, lines 105–109)  
**REQ:** REQ-FIT-NEST-002 · **ADR:** 0001  
**Skill:** explore-task · **Created:** 2026-05-17

---

## Decisions (locked this session)

| # | Topic | Decision |
|---|--------|----------|
| 1 | Scope | **Full epic:** (A) full-sheet `nest_sheet` per bin with production `margin_mm` + `kerf_mm` + obstacles, replacing per-piece Shapely fill in `_place_on_one_sheet`; (B) reorder / move pieces between sheets (local search under time cap); (C) extend `_consolidate_sheets` repack. |
| 2 | Success criteria | **Invariant tests only** (no golden x/y): fit inside bin, kerf clearance, margin at sheet edge, JSON/report contract. **Synthetic fixtures** assert **sheet count** and **largest continuous free region** (mm²) where meaningful. |
| 3 | Time budget | **Single cap:** project `nesting_time_limit_sec` / CLI `time_limit_sec` only — no per-phase sub-budgets. Best-so-far on timeout (REQ-FIT-JOB-001 / partial). |
| 4 | libnest2d limits / fallback | **Locked default:** per-sheet full-sheet `nest_sheet` on candidate indices; **unplaced** stay in pending queue (next sheet / heuristics). **No kerf/margin downgrade.** Shapely per-piece **fallback only** if libnest2d unavailable or batch places zero for a non-empty candidate set. Integer-mm quantization accepted (~1 mm feature floor). Holes + rotation per `capabilities()`. |
| 4b | Max pieces per `nest_sheet` | **`_MAX_PIECES = 128`** (raise from 64 in `nest_libnest2d.py`; multi-bin batches or splits if &gt; 128). |
| 5 | Roadmap coupling | **Independent** of v1.1 auto-split (`REQ-FIT-SPLIT-001`). |
| 6 | Phase order (single `deadline`) | **(1)** Initial multi-bin nest (full-sheet fill) → **(2)** `_consolidate_sheets` (extended) → **(3)** Inter-sheet local search. |

---

## libnest2d limits (reference)

| Constraint | Notes |
|------------|--------|
| Integer-mm vertices | `_ring_to_points`; features &lt; ~1 mm may collapse |
| 128 pieces / `nest_sheet` | `_MAX_PIECES`; split/batch if exceeded |
| Partial batch | Unplaced → pending; no silent rule relaxation |
| Shapely fallback | Only zero-placement batch or binding unavailable |

---

## Domain Model

### SheetStockSpec
- **Responsibility:** One bin type in multi-bin job (dimensions, sort order, finite or infinite quantity).
- **Invariants:** `width_mm`, `height_mm` &gt; 0; `sort_order` defines open order; `quantity is None` ⇒ unlimited sheets.

### NestedSheet
- **Responsibility:** One physical sheet instance with placed pieces and layout offset in combined DXF.
- **Invariants:** All `PlacedPiece` polygons fit usable area (margin inset); `stock_sort_order` matches a configured stock; `offset_x_mm` respects `sheet_gap_mm` between sheets.

### PlacedPiece / Placement
- **Responsibility:** Link source `piece_index` to final pose (`x_mm`, `y_mm`, `rotation_deg`).
- **Invariants:** `placed_polygon(apply_kerf(piece), placement)` does not intersect other placed obstacles closer than kerf semantics allow; margin only vs sheet edges.

### ObstacleSet (conceptual)
- **Responsibility:** Union of already-placed **kerf-buffered** footprints on a sheet during fill.
- **Invariants:** Grows monotonically during per-sheet fill; libnest2d path must treat prior placements as fixed obstacles equivalent to today’s `occupied` list in `_place_on_one_sheet`.

### MultiBinResult
- **Responsibility:** Terminal output: `sheets`, `orphans`, `warnings` (e.g. time limit).
- **Invariants:** Orphan reasons documented; warnings include time-limit message when deadline hit.

### Value objects / branded types
| Name | Wraps | Rule |
|------|--------|------|
| `MarginMm` | `float` | ≥ 0; sheet-edge inset only |
| `KerfMm` | `float` | ≥ 0; applied via `apply_kerf` before placement |
| `TimeLimitSec` | `float \| None` | &gt; 0 when set; monotonic `deadline` for all epic phases |
| `LargestFreeAreaMm2` | `float` | ≥ 0; from usable sheet minus union of placed obstacles (test metric) |
| `SheetCount` | `int` | ≥ 0; synthetic fixture assertion target |

---

## Epic workstreams (draft)

### A — Full-sheet libnest2d fill (core)
- Replace inner loop of `_place_on_one_sheet` (Shapely `_place_piece_on_sheet`) with batch `nest_sheet` / NFP–BLP when obstacle model is wired.
- Kerf: continue `apply_kerf` before libnest2d items; margin: usable bin = sheet minus `2 * margin_mm` (existing `nest_sheet` pattern).
- Obstacles: model placed pieces so libnest2d cannot overlap them (approach TBD in plan: fixed items, bin holes, or pre-subtract — must match REQ-FIT-NEST-002 scoring tie-break where Shapely path still applies).

### B — Inter-sheet local search
- After initial `_nest_across_stocks`, under same `deadline`: try moving pieces from high-index / sparse sheets to earlier sheets if fit improves sheet count or free area metric.
- Must respect `SheetStockSpec.quantity` and stock dimensions.

### C — Extend `_consolidate_sheets`
- Today: merge donor → target same dimensions via `_move_pieces_into_sheet` (still per-piece Shapely).
- Extend: trigger after B or use full-sheet repack on nearly-full donors/targets; goal fewer total sheets.

### Test strategy (agreed)
- New synthetic scenarios: N rectangles / L-shapes designed so per-piece greedy uses more sheets than batch nest.
- Assert: `len(result.sheets) <= expected_max`, kerf/margin invariants, optional `largest_free_area_mm2 >= threshold` on last sheet.
- No golden coordinates.

---

## Risks

| Risk | Mitigation |
|------|------------|
| libnest2d has no first-class “obstacle” API | Spike in plan: fixed placed `Item`s vs Shapely-only obstacles; reject if violates architecture. |
| Integer quantization changes feasibility | Keep existing small-piece tests; add regression when touching quantization. |
| Epic scope vs single time limit | Locked order: fill → consolidate → inter-sheet search; all check `deadline`. |
| Scoring parity (largest free area) | SPEC secondary tie-break may differ from libnest2d internal objective — document acceptable delta or post-process compaction in `nest_placement`. |

---

## Scratchpad

- Current fill: `_place_on_one_sheet` → per-index Shapely with `obstacles=occupied`.
- `nest_sheet` already: kerf buffer + margin shrink + `nest_blp` for multi-piece single bin.
- `_consolidate_sheets`: pairwise same-size merge only.
- Prerequisite done: libnest2d integration + free-area-first scoring in `nest_placement.py`.

---

## Session metadata

- **Classification:** Feature
- **Roadmap item:** Full-sheet libnest2d placement (kerf + obstacles) — `docs/ROADMAP.md` L105–109
- **Status:** Spec locked (2026-05-17)

---

<implementation_plan>

## Preconditions (global)

- All nesting changes stay in `nesting_engine/` (no Rails nesting math — `SYSTEM_ARCHITECTURE.md` §3).
- `margin_mm` = sheet-edge inset only; `kerf_mm` via `apply_kerf` before obstacles (`REQ-FIT-NEST-002`).
- `nest_bin` continues to delegate to `nest_libnest2d`; no import cycles (`nest_bin` → lazy import in `nest_multi_bin` only per project rules).
- Reuse `_largest_continuous_free_area` from `nest_placement.py` for test metrics (do not duplicate geometry logic).
- Tag new/changed tests with `[REQ-FIT-NEST-002]`; assert invariants only (fit, kerf, margin, sheet count, free area) — no golden x/y.

## Post-conditions (epic complete)

- `nest_multi_bin` pipeline order: **initial fill → `_consolidate_sheets` (extended) → inter-sheet local search**, all respecting single `deadline`.
- `_place_on_one_sheet` fill uses **full-sheet libnest2d** with kerf + obstacles; Shapely per-piece only on agreed fallback paths.
- `_MAX_PIECES == 128`; batches split when pending &gt; 128 on one sheet attempt.
- Synthetic fixtures prove **fewer sheets** (or equal with higher last-sheet free area) vs greedy per-piece baseline where designed.
- `capabilities()` / ADR-0001 note updated for obstacle-aware full-sheet path (addendum paragraph, no new library).

<step id="1" status="complete">**[REQ-FIT-NEST-002]** Add failing test: `_MAX_PIECES` allows 128 polygons in `nest_sheet` (synthetic small rectangles on large bin). Run `pytest nesting_engine/tests/test_nest_libnest2d.py -k max_pieces` — expect FAIL at 64 limit.</step>

<step id="2" status="complete">Implement `_MAX_PIECES = 128` in `nest_libnest2d.py` (and spike assert if shared). Green step 1 only.</step>

<step id="3" status="complete">**[REQ-FIT-NEST-002]** Add failing test module `test_nest_full_sheet_obstacles.py`: given bin + margin + kerf, place obstacle footprints then nest remaining pieces via new API (e.g. `nest_sheet_with_obstacles` or extended `nest_sheet` kwargs). Assert: all placed fit usable area; pairwise kerf clearance via existing invariant helpers; unplaced indices returned explicitly.</step>

<step id="4" status="complete">**Spike (max 1 step, no ADR):** Implement obstacle model for libnest2d (preferred: pre-placed fixed `Item`s at locked transforms; alternative: subtract from usable bin only if kerf-safe). Document chosen approach in ADR-0001 addendum. Make step 3 green. If no kerf-safe libnest2d obstacle API exists, stop and record blocker in `.agenticguild/tech_debt.md` — do not violate architecture with Ruby or margin-as-kerf hacks.</step>

<step id="5" status="complete">**[REQ-FIT-NEST-002]** Add failing synthetic fixture: multi-rectangle job where per-piece greedy fill would use ≥2 sheets but full-sheet batch fits on 1 (document piece set in test). Assert `len(result.sheets) &lt;= 1` and kerf/margin invariants.</step>

<step id="6" status="complete">Refactor `_place_on_one_sheet`: replace inner Shapely loop with full-sheet batch (obstacles from `occupied`, pending batch ≤128, split batches). Unplaced indices return to pending. Shapely `_place_piece_on_sheet` fallback only when batch places zero for non-empty candidate set. Green step 5.</step>

<step id="7" status="complete">**[REQ-FIT-NEST-002]** Add failing test: extended `_consolidate_sheets` merges a nearly-empty donor into target using **full-sheet repack** (same stock size), reducing total sheet count. Use synthetic L-shapes/rectangles.</step>

<step id="8" status="complete">Implement extended consolidate (full-sheet repack path + existing pairwise merge). Respect `deadline` if passed through (thread `deadline` into consolidate from `nest_multi_bin`). Green step 7.</step>

<step id="9" status="complete">**[REQ-FIT-NEST-002]** Add failing test: inter-sheet local search moves pieces from last sparse sheet to earlier sheet, reducing `len(sheets)` under same stocks/time limit. Assert invariants + optional `_largest_continuous_free_area` on donor sheet improves or sheet removed.</step>

<step id="10" status="complete">Implement `_inter_sheet_local_search` (or equivalent) after consolidate in `nest_multi_bin`; honor `SheetStockSpec.quantity`, stock dimensions, and `deadline`. Green step 9.</step>

<step id="11" status="complete">**[REQ-FIT-NEST-002]** Add failing integration test: end-to-end `nest_multi_bin` runs phases in locked order and respects `time_limit_sec` (warning + best-so-far when deadline forced with tiny limit). No golden coordinates.</step>

<step id="12" status="complete">Wire `nest_multi_bin`: phase 1 fill → phase 2 extended `_consolidate_sheets` → phase 3 inter-sheet search; single `deadline` throughout. Green step 11.</step>

<step id="13" status="complete">Update `docs/core/ADRs/0001-nesting-library.md` (hybrid → obstacle-aware full-sheet), `docs/core/DATA_FLOW_MAP.md` §1 one-liner, and `docs/ROADMAP.md` checkbox when epic verified. Run full `pytest nesting_engine/`.</step>

</implementation_plan>
