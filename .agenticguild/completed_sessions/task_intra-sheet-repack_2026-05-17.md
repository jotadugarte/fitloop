# Explore: Repack intra-lámina / compactación post-batch

**Status:** Implementation planning (start-task Phase 2)  
**Classification:** Feature  
**Opened:** 2026-05-17  
**REQ anchors:** REQ-FIT-NEST-002 (placement scoring), ADR-0001 (libnest2d boundaries)

---

## Problem statement (from user)

Real nesting job on **5 sheets 1000×900 mm** shows **large internal voids** on individual sheets (e.g. sheets 2 and 4 in preview). The recent **full-sheet epic** optimizes **sheet count** (consolidate + inter-sheet repack), not **intra-sheet layout quality**.

**Hypothesis:** After libnest2d batch placement per sheet, pieces are valid but **not compacted** and **not re-scored** with Fitloop’s **largest continuous free area** criterion (`nest_placement._largest_continuous_free_area`). Internal holes remain even when a full-sheet re-nest might pack tighter or shift pieces to enlarge one contiguous free region.

---

## Architectural context (read-only)

| Layer | Today | Gap |
|-------|--------|-----|
| `nest_libnest2d.nest_sheet` / `nest_sheet_with_obstacles` | Batch libnest2d; own packing heuristic | No post-batch compact; no free-area scoring |
| `nest_placement.py` | Per-piece Shapely + `_largest_continuous_free_area` + `_compact_toward_origin` | Used in fallback / legacy paths, not after batch on a filled sheet |
| `nest_multi_bin` pipeline | fill → consolidate → inter-sheet | **No intra-sheet repack phase** |

**SPEC drift:** `SPEC.md` REQ-FIT-NEST-002 still says “full-sheet libnest2d with kerf/obstacles is future work” — outdated after epic; separate doc fix.

---

## Success criteria (agreed)

1. **Primary:** Close **internal voids** on each sheet — maximize **largest continuous free area** (REQ-FIT-NEST-002 primary metric).
2. **Opportunistic inter-sheet (during compact):** While re-nesting sheet *S*, if a piece from another sheet *T* (same stock) fits on *S* after repack, **move it** to *S* (reduces sheet count when possible; not the main driver but required when space appears).
3. **Mechanism:** **Full re-nest** of all pieces currently on the target sheet via libnest2d batch path; **rollback** to prior layout if free-area score regresses or placement count drops.
4. **Time budget:** Single **global** `deadline` / `time_limit_sec` only — no separate per-sheet cap; phase stops when deadline hits (best-so-far kept).
5. **Tie-breakers:** layout footprint, then bottom-left (existing REQ-FIT-NEST-002 order).
6. **Invariants:** margin, kerf, no overlaps, all pieces inside usable bin.
7. **Tests:** invariants + score does not regress on accepted repacks; synthetic fixtures OK — **not** golden x/y.

---

## Open questions (remaining)

1. **Trigger:** Run repack on **every** non-empty sheet under deadline, or skip trivial sheets (e.g. 1 piece)? *(Default proposal: every sheet with ≥2 pieces.)*
2. **Inter-sheet phase order:** Confirm `inter_sheet` stays **after** both intra passes (proposed pipeline below).
3. **Fallback:** If libnest2d re-nest ties on score, try Shapely `_compact_toward_origin` per piece before rollback? *(Optional v1.1 — flag in plan.)*

## Pipeline order (agreed)

```
fill → intra_sheet_repack → consolidate → intra_sheet_repack → inter_sheet_local_search
```

Both intra passes share the same implementation and acceptance rules (global deadline).

---

## Risks

- libnest2d re-batch optimizes **its** metric, not guaranteed to improve `_largest_continuous_free_area` → rollback mandatory.
- Re-nest may place **fewer** pieces → rollback.
- Pulling pieces from other sheets during intra repack may **duplicate** logic with `_inter_sheet_local_search` — need one coherent story to avoid double work / oscillation.
- Integer-mm quantization may block small gains.

---

## Domain model

| Entity | Responsibility | Invariants |
|--------|----------------|------------|
| `SheetLayout` | One bin + placed piece instances | All polygons ⊆ usable rectangle; pairwise kerf clearance |
| `FreeAreaScore` | mm² of largest connected component of `usable \ occupied` | Non-negative; comparable across layouts of same sheet size |
| `IntraSheetRepackAttempt` | Re-nest all pieces on sheet *S*; optional **candidate pulls** from other sheets (same `stock_id`) | If accepted: `placed_count` on *S* increases or `FreeAreaScore` strictly increases; else rollback |
| `RepackRollback` | Snapshot of placements before attempt | Restored on regression or deadline skip mid-sheet |

**Value objects:** `FreeAreaScoreMm2` (float), `StockId` (str), `SheetIndex` (int), `Deadline` (monotonic clock).

---

## Proposed phase (draft — for discussion)

**`_intra_sheet_repack_search`** (name TBD):

- For each sheet (under global deadline), collect pieces on sheet + try adding one piece at a time from **later** sheets (same stock) if re-nest improves free area or absorbs the piece.
- Each attempt: `nest_sheet` / `nest_sheet_with_obstacles` on full piece set for that bin size.
- Score with `nest_placement._largest_continuous_free_area`; accept iff score improves **or** same score with smaller footprint **or** extra piece absorbed without score loss.
- Else restore snapshot.

Does **not** replace consolidate/inter-sheet; **complements** them for void closure.

---

## Acceptance fixture (real DXF)

**Source (local):** `xf-test-temp/archivo corte peluo.dxf`  
**For CI:** copy into `nesting_engine/tests/fixtures/archivo_corte_peluo.dxf` (kebab name, no spaces).  
**Layers (observed):** `CORTE` (21 entities), `MARCADO` (131), plus `GRABADO`, `Contexto`, `Parqueo`, `PUERTA`.  
**Fitloop selection (confirmed):** **`CORTE` only** for nesting in the peluo acceptance job.

**Integration test style (not golden xy):**

- Run `nest_multi_bin` with user’s sheet params (1000×900, margin/kerf from job).
- Assert **per-sheet** `largest_continuous_free_area` does not decrease vs baseline pipeline **without** intra phase, **or** sheet count decreases.
- Mark `@pytest.mark.slow` if runtime > few seconds.

## Scratchpad

- User priority: **void closure** > sheet count, but sheet count wins when pull fits during compact.

---

## Decision log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-17 | Scope = intra-sheet repack / post-batch compact | User request |
| 2026-05-17 | **Primary goal** = close internal voids (free-area metric) | User (1) |
| 2026-05-17 | **Opportunistic pull** from other sheets when repack makes room | User (1) |
| 2026-05-17 | **Full re-nest** per sheet + **rollback** on regression | User (2) |
| 2026-05-17 | **Global** time limit only | User (3) |
| 2026-05-17 | No customer job fixture required | User (4) — clarified |
| 2026-05-17 | **post-fill + post-consolidate** intra repack (two passes) | User |
| 2026-05-17 | Real DXF: `xf-test-temp/archivo corte peluo.dxf` → copy to test fixtures | User |
| 2026-05-17 | Acceptance job uses layer **`CORTE` only** | User |

## Dark corners (architect notes)

| Risk | Why it hurts | Mitigation in plan |
|------|----------------|-------------------|
| **No sheet-level score helper today** | `_largest_continuous_free_area` is written for incremental placement (one new piece + obstacles), not whole-sheet layout | Add `score_sheet_layout(...)` in `nest_placement.py` (union of all placed polygons vs usable bin) |
| **libnest2d optimizes its own objective** | Full re-nest may **not** increase continuous free area → rollback → no visible fix for red voids | Document limitation; optional Shapely compact fallback on tie; acceptance test proves improvement on **peluo** or synthetic hole fixture |
| **Overlap with `_inter_sheet_local_search`** | Both move pieces between sheets via repack | Intra pass scores **free area** + void closure; inter-sheet remains **merge sparse donor** heuristic — run inter-sheet **last** |
| **Oscillation** | Pull on pass 1, consolidate moves, pass 2 pulls back | Accept if rare; cap attempts per sheet; always rollback on regression |
| **128-piece batch cap** | `nest_sheet` limit | peluo ~21 on CORTE — OK; guard if layer has more |
| **Deadline partial progress** | Some sheets repacked, others not | Same as today: best-so-far; report unchanged |
| **Non-determinism** | libnest2d may vary slightly run-to-run | Tests compare **with vs without** intra phase in same run, not absolute coordinates |
| **DXF not in repo yet** | CI won’t see `xf-test-temp/` unless copied | Commit sanitized copy under `tests/fixtures/` (check license/size) |

---

## Implementation plan

<implementation_plan>

<step id="1" status="complete">
**Test:** Add `test_score_sheet_layout_largest_continuous_free_area` in `nesting_engine/tests/test_nest_placement_scoring.py` — synthetic sheet with two separated obstacles; assert `score_sheet_layout` matches direct `_largest_continuous_free_area` for the union layout. Tag `[REQ-FIT-NEST-002]`.
**Implement:** `score_sheet_layout(bin_width_mm, bin_height_mm, margin_mm, placed_polygons) -> tuple[float, float]` in `nest_placement.py` (free-area mm² + layout footprint). Pre: non-negative dims, polygons list (may be empty). Post: score ≥ 0; empty layout → full usable area.
</step>

<step id="2" status="complete">
**Test:** Add `test_layout_better_than` unit tests — strict free-area increase accepts; tie on free area uses footprint then bottom-left ordering per REQ-FIT-NEST-002. Tag `[REQ-FIT-NEST-002]`.
**Implement:** `_layout_better_than(baseline_score, candidate_score) -> bool` helper (or equivalent tuple compare) shared by intra repack acceptance.
</step>

<step id="3" status="complete">
**Test:** Add `test_intra_sheet_repack_improves_free_area_on_synthetic_hole` — fixture: 3+ rectangles on one sheet with deliberate internal void; stub or call real `_intra_sheet_repack_search`; assert accepted repack strictly increases `score_sheet_layout` and all placement invariants hold. Tag `[REQ-FIT-NEST-002]`.
**Implement:** `_intra_sheet_repack_search(sheets, pieces, stocks, margin_mm, kerf_mm, sheet_gap_mm, deadline) -> list[NestedSheet]` — per sheet with ≥2 pieces (skip trivial), snapshot placements, full re-nest via `nest_sheet` / `nest_sheet_with_obstacles`, score with `score_sheet_layout`, rollback on regression or fewer pieces placed. Pre: valid `NestedSheet` list. Post: same piece count per sheet unless pull absorbed; margin/kerf/no-overlap invariants preserved.
</step>

<step id="4" status="complete">
**Test:** Extend `test_nest_multi_bin_runs_epic_phases_in_locked_order` (or sibling) — monkeypatch phase hooks; assert order `fill → intra_sheet_repack → consolidate → intra_sheet_repack → inter_sheet`. Tag `[REQ-FIT-NEST-002]`.
**Implement:** Wire two `_intra_sheet_repack_search` calls into `nest_multi_bin` at agreed pipeline points; cooperative `deadline` checks between sheets.
</step>

<step id="5" status="complete">
**Test:** Add `test_intra_sheet_repack_pulls_piece_from_later_sheet` — two same-stock sheets; after repack on sheet 0, a piece from sheet 1 is absorbed without free-area regression. Tag `[REQ-FIT-NEST-002]`.
**Implement:** During repack on sheet *S*, try adding one piece at a time from **later** sheets (same `stock_sort_order` / dimensions via `_sheets_allow_piece_transfer`); accept only if `_layout_better_than` or extra piece with non-worse score.
</step>

<step id="6" status="complete">
**Test:** Add `test_intra_sheet_repack_respects_global_deadline` — monkeypatch monotonic clock; partial sheets repacked, best-so-far returned, no crash. Tag `[REQ-FIT-NEST-002]`.
**Implement:** Ensure mid-sheet attempts honor `deadline`; restore snapshot when time expires before accept.
</step>

<step id="7" status="complete">
**Test:** Copy `xf-test-temp/archivo corte peluo.dxf` → `nesting_engine/tests/fixtures/archivo_corte_peluo.dxf` (if not present); add `@pytest.mark.slow` integration test — `nest_multi_bin` with CORTE-only layer, 1000×900 sheets; assert per-sheet `score_sheet_layout` does not decrease vs pipeline **without** intra phase **or** sheet count decreases. No golden x/y. Tag `[REQ-FIT-NEST-002]`.
**Implement:** Test-only fixture commit; minimal DXF loader reuse from existing tests.
</step>

<step id="8" status="complete">
**Test:** Run full `nesting_engine` pytest suite; fix regressions.
**Implement:** Update `docs/core/SPEC.md` REQ-FIT-NEST-002 bullet that still claims “full-sheet libnest2d … is future work” (doc drift from epic). Optional: note intra-sheet repack in `SYSTEM_ARCHITECTURE.md` §nesting pipeline if a phase diagram exists.
</step>

</implementation_plan>
