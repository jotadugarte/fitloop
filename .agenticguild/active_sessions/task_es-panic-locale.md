# Task: Modo Arquitecto en Pánico (`:es_panic`)

**Opened:** 2026-05-19  
**Status:** Spec locked (explore-task complete → start-task)  
**Classification:** Feature (UX / i18n easter egg)  
**Related REQ:** REQ-FIT-UI-005 (locale switcher — extend for third locale)

---

## Problem statement

Add a joke locale **“Modo Arquitecto en Pánico”** (`:es_panic`) with humorous Spanish copy across the main project workflow: home, setup (sheet inventory + nesting params + DXF upload), show (preview, orphans, actions), and nesting progress. User should pick it from the language switcher (label **“📐 PÁNICO”**).

User-provided dictionary uses top-level namespace `fitloop.*` (see scratchpad below).

---

## Codebase reconnaissance (2026-05-19)

| Area | Current state |
|------|----------------|
| Locales | `config/locales/en.yml`, `es.yml` only |
| `available_locales` | `%i[en es]` in `config/application.rb` |
| Switcher | `app/views/shared/_locale_switcher.html.erb` — loops `I18n.available_locales`, button label = `locale.to_s.upcase` |
| Persistence | `LocaleSwitchable` + cookie `fitloop_locale` + `LocalesController#update` |
| Views | **Already i18n’d** — keys like `projects.form.*`, `nesting.*`, `home.index.*`, `project_layers.*` (no hardcoded ES/EN UI strings found in `app/views/projects/`) |
| Progress UX | `nesting.phase.*` keys + `ProgressSnapshot::PHASE_I18N_KEYS`; `project.progress_message` stores **translated** string at write time |
| Architecture doc | `SYSTEM_ARCHITECTURE.md` §1 lists i18n as **`en`, `es` in v1** |
| Tests | `spec/requests/locale_spec.rb`, `spec/requests/i18n_views_spec.rb`, `spec/i18n/nesting_phase_labels_spec.rb` (%i[en es] only) |
| Verifier | `lib/fitloop_home_verifier.rb` expects `config/locales/en.yml` and `es.yml` |

---

## Critical design tension (must decide before build)

User request step 4 asks to replace static copy with `t('fitloop.xxx')`.

**Reality:** Fitloop v1 UI strings already live under Rails’ conventional trees (`projects`, `nesting`, `home`, `project_layers`, `activerecord`, …). Introducing a **parallel** `fitloop.*` tree implies either:

| Option | Scope | Pros | Cons |
|--------|-------|------|------|
| **A — Locale file only (mirror `es.yml`)** | Add `es_panic.yml` with **same keys as `es.yml`**, panic values; tweak switcher labels | Small diff; en/es unchanged; fits existing tests | User’s `fitloop.*` YAML shape not used literally |
| **B — New `fitloop.*` namespace + view refactor** | New keys in **all** locale files + change every `t("projects…")` → `t("fitloop…")` | Matches user’s dictionary structure exactly | Large blast radius; duplicate key maintenance; touches every view/helper/job that calls `I18n.t` with old paths |
| **C — Hybrid alias layer** | `fitloop.*` in YAML + helper `fit_t(key)` mapping to legacy keys | Keeps one “panic dictionary” file | Indirection; easy to drift; non-idiomatic Rails |

**Recommendation (architect): Option A** unless product explicitly wants a permanent `fitloop.*` product namespace. Map user’s dictionary → existing keys in the implementation plan (table below).

---

## User dictionary → suggested existing keys (draft mapping)

| User `fitloop` section | Suggested Rails key(s) |
|------------------------|-------------------------|
| `global.lang_*` | New: `locale.labels.en` / `es` / `es_panic` (switcher only) |
| `home.*` | `home.index.tagline`, `subtitle`, `cta_start` |
| `inventory.*` | `projects.form.sheet_stocks_legend`, `quantity_hint`, `consumption_*`, `add_sheet`, `edit_sheet`, `delete_sheet`, `save_sheets` / `continue`, AR attrs `width_mm` / `height_mm` / `quantity` |
| `nesting_params.*` | `projects.show.nesting_parameters_title`, `projects.form.kerf_mm*`, `margin_mm*`, `apply_nesting_parameters` |
| `dxf.*` | `projects.form.dxf_upload_*`, `projects.show.source_dxf_detail_*`, `project_layers.*`, `project_readiness.no_layers_selected` |
| `preview.*` | `projects.show.preview_zone_title`, `projects.preview.*`, `projects.show.download_nested_dxf` |
| `pieces.*` | `nesting.orphan_*`, `nesting.split.*`, `nesting.derived_piece.title` |
| `actions.*` | `nesting.start`, `renest`, `nest_updated_pieces` |
| `progress.*` | `nesting.progress_heading`, `nesting.cancel`, `nesting.phase.*`, terminal: `nesting.completed` / `partial` / `failed` / `time_limit_notice` |

### Progress copy — percent bands vs phase keys

User YAML uses **percent-band** keys (`status_3`, `status_8`, `status_12`, …). Engine/Rails today use **phase** keys (`nesting.phase.queued`, `preparing`, `extracting`, `fill`, …).

| User key | Approx. match today |
|----------|---------------------|
| `status_3` | `nesting.phase.queued` (enqueue 3%) |
| `status_8` | `nesting.phase.preparing` |
| `status_12` | `nesting.phase.starting` |
| `status_10` | `nesting.phase.extracting` (note: user order ≠ pipeline order) |
| `status_12_55` | `nesting.phase.fill` / optimizing band |
| `status_58` | `nesting.phase.optimizing` |
| `status_72` | `nesting.phase.consolidating` / refining |
| `status_82_90` | `nesting.phase.writing_outputs` |
| `status_100` | `nesting.completed` |
| `status_100_orphans` | `nesting.partial` |
| `status_100_fail` | `nesting.failed` |
| `status_100_timeout` | `nesting.time_limit_notice` |

**YAML issue:** duplicate key `status_12` (two different strings). Resolve when translating to `nesting.phase.*`.

Implementing percent-band labels literally would require **new Ruby** (map `progress_percent` → message), which is out of scope for a copy-only easter egg unless user insists.

---

## Domain model

| Entity | Responsibility | Invariants |
|--------|----------------|------------|
| **Locale** | User-facing language choice (`:en`, `:es`, `:es_panic`) | Must be ∈ `I18n.available_locales`; persisted cookie value is string (`"es_panic"`) |
| **LocaleLabel** (value) | Display string in switcher | Not derived from `locale.to_s.upcase` for `es_panic` |

No new DB tables.

---

## User decisions (locked 2026-05-19)

| # | Decision |
|---|----------|
| 1 | **Option A** — `es_panic.yml` mirrors `es.yml` key tree |
| 2 | **No orphans** — user will supply all missing panic strings (see `task_es-panic-locale_gaps.md`) |
| 3 | **Full app** — flashes, AR errors, nav, workspace, project_layers index, dates, etc. |
| 4 | **Yes** — extend REQ-FIT-UI-005 + `SYSTEM_ARCHITECTURE.md` §1 |
| 5 | **Locale switcher layout (grid 2+1)** — user mockup 2026-05-19; see § Locale switcher UI below |

**Fallback policy:** No runtime fallback to `:es`; file must be complete before merge (232 values).

---

## Locale switcher UI (locked — mockup 2026-05-19)

**Not** a single horizontal row of three chips. Use a **2+1 grid** in `shared/_locale_switcher` + CSS in `application.css`.

```
┌─────────┬─────────┐
│   EN    │   ES    │   ← row 1: two equal columns
├─────────┴─────────┤
│  📐  PÁNICO       │   ← row 2: full width (spans both columns)
└───────────────────┘
```

| Element | Spec |
|---------|------|
| Row 1 | `:en` and `:es` only — `display: grid; grid-template-columns: 1fr 1fr; gap` |
| Row 2 | `:es_panic` only — one button `width: 100%` (class e.g. `locale-switcher__btn--wide`) |
| Labels | `t("locale.labels.en")`, `t("locale.labels.es")`, `t("locale.labels.es_panic")` → `"EN"`, `"ES"`, `"📐 PÁNICO"` |
| Markup | Wrapper `.locale-switcher` (column flex); `.locale-switcher__row` per row; panic row `.locale-switcher__row--panic` |
| Active state | Keep existing `.locale-switcher__btn--active` (navy fill) on all three |
| Placement | Unchanged: `app-main__toolbar` (layout app) and `minimal-layout__top` (layout minimal) |
| A11y | Outer `<nav aria-label="…">`; each row `role="group"` with sensible `aria-label` |

Optional later: CAD-style corner-bracket borders from mockup — **out of scope** unless user asks; use existing Fitloop button tokens for v1.

**Do not** use `locale.to_s.upcase` for `es_panic` (would render `ES_PANIC`).

---

## Copy review (2026-05-19 — user batch 2)

### Structural issues (must fix in final `es_panic.yml`)

1. **`upload:` / `index:` misplaced** — indented under `es_panic` root; Rails expects `project_layers.upload.*` and `project_layers.index.*`.
2. **`fitloop:` block** — Option A: flatten into standard keys (`home.index`, `projects.form`, `nesting.phase`, …); views do not call `t("fitloop.*")`.
3. **Message truncated** — `fitloop.progress.status_96_99` cut mid-string; missing terminal keys (`status_100`, `status_100_orphans`, `status_100_fail`, `status_100_timeout`).
4. **Wrong interpolations:**
   - `projects.show.dxf_file_layers_meta` / `_template`: use `%{selected}` and `%{total}` (not `layers` / `total_layers`).
   - `projects.show.source_dxf_detail_summary`: static title (no `%{filename}` in views).
   - **Missing** `projects.show.source_dxf_detail_meta`: `%{files} planos · %{selected} de %{total} capas` (map from `fitloop.dxf.summary_count`).
5. **`date.formats.short`** — user set `"%d %b %H:%M"`; `es` uses date-only `%-d %b %Y`. Keep date/time split like `es.yml` or history timestamps look wrong.
6. **New switcher keys** — add `locale.labels.en|es|es_panic` (from `fitloop.global.lang_*`).

### Content mapping (`fitloop.*` → Rails keys at implement time)

| fitloop | Rails target |
|---------|----------------|
| `home.*` | `home.index.*` |
| `inventory.*` | `projects.form.*`, `activerecord.attributes.sheet_stock.*`, `projects.show.save_sheets` |
| `nesting_params.*` | `projects.show.nesting_parameters_*`, `projects.form.kerf_mm*`, `margin_mm*` |
| `dxf.*` | `projects.form.dxf_*`, `projects.show.apply_layers`, `project_layers.*`, `project_readiness.no_layers_selected` |
| `preview.*` | `projects.show.preview_zone_title`, `projects.preview.*`, `projects.show.download_nested_dxf` |
| `pieces.*` | `nesting.orphan_*`, `nesting.split.*` |
| `actions.*` | `projects.show.actions_title`, `nesting.start`, `renest`, `nest_updated_pieces` |
| `progress.*` | `nesting.progress_heading`, `nesting.cancel`, `nesting.phase.*` (map bands → phases), terminals |
| `global.btn_continue` | `projects.form.continue` |

### Still no panic string after merge (provide or confirm reuse)

- `locale.labels.*` (3) — values in `fitloop.global`
- `projects.show.source_dxf_detail_meta` — derive from `fitloop.dxf.summary_count` with fixed vars
- `nesting.phase.*` (9) — map from `fitloop.progress.status_*` table in plan
- `nesting.orphan_reason.oversized_for_sheet` / `orphan_hint.oversized_for_sheet` — use `fitloop.pieces.error_too_large` / `tip_try_larger`?
- `nesting.split.badge.pending|system_split|manual` — map from `fitloop.pieces.status_*`
- `project_layers.layer_name`, `section_note`, `primary_layer.short`, `auxiliary_layers.short` — partial in `fitloop.dxf`
- `nav.projects` — provided; unused in views today but include for parity

## Copy batch 3 (locked 2026-05-19)

User confirmed: flattened YAML (no `fitloop:`), phases in `nesting.phase.*`, terminals complete, dates split, meta DXF fixed.

Pre-implement mechanical fixes: see `es_panic_preimplement_fixes.md` (~20 keys to add/repath; implementer applies when writing `config/locales/es_panic.yml`).

---

## Risks

| Risk | Mitigation |
|------|------------|
| Large refactor if Option B | Prefer Option A |
| `progress_message` stored translated at job time | Already true for en/es; es_panic works if locale set before nesting |
| Tests hardcode EN/ES | Extend locale specs; add one request example with panic tagline |
| `fitloop_home_verifier` | Add `es_panic.yml` to locale file check |
| Duplicate `status_12` in user YAML | Use phase keys; one string per phase |

---

## User-provided YAML (reference)

Stored verbatim for implementer — **do not treat key paths as final** until namespace decision locked:

```yaml
# Top-level locale key: es_panic
# Namespace: fitloop → global, home, inventory, nesting_params, dxf, preview, pieces, actions, progress
# (Full content supplied by user in chat 2026-05-19 — see explore-task thread)
```

---

## Scratchpad

- `html lang="<%= I18n.locale %>"` → will emit `es_panic` (valid BCP47-ish; acceptable).
- Switcher: grid 2+1 (EN|ES / 📐 PÁNICO); labels via `locale.labels.*`.
- Roadmap item #18 marks EN/ES done; this is a small additive UX gag, not nesting engine work.

---

<implementation_plan>

<step id="1" status="complete">
**Test:** Extend `spec/i18n/locale_key_parity_spec.rb` (new) or `spec/i18n/nesting_phase_labels_spec.rb` — for `:es_panic`, every leaf key in `es.yml` resolves without `translation missing` (compare flattened key sets). Tag `[REQ-FIT-UI-005]`.
**Implement:** `es_panic.yml` (232 keys, batch 3 + gap fillers), `available_locales` includes `:es_panic`.
</step>

<step id="2" status="complete">
**Test:** Extend `spec/requests/locale_spec.rb` — `PATCH /locale` with `es_panic` persists cookie; `GET /` with cookie shows panic tagline; layout includes `.locale-switcher__row--panic` with `📐 PÁNICO` (not `ES_PANIC`). Tag `[REQ-FIT-UI-005]`.
**Implement:** `_locale_switcher` grid 2+1, `locale.labels.*` in en/es/es_panic, CSS row/wide.
</step>

<step id="3" status="pending">
**Test:** Extend `spec/i18n/nesting_phase_labels_spec.rb` — include `es_panic` context for all `nesting.phase.*` keys. Tag `[REQ-FIT-UI-005]`, `[REQ-FIT-JOB-001]`.
**Implement:** (none yet)
</step>

<step id="4" status="pending">
**Implement:** Add `config/locales/es_panic.yml` from user batch 3; apply fixes in `es_panic_preimplement_fixes.md` (reindent `project_layers`, `split.badge`, `orphan_preview.download_dxf`, missing ~20 keys, `%{piece_number}`).
</step>

<step id="5" status="complete">
**Implement:** `config/application.rb` — `available_locales` includes `:es_panic`. `config/locales/en.yml` and `es.yml` — add `locale.labels.en` / `es` for switcher parity.
</step>

<step id="6" status="complete">
**Test:** Request or view spec — `.locale-switcher` has two rows; row 1 contains EN+ES; row 2 contains panic button when `:es_panic` enabled. Tag `[REQ-FIT-UI-005]`.
**Implement:** `shared/_locale_switcher.html.erb` — grid 2+1 per § Locale switcher UI; `application.css` — `.locale-switcher__row`, `__btn--wide`, column layout; labels `t("locale.labels.#{locale}", default: locale.to_s.upcase)`.
**Note:** Covered by step 2 locale_spec (row--panic, EN/ES/PÁNICO).
</step>

<step id="7" status="pending">
**Implement:** `lib/fitloop_home_verifier.rb` — expect `config/locales/es_panic.yml`.
</step>

<step id="8" status="pending">
**Implement:** `docs/core/SPEC.md` REQ-FIT-UI-005 — document optional joke locale `:es_panic`. `docs/core/SYSTEM_ARCHITECTURE.md` §1 i18n — `en`, `es`, `es_panic` (easter egg).
</step>

<step id="9" status="pending">
**Test:** Run `bundle exec rspec spec/requests/locale_spec.rb spec/i18n/ spec/requests/i18n_views_spec.rb` (adjust only if brittle on panic strings).
**Implement:** Fix regressions; optional `docs/ROADMAP.md` line for es_panic locale.
</step>

</implementation_plan>
