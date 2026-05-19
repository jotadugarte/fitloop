# Task: Sheet stock consumption priority

**Roadmap:** Pending — Product/UX — `docs/ROADMAP.md` (Sheet stock consumption priority)  
**REQ anchors:** REQ-FIT-UI-001, REQ-FIT-DOM-001, REQ-FIT-NEST-002  
**Status:** Spec locked — handoff to `start-task`  
**Classification:** Feature

---

## Problem statement

Users cannot tell **in what order** the nesting engine will consume sheet types when they add more than one `SheetStock`. Priority is stored as hidden `sort_order` fields with **no visible column or controls** in the inventory table. The SPEC workflow W1 mentions “Stimulus sortable”, but the current UI only **appends rows** and reindexes `sort_order` by table row index on add/remove/save — there is no drag-and-drop and no explanatory copy.

**User goal:** Make consumption order **explicit in the UI**, with a clear default policy (finite before ∞) applied only when the user asks for it, while allowing manual ranking **within** the finite group (and implicitly within the ∞ group).

---

## Discovery log

### 2026-05-17 — Stakeholder answers (step 1.2)

| # | Topic | Decision |
|---|--------|----------|
| 1 | Pain | Order is opaque when adding multiple sheets; want **explicit UI** showing how consumption works. |
| 2 | Default policy | **Finite stocks first, then ∞**, via an **explicit button** (“Ordenar: finitos primero” / EN equivalent). Among **multiple finite** stocks, user must be able to set **relative priority** between them. |
| 3 | Manual vs auto | **Option A:** “Finitos primero” only **moves groups** (all finite above the single ∞ row); **preserves relative order among finites**; user may still drag rows afterward. |
| 4 | Tie-break | User-defined order among finites via drag (and preserved by finite-first button). |
| 5 | Scope | **Full stack:** Rails UI + i18n + tests **and** `nesting_engine` (tests/contract alignment; engine already sorts by `sort_order`). |
| 6 | Reorder UX | **Drag-and-drop** table rows (SortableJS or equivalent Stimulus pattern). |
| 7 | Inventory cap | **At most one** unlimited (`quantity: nil`) `SheetStock` per project; **unlimited count** of finite stocks (`quantity` ≥ 1). Enforce in model + UI + engine input validation. |

### 2026-05-17 — Round 2 (step 1.2 continued)

| # | Topic | Decision |
|---|--------|----------|
| Q3 (finite-first button) | **Confirmed: Option A** |
| Q6 (reorder) | **Confirmed: drag rows** |
| Q∞ cap | **Confirmed: max 1 unlimited sheet; n finite sheets** |
| Q7 (priority column + legend) | **Confirmed: yes** — column #1, #2, … + short copy “engine consumes top → bottom” (`en`/`es`). |
| Q8 (∞ placement) | **Auto-pin ∞ last** — not A/B/C from earlier list. Every time a **finite** stock is added, it is inserted **before** any unlimited row. The unlimited row is **always last** in consumption order, regardless of add/edit sequence. User may still drag to rank **finite** rows; ∞ cannot stay above finites (re-sink on add, after drag, and on save). |

### Placement rules (locked)

1. **Add finite:** insert at end of finite block (immediately before the single ∞ row, if present).
2. **Add unlimited:** append as last row (only if project has zero ∞ stocks).
3. **Drag:** reorder among finites freely; if ∞ row moved up, **snap back to last** on drop (or block invalid drop).
4. **Button “Ordenar: finitos primero”:** Option A among **finite rows only** (stable sort within finites + ensure ∞ at bottom — redundant for ∞ position but useful if user only wants to normalize finite relative order without manual drag).
5. **Save:** persist `sort_order` 0..n-1 matching visual order; server normalizes ∞ to `max(sort_order)` if client ever sends wrong order.

### Codebase audit (current behavior)

- **UI:** `sheet_inventory_controller.js` — composer add → `buildRow` → `sort_order = row index`; `reindexSortOrders()` on remove; **no** priority column, **no** reorder buttons, **no** SortableJS.
- **Save:** `ProjectsController#assign_sheet_stock_sort_orders!` sets `sort_order` from **non-destroyed association order** (0..n-1), overwriting any prior values.
- **Engine:** `nest_libnest2d` → `stocks = sorted(sheet_stocks, key=sort_order)`; existing test `test_libnest2d_finite_stock_then_next_sort_order`.
- **CLI:** `Nesting::ConfigBuilder` emits stocks `order(:sort_order)`.

**Gap vs roadmap:** Not engine algorithm — **UX + discoverability + explicit reorder + “finite first” action**.

---

## Open questions

_(None — discovery complete pending “listo para implementar”.)_

---

## Domain Model

### SheetStock (existing entity — behavior clarified)

- **Responsibility:** One sheet type in project inventory (dimensions, finite qty or ∞, consumption rank).
- **Invariants:**
  - `width_mm`, `height_mm` > 0.
  - `sort_order` is a **dense rank** 0..n-1 per project (unique, gapless after save).
  - **At most one** stock per project has `quantity: nil` (unlimited sheets for that type).
  - Zero or more stocks with `quantity` ≥ 1 (finite).
  - If an unlimited stock exists, its `sort_order` is **strictly greater** than every finite stock on the project (always consumed last).
  - Engine consumes stocks in **ascending `sort_order`**; finite `quantity` decrements per sheet opened; the single ∞ stock (if present) runs only after all finite stocks are exhausted or cannot place more pieces.
- **Value objects / branded types:** (no new DB columns anticipated)
  - `ConsumptionRank` — wraps Integer 0..n-1 (UI label “#1” = rank 0).
  - `SheetQuantity` — finite positive int OR unlimited (nil).

### Consumption policy (UI action, not persisted)

- **FiniteFirstPolicy** — ephemeral command: partition stocks into `{finite}` then `{infinite}`; preserve stable order within each partition; rewrite `sort_order`.

---

## Proposed UX (locked)

1. Column **“Prioridad”** (#1, #2, …) + drag handle; DnD for row order; Stimulus syncs `sort_order`.
2. Legend (i18n): engine consumes **top → bottom**.
3. **Auto-placement:** new finite → before ∞; new/edit ∞ → always last; drag cannot leave ∞ above finites.
4. Button **“Ordenar: finitos primero”** — stable reorder **among finite rows only** (Option A); ∞ stays last.
5. Composer: block second ∞ stock; i18n for cap and placement rules.
6. Model + `assign_sheet_stock_sort_orders!` / custom normalizer: enforce ∞ last and dense ranks on save.
7. Engine: validate config — at most one `quantity: null`; optional assert ∞ has max `sort_order` when multiple stocks present.
8. Docs: SPEC W1, DATA_FLOW_MAP, SCHEMA_REFERENCE, ROADMAP checkbox when shipped.
9. Tests: RSpec (model validation, add order, drag, save normalization); system spec DnD; pytest consumption order with multiple finites + one ∞.

---

## Risks

| Risk | Mitigation |
|------|------------|
| `assign_sheet_stock_sort_orders!` fights client-sent order | Ensure form row order matches visual order; only reindex on explicit client events or drop server-side overwrite if params carry explicit ranks. |
| SPEC W1 still says “Stimulus sortable” | Update SPEC + DATA_FLOW_MAP in same task (docs slice in plan). |
| Conflict with earlier “button only” for ∞ | **Resolved:** ∞ auto-last is automatic; button is for **finite-finite** ordering only. |
| Second unlimited stock added | Model + UI guard; engine assert/warn on duplicate `quantity: null` in one job. |
| Only one ∞ row — no “∞ group” reorder | Drag still moves the single ∞ row among finites; finite-first button pins it below all finites. |

---

## Implementation plan

<implementation_plan>

<step id="1" status="complete">
**Test:** Add `spec/models/sheet_stock_spec.rb` examples — project with two `quantity: nil` stocks fails validation; tag `[REQ-FIT-DOM-001]`.
**Implement:** `SheetStock` validation (or `Project` `validate` on nested attrs) — at most one unlimited stock per project; i18n error key under `activerecord.errors`.
</step>

<step id="2" status="complete">
**Test:** Add model spec — project with one finite (`sort_order: 1`) and one unlimited (`sort_order: 0`) fails until normalized; after `SheetStocks::NormalizeConsumptionOrder.call(project)` unlimited has highest `sort_order`. Tag `[REQ-FIT-DOM-001]`.
**Implement:** `app/services/sheet_stocks/normalize_consumption_order.rb` — dense ranks 0..n-1; all finites first ascending prior relative order; single ∞ last if present. Call from `ProjectsController` on create/update instead of blind `assign_sheet_stock_sort_orders!` index-only pass.
</step>

<step id="3" status="complete">
**Test:** Add `spec/requests/projects_sheet_inventory_spec.rb` — POST/PATCH project with attrs order `[∞, finite]`; assert persisted `sheet_stocks.order(:sort_order)` is `[finite, ∞]`. Tag `[REQ-FIT-UI-001]`.
**Implement:** Wire normalizer on save; ensure nested attributes order does not bypass ∞-last rule.
</step>

<step id="4" status="complete">
**Test:** Add `nesting_engine/tests/test_cli_sheet_stocks.py` (or extend existing CLI schema test) — `config.json` with two `quantity: null` entries fails fast with clear error. Tag `[REQ-FIT-NEST-002]`, `[REQ-FIT-CLI-001]`.
**Implement:** Validate `sheet_stocks` in CLI entry (`nest.py` / loader) — max one unlimited; if multiple stocks and one unlimited, assert its `sort_order` equals `max(sort_order)`.
</step>

<step id="5" status="complete">
**Test:** Add `test_multi_bin_consumes_finite_stocks_before_unlimited` in `nesting_engine/tests/test_nest_libnest2d.py` — two finite stocks (qty 1 each) + one unlimited; pieces only fit on unlimited size; assert first opened sheet uses first finite `stock_sort_order`. Tag `[REQ-FIT-NEST-002]`.
**Implement:** Only add engine-side guard/assert if step 4 validation insufficient; do **not** change `nest_multi_bin` phase order.
</step>

<step id="6" status="complete">
**Test:** Add failing system spec `spec/system/sheet_inventory_priority_spec.rb` — project form shows priority column header and consumption legend (`en`); tag `[REQ-FIT-UI-001]`.
**Implement:** Update `_sheet_inventory.html.erb` / `_sheet_stock_list_item.html.erb` — priority column (#1..n), drag handle column, legend copy; `config/locales/en.yml` + `es.yml`.
</step>

<step id="7" status="complete">
**Test:** Extend system spec — create finite + unlimited rows via UI; unlimited row displays last priority number after save. Tag `[REQ-FIT-UI-001]`.
**Implement:** Pin SortableJS via `config/importmap.rb` (+ vendor or jspm pin per project convention); Stimulus `sheet_inventory_controller` — Sortable on `<tbody>`; `reindexSortOrders()` on `onEnd`; **insert finite before ∞** in `buildRow`; on add unlimited append last; on drag end call `pinUnlimitedLast()`.
</step>

<step id="8" status="complete">
**Test:** System or request spec — click “Ordenar: finitos primero” reorders finite rows stable relative order and leaves ∞ last. Tag `[REQ-FIT-UI-001]`.
**Implement:** Toolbar button + `sortFiniteFirst` action (stable partition finites, ∞ unchanged at bottom); disable second unlimited in composer when one exists (alert/i18n).
</step>

<step id="9" status="complete">
**Test:** `spec/requests/i18n_views_spec.rb` — Spanish locale includes priority legend strings. Tag `[REQ-FIT-UI-001]`.
**Implement:** Complete `es`/`en` strings for priority column, legend, finite-first button, single-unlimited cap error.
</step>

<step id="10" status="complete">
**Test:** Run `bundle exec rspec` (targeted then full) and `python -m pytest nesting_engine/tests -q -m "not slow"`.
**Implement:** Update `docs/core/SPEC.md` W1 (drag + auto ∞-last + max one ∞), `docs/core/DATA_FLOW_MAP.md` (`sort_order` semantics), `docs/core/SCHEMA_REFERENCE.md` (business rule note on `quantity` NULL cap), `docs/ROADMAP.md` mark item done when merged.
</step>

</implementation_plan>
