# Task: Nesting / workshop domain types (CbC refactor)

**Roadmap:** Pending #0 (Pre-live)  
**REQ-IDs:** REQ-FIT-NEST-002, REQ-FIT-DOM-001, REQ-FIT-CLI-001, REQ-FIT-SPLIT-001 (piece keys)  
**Classification:** Refactor (CbC / Design by Contract)  
**Depends on:** None (billing CbC complete; separate domain)  
**Blocks:** None (admin does not depend on this item)

**Started:** 2026-05-30  
**Skill:** explore-task → handoff to start-task  
**User approval:** PROCEED (normative defaults from project rules)

---

## Goal

Replace raw `Float` / `String` in the **nesting and workshop service layer** with validated value objects so invalid kerf/margin semantics, negative spacing, and malformed piece keys are **unrepresentable** at service boundaries. Preserve `config.json` keys, DB columns, HTTP routes, and nesting engine algorithms. Mirror the billing CbC pattern (`app/models/billing/`) without mixing domains.

---

## Architect decisions (2026-05-30 — PROCEED / project rules)

### D-NEST-CBC-1 — Scope (defense-in-depth, boundary-first)

| Layer | Role |
|-------|------|
| **DB / AR** (`Project`, `SheetStock`, `OrphanResolution`) | Keep `float` columns and string `piece_key` unchanged. AR validations remain safety net. |
| **Domain VOs** (`app/models/nesting/*.rb`) | Pure Ruby: parse/validate once; no ActiveRecord. |
| **Services** (`Nesting::*`, `SheetStocks::*`, split/orphans) | Must accept/return VOs for domain concepts. |
| **Controllers** (workshop, nesting params, nest start) | Parse params → VOs immediately; assign AR with `.to_f` / `.to_s` only at persistence edge. |
| **Views / presenters** | Display `.value` or formatters; `Workshop::UxMode` unchanged (presentation only). |
| **Python CLI** | Phase F: parse/validate numeric fields from `config.json` (fail fast); **no** nesting math in Rails; **no** duplicate consumption-order logic in Ruby. |

**Out of scope:** Billing types; DB migrations; changing `config.json` schema; reordering `nest_multi_bin` phases; golden x/y test coordinates.

### D-NEST-CBC-2 — Kerf vs margin (non-negotiable)

**Decision:** **Separate types** `Nesting::KerfMm` and `Nesting::MarginMm` (not a shared `SpacingMm`).

- `KerfMm` → piece-to-piece clearance → `nest_types.apply_kerf` via config `kerf_mm`.
- `MarginMm` → sheet-edge inset only → `nest_placement` via config `margin_mm`.

**Rationale:** `SYSTEM_ARCHITECTURE` §7 kill list; `.cursorrules` #2.

### D-NEST-CBC-3 — Namespace and PieceKey

**Decision:** New VOs live under **`app/models/nesting/`** (Zeitwerk `Nesting::`).

**PieceKey:** Relocate from `app/services/nesting/piece_key.rb` → `app/models/nesting/piece_key.rb` in Phase A (behavior unchanged); `PieceKeyBuilder` stays in services but returns `Nesting::PieceKey`.

### D-NEST-CBC-4 — Project parameters bundle

**Decision:** Introduce **`Nesting::JobParameters`** value object aggregating kerf, margin, curve_tolerance, sheet_gap, time_limit — built from `Project` via `.from_project(project)` and consumed by `ConfigBuilder` / `CliRunner` as SSOT for CLI payload numerics.

**Rationale:** Single adapter Project → config.json; avoids five separate floats threading through services.

### D-NEST-CBC-5 — Sheet stock dimensions

**Decision:** **`Nesting::SheetStockSpec`** (Rails VO, distinct from Python `nest_types.SheetStockSpec`) wrapping width_mm, height_mm, quantity, sort_order with invariants (positive dimensions, quantity nil or positive int, sort_order ≥ 0). Used when building `sheet_stocks` array in `ConfigBuilder` and optionally in `SheetStocks::NormalizeConsumptionOrder` outputs.

**Note:** Python dataclass name unchanged; Rails VO may be `Nesting::SheetStockRow` if naming collision is confusing — prefer **`Nesting::SheetStockRow`** in Ruby, map to JSON `sheet_stocks` hashes.

### D-NEST-CBC-6 — Migration strategy (phased slices)

1. **Phase A** — Core VOs + unit specs (+ relocate `PieceKey`).
2. **Phase B** — `JobParameters` + `ConfigBuilder` (CLI SSOT).
3. **Phase C** — `CliRunner`, `JobRunner`, `StartsNesting`, progress/cancel paths.
4. **Phase D** — Split/orphans (`PieceKey` on `OrphanResolution`, derived pieces, `SplitPlannerRunner`).
5. **Phase E** — Workshop controllers (`nesting_parameters`, workspace sheet flows if touching dimensions).
6. **Phase F** — Python `nesting_engine` config parsers (kerf/margin ≥ 0 asserts; optional shared module `nesting_config.py`).

Each phase: green RSpec nesting/workshop + targeted pytest before next slice.

### D-NEST-CBC-7 — Testing

1. **VO unit specs** — `spec/models/nesting/*_spec.rb` with `[REQ-FIT-NEST-002]` / `[REQ-FIT-DOM-001]`.
2. **Existing service/request specs** — construct VOs; assert behavior unchanged.
3. **Python** — extend config validation tests if Phase F adds parsers; invariant tests unchanged (no golden coordinates).

### D-NEST-CBC-8 — Documentation

Add short paragraph under **REQ-FIT-DOM-001** and **REQ-FIT-NEST-002** in `docs/core/SPEC.md` pointing to `app/models/nesting/` typed layer (no REQ-ID change). Optional one-line ADR-0001 addendum if needed; no behavioral ADR unless JSON contract changes.

---

## Domain Model

### Nesting::KerfMm

- **Responsibility:** Minimum piece-to-piece clearance (mm).
- **Wraps:** `BigDecimal` or `Float` (canonical non-negative mm).
- **Invariants:** `>= 0`; must not be conflated with margin.
- **Factories:** `.parse(raw)`, `.from_project(project)` → `.to_f` for JSON/AR only at boundary.

### Nesting::MarginMm

- **Responsibility:** Sheet-edge inset (mm) only.
- **Wraps:** Non-negative mm scalar.
- **Invariants:** `>= 0`; distinct type from `KerfMm` (no implicit conversion).
- **Factories:** `.parse(raw)`, `.from_project(project)`.

### Nesting::CurveToleranceMm

- **Responsibility:** DXF curve tessellation tolerance for extract.
- **Wraps:** Positive mm scalar.
- **Invariants:** `> 0` (matches `Project` validation).

### Nesting::SheetGapMm

- **Responsibility:** Offset between sheet rectangles in combined nested DXF output (orthogonal to kerf/margin).
- **Wraps:** Non-negative mm.
- **Invariants:** `>= 0`.

### Nesting::NestingTimeLimitSec

- **Responsibility:** Job/engine deadline seconds.
- **Wraps:** Positive integer seconds.
- **Invariants:** `> 0`; upper bound optional (document if capped, e.g. 600 default per SPEC).

### Nesting::JobParameters

- **Responsibility:** Bundle of all project nesting numeric params for one CLI job.
- **Wraps:** `KerfMm`, `MarginMm`, `CurveToleranceMm`, `SheetGapMm`, `NestingTimeLimitSec`.
- **Invariants:** All components valid; `#to_config_hash` emits exact legacy keys for `config.json`.
- **Factories:** `.from_project(project)`.

### Nesting::SheetStockRow

- **Responsibility:** One sheet stock row for CLI payload.
- **Wraps:** width_mm, height_mm, quantity (Integer or nil), sort_order.
- **Invariants:** width/height > 0; quantity nil or ≥ 1; at most one nil quantity per project enforced at project level (AR), not inside single row.
- **Factories:** `.from_sheet_stock(stock)`, `.to_config_hash`.

### Nesting::PieceKey (existing — relocate + consolidate)

- **Responsibility:** Stable nestable piece identity across runs (`REQ-FIT-SPLIT-001`).
- **Wraps:** String matching `FORMAT` regex.
- **Invariants:** Non-blank; format `\A\d+:(?:piece-\d+|fp-[a-f0-9]{16})\z`.
- **Factories:** via `Nesting::PieceKeyBuilder` (unchanged logic).

### Entities unchanged (persistence)

- **Project**, **SheetStock**, **NestingRun**, **OrphanResolution**, **DerivedPiece** — AR; optional `#kerf_mm_vo` helpers read-only only.

### Workshop::UxMode (unchanged)

- Presenter only; may read `project.kerf_mm` for display until views use VO formatters.

---

## Current primitives audit (hot spots)

| Location | Raw today | Target |
|----------|-----------|--------|
| `Nesting::ConfigBuilder#build` | `@project.kerf_mm`, etc. | `JobParameters` + `SheetStockRow[]` |
| `Project` validations | floats | unchanged; VO mirrors rules |
| `projects_controller` nesting params | `params[:kerf_mm]` | parse → `KerfMm`/`MarginMm` → assign AR |
| `Nesting::PieceKeyBuilder` | returns PieceKey | unchanged API |
| `OrphanResolution#piece_key` | String | parse to `PieceKey` in services |
| `DerivedPiece#parent_piece_key` | String | `PieceKey` at boundary |
| `nest_bin` / CLI | `float` from JSON | Phase F validate in Python |
| `SheetStocks::*` | AR floats | optional `SheetStockRow` when emitting to config |

---

## Risks

| Risk | Mitigation |
|------|------------|
| Kerf/margin confusion in code | Separate types; no shared arithmetic |
| Large diff on ConfigBuilder | Phase B isolated; snapshot specs |
| PieceKey path move breaks autoload | Single commit in Phase A; grep Zeitwerk |
| Python/Ruby drift on validation | Phase F mirrors AR rules only for parsed config |
| Scope creep into engine | Explicit kill list in plan constraints |

---

## Open questions

_(closed 2026-05-30 — PROCEED with project-rule defaults)_

---

## Scratchpad

### Green baseline (2026-05-30 — step 0.1 complete)

**RSpec** (111 examples, 0 failures):

```bash
bundle exec rspec \
  spec/services/nesting \
  spec/services/sheet_stocks \
  spec/models/project_spec.rb spec/models/nesting_run_spec.rb \
  spec/requests/project_nesting_parameters_spec.rb \
  spec/requests/nesting_start_workspace_spec.rb \
  spec/requests/nesting_renest_spec.rb \
  spec/requests/nesting_renest_after_sheet_edit_spec.rb \
  spec/requests/nesting_nest_updated_pieces_spec.rb \
  spec/requests/nesting_enqueue_eta_spec.rb \
  spec/requests/project_nesting_sync_spec.rb \
  spec/jobs/nesting_job_spec.rb spec/jobs/nesting_renest_spec.rb \
  spec/jobs/nesting_split_plan_job_spec.rb
```

Note: `spec/models/nesting` omitted — directory does not exist yet (Phase A will create it).

**Pytest** (134 passed):

```bash
.venv/bin/pytest nesting_engine/tests -q --ignore=nesting_engine/tests/fixtures
```

---

<implementation_plan>
  <meta>
    <task_slug>nesting-workshop-domain-types-cbc</task_slug>
    <branch_name_suggestion>refactor/nesting-workshop-domain-types-cbc</branch_name_suggestion>
    <roadmap_item>Nesting / workshop domain types (CbC refactor) — Pending #0</roadmap_item>
    <classification>Refactor</classification>
    <req_ids>
      <req>REQ-FIT-NEST-002</req>
      <req>REQ-FIT-DOM-001</req>
      <req>REQ-FIT-CLI-001</req>
      <req>REQ-FIT-SPLIT-001</req>
    </req_ids>
    <constraints>
      <constraint>No nesting math in Ruby (SYSTEM_ARCHITECTURE §3 kill list).</constraint>
      <constraint>Domain VOs in `app/models/nesting/`; services in `app/services/nesting/` and `app/services/sheet_stocks/`; no fat controllers.</constraint>
      <constraint>Separate `Nesting::KerfMm` and `Nesting::MarginMm` — never conflate (§7, .cursorrules #2).</constraint>
      <constraint>No DB migrations; `config.json` key names and types unchanged unless ADR.</constraint>
      <constraint>`nest_multi_bin` phase order unchanged (fill → intra repack → consolidate → intra repack → inter-sheet).</constraint>
      <constraint>Sheet consumption: `NormalizeConsumptionOrder` + `sheet_stocks_config.stocks_in_consumption_order` remain authoritative (.cursorrules #12–14).</constraint>
      <constraint>Do not mix `Billing::*` types into nesting/workshop.</constraint>
      <constraint>CbC: VO preconditions; functions ≤60 lines; cyclomatic complexity ≤10.</constraint>
      <constraint>New RSpec files: `RSpec.describe ClassName, "[REQ-FIT-NEST-002]"` (or DOM/SPLIT as appropriate).</constraint>
      <constraint>Nesting tests assert invariants, not golden coordinates (.cursorrules #7).</constraint>
    </constraints>
  </meta>

  <phase id="P0" name="Green baseline &amp; anchors">
    <step id="0.1" status="complete">Run existing tests to establish a green baseline: full `spec/services/nesting`, `spec/services/sheet_stocks`, nesting-related request/job specs, and `nesting_engine` pytest suite (record command + pass count in scratchpad).</step>
    <step id="0.2">Add SPEC paragraphs under REQ-FIT-DOM-001 and REQ-FIT-NEST-002 documenting `app/models/nesting/` typed layer (no REQ-ID change).</step>
    <step id="0.3">Optional: one-line ADR-0001 addendum referencing Rails nesting VOs at service boundaries (behavior unchanged).</step>
  </phase>

  <phase id="P1" name="Phase A — Core value objects">
    <step id="1.1">Run existing tests to establish green baseline for Phase A (subset: `spec/services/nesting/piece_key*` if present, `piece_key_builder_spec.rb`).</step>
    <step id="1.2">Write failing unit specs for `Nesting::KerfMm` and `Nesting::MarginMm` — non-negative, reject negative/nil; no cross-type equality.</step>
    <step id="1.3">Implement `KerfMm` and `MarginMm` in `app/models/nesting/`.</step>
    <step id="1.4">Write failing unit specs for `CurveToleranceMm` (&gt; 0), `SheetGapMm` (≥ 0), `NestingTimeLimitSec` (&gt; 0).</step>
    <step id="1.5">Implement those three types.</step>
    <step id="1.6">Relocate `Nesting::PieceKey` to `app/models/nesting/piece_key.rb`; update autoload references; keep `piece_key_builder_spec.rb` green.</step>
    <step id="1.7">Write failing unit specs for `Nesting::SheetStockRow` — positive dimensions, quantity nil or ≥ 1, `#to_config_hash` keys.</step>
    <step id="1.8">Implement `SheetStockRow`.</step>
    <step id="1.9">Run Phase A unit suite — all green.</step>
  </phase>

  <phase id="P2" name="Phase B — JobParameters &amp; ConfigBuilder (CLI SSOT)">
    <step id="2.1">Write failing specs: `Nesting::JobParameters.from_project` mirrors project defaults; `#to_config_hash` matches legacy `ConfigBuilder` output for numerics.</step>
    <step id="2.2">Implement `Nesting::JobParameters`.</step>
    <step id="2.3">Refactor `Nesting::ConfigBuilder` to use `JobParameters` and `SheetStockRow.from_sheet_stock`; extend `config_builder_spec.rb` / `config_builder_split_spec.rb` — JSON unchanged.</step>
    <step id="2.4">Run ConfigBuilder + CLI-related service specs — green.</step>
  </phase>

  <phase id="P3" name="Phase C — Job orchestration">
    <step id="3.1">Refactor `Nesting::CliRunner`, `Nesting::JobRunner`, `StartsNesting` concern to accept/build `JobParameters` at boundary (internal AR read via `.from_project` only).</step>
    <step id="3.2">Run `cli_runner_spec.rb`, `job_runner_spec.rb`, `nesting_job*_spec.rb`, `nesting_start_workspace_spec.rb` — green.</step>
  </phase>

  <phase id="P4" name="Phase D — Split / orphans / piece keys">
    <step id="4.1">Refactor orphan/split services to parse `piece_key` strings into `Nesting::PieceKey` at entry (`ConfirmManualOrphanResolution`, split accept, `mother_piece_still_present`, etc.).</step>
    <step id="4.2">Run `piece_key_builder_spec.rb`, split/orphan service and request specs — green.</step>
  </phase>

  <phase id="P5" name="Phase E — Workshop controllers">
    <step id="5.1">Refactor `ProjectsController` (or workshop nesting parameters action) to parse `kerf_mm`/`margin_mm` params → VOs before assign; invalid → 422 / model errors unchanged UX.</step>
    <step id="5.2">Run `project_nesting_parameters_spec.rb`, workshop-related request specs — green.</step>
    <step id="5.3">Grep `app/services/nesting` and nesting controllers for raw `kerf_mm`/`margin_mm` on `@project` past boundaries — zero hits except AR assign adapters.</step>
  </phase>

  <phase id="P6" name="Phase F — Python config validation (optional but recommended)">
    <step id="6.1">Add `parse_job_parameters_from_config` (or extend existing CLI entry) with asserts: `kerf_mm`/`margin_mm` ≥ 0, `curve_tolerance_mm` &gt; 0; pytest for invalid config rejection.</step>
    <step id="6.2">Run nesting_engine pytest — green; no change to placement invariants.</step>
  </phase>

  <phase id="P7" name="Regression &amp; roadmap">
    <step id="7.1">Run full nesting/workshop RSpec list from scratchpad + `spec/system/golden_nesting_e2e_spec.rb` if CI time allows (or mark slow separately).</step>
    <step id="7.2">Update `docs/ROADMAP.md` Pending #0 → done when merged.</step>
    <step id="7.3">Archive session via `finish-branch` skill.</step>
  </phase>
</implementation_plan>
