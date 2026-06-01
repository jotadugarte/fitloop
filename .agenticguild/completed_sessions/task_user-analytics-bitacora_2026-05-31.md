# Task: User analytics & admin bitácora (core + UI)

**Created:** 2026-05-31 (resumed from archived `completed_sessions/task_user-analytics_2026-05-21.md`)  
**Status:** Spec locked — handoff to `start-task` (2026-05-31)  
**Roadmap:** Pending #3 — Depends on **Admin foundation** ✅ (2026-05-31)  
**Scope v1 (this epic):** Tarjeta admin **«Estadísticas y Uso»** (Analytics) + `/admin/usuarios` bitácora — `user_events`, `Analytics::TrackEvent`, workshop + billing instrumentation, `/admin/analytics`, CSV export, Chart.js, gobernanza anti-drift (contrato + catálogo + spec). **`/admin/ventas` fuera de alcance** (ya shipped); el contrato **documenta** ventas para drift, sin reimplementar ventas. **Fuera de v1 → ROADMAP Pending #6:** archivo frío, alertas push, FU-LEGAL-003 completo, BI externo.

---

## User request (2026-05-31)

1. Run **explore-task** for ROADMAP item **User analytics & admin bitácora (core + UI)**.
2. Add governance: if Fitloop changes in the future affect **user analytics** or **sales reporting** (`/admin/ventas`, Hacienda, exports), we need a **detectable rule** so reports and dashboards are updated — not silent drift.

---

## Baseline (codebase today)

| Area | State |
|------|--------|
| `users.admin` + `FITLOOP_ADMIN_EMAILS` + `Admin::BaseController` 404 gate | ✅ Shipped |
| `/admin/ventas` + XLSX + `Admin::ReportingScope` + Hacienda summary | ✅ Shipped |
| `/admin` dashboard | Analytics card **“Próximamente”** (no routes) |
| `user_events`, `Analytics::*` | ❌ Not implemented |
| `REQ-FIT-ANALYTICS-001` in `docs/core/SPEC.md` | ❌ Not added (planned in archive) |
| ADR for analytics | ❌ Use **ADR-0008** (0006 = ONVO billing) |

---

## Agreed decisions (carried from 2026-05-20 archive)

Decisions **A1–A40** remain locked unless noted below. See `completed_sessions/task_user-analytics_2026-05-21.md` for full table.

**Adjustments for 2026-05-31:**

| # | Update |
|---|--------|
| A34 | **`FITLOOP_ADMIN_EMAILS`** (comma-separated) is SSOT — matches shipped `promote_admins.rb`; archive text `FITLOOP_ADMIN_EMAIL` singular is obsolete. |
| A33 | **Archive cold DB** deferred to backlog item *Analytics archive (cold storage)* — not blocking v1 analytics UI. |
| ADR | Analytics ADR → **`docs/core/ADRs/0008-admin-analytics-and-user-events.md`** (not 0006). |

---

## New decision (2026-05-31) — reporting & analytics drift governance

| # | Decision |
|---|----------|
| **A41** | **Reporting contract + drift detection:** Maintain a single documented inventory of (a) **admin analytics surfaces** (KPIs, funnel stages, filters, CSV columns, `config/analytics.yml` thresholds) and (b) **admin ventas surfaces** (filters, XLSX columns, Hacienda summary rows, `Admin::ReportingScope` rules, `Payment` fields used). Any product change that touches a **source of truth** for those surfaces must update the contract and the implementation in the **same PR** (or an explicitly linked follow-up PR before merge). |
| **A41a** | **Triggers (non-exhaustive):** new/changed `Payment` / `DownloadGrant` / cart / checkout / ONVO status; new workshop lifecycle (routes, nest terminal status, split outcomes); new `event_type` candidates; new billing.yml price keys; new `product_description` / `purpose` values; new locale or currency mode; changes to `superseded_at`, `cabys_code`, IVA snapshot fields, or geo defaults. |
| **A41b** | **Detection mechanism (v1 proposal):** `docs/core/ANALYTICS_AND_REPORTING_CONTRACT.md` (human SSOT) + **automated doc/architecture spec** `spec/doc/analytics_reporting_contract_spec.rb` that asserts: (1) listed `event_type` strings exist in a Ruby constant `Analytics::EventCatalog` (or YAML manifest); (2) ventas XLSX header keys match `Admin::ExportPaymentsXlsx::COLUMNS` (or documented constant); (3) funnel stage list matches `Analytics::FunnelStages::ORDERED`. Failing spec = reminder to update dashboards/ventas. Optional: `.cursorrules` project rule #67 mirroring A41 for AI agents. |
| **A41c** | **Process:** `audit-compliance` / `process-feedback` / PR template checklist item: “¿Tocaste billing, taller, o pagos? → actualiza contrato + analytics/ventas + specs doc.” |
| **A41d** | **Not in scope:** auto-generating dashboards from schema introspection; Metabase/external BI v1. |

### A41 — locked stack (2026-05-31, user: “que nunca se nos pase nada”)

| Capa | Qué | Por qué |
|------|-----|--------|
| **1. Contrato humano** | `docs/core/ANALYTICS_AND_REPORTING_CONTRACT.md` — una sola página: sección **Analytics** (eventos, embudo, KPIs, CSV, claves `analytics.yml`) + sección **Ventas** (filtros, XLSX, Hacienda, `ReportingScope`, campos `Payment`) + tabla **“si cambias X → actualiza Y”** | Un solo lugar al abrir un PR de billing o taller |
| **2. Catálogo machine-readable** | `config/analytics_event_catalog.yml` (tipos, `priority`, propiedades requeridas) cargado por `Analytics::EventCatalog` | Editable sin redeploy de lógica; el spec lee el YAML |
| **3. Constantes Ruby** | `Analytics::FunnelStages::ORDERED`, `Admin::ExportPaymentsXlsx::COLUMN_KEYS` (o similar ya existente) | El spec compara YAML/contrato ↔ código |
| **4. Test automático** | Extender `test/spec/spec_doc_test.rb` / `lib/spec_doc_verifier.rb` — falla si catálogo, embudo, columnas XLSX o keys de `analytics.yml` no coinciden con el contrato | CI obligatorio; no confiar en memoria |
| **5. Regla agente** | `.cursorrules` (~#67): cambios en billing/taller/pagos/eventos → actualizar contrato + catálogo + pantallas admin afectadas | Para humanos y AI en el mismo repo |
| **6. PR checklist** | `.github/pull_request_template.md` (o equivalente): checkbox “Reporting contract actualizado” | Última línea de defensa antes de merge |

**No usar solo documentación:** sin capa 4 el drift vuelve en 3 meses.

---

## Domain Model (CbC)

### UserEvent
- **Responsibility:** Append-only fact log for admin consultation only; not billing SSOT.
- **Invariants:** no blob columns; `occurred_at` UTC; `idempotency_key` unique when present; critical events exempt from rate limit (A32).
- **Value objects:** `EventType`, `AnonymousSessionKey`, `CountryCode`, `EventProperties`, `IdempotencyKey`, `EventPriority`.

### Analytics::TrackEvent
- **Responsibility:** Single ingestion entry; sync critical / async low via `TrackEventJob`.
- **Invariants:** duplicate idempotency → no-op; billing amounts never authoritative in `properties`.

### Analytics::EventCatalog (proposed for A41b)
- **Responsibility:** Canonical list of `event_type` strings + priority + required property keys.
- **Invariants:** doc spec and instrumentation must stay in sync.

### Analytics::FunnelStages
- **Responsibility:** Ordered funnel for dashboard + semáforo.
- **Invariants:** `workspace_started` → `first_dxf_uploaded` → `nest_completed` → `paywall_viewed` → `payment_succeeded` → `download_completed` (A37).

### Admin ventas (existing — contract side)
- **SSOT tables:** `Payment` via `Admin::ReportingScope`; labels `Admin::PaymentDisplayLabels`; net collected `Admin::HaciendaSummaryRows`.
- **Invariants:** superseded payments excluded from operational totals; analytics monetization KPIs must **JOIN** same scope rules (A19, project rule 59).

---

## Risks

| Risk | Mitigation |
|------|------------|
| Silent drift after billing/workshop changes | **A41** contract + doc spec + PR checklist |
| ADR/plan stale vs shipped admin | Rebase plan: skip steps 16–17 admin migration; start at `user_events` + instrumentation |
| jsonb volume | Indexes; archive backlog |
| ADR-0006 name collision | Renumber to ADR-0008 |

---

## Decisions log

- **2026-05-31 — RESUME:** Explore-task restarted; admin foundation + ventas prerequisite satisfied.
- **2026-05-31 — A41:** Reporting/analytics drift governance — **approved** 6-layer stack (contrato único + YAML catálogo + spec_doc_verifier + cursorrules + PR checkbox).
- **2026-05-31 — SCOPE:** Epic = tarjeta Analytics deshabilitada + `/admin/usuarios`; ventas no se rehace; follow-ups en ROADMAP #6.
- **2026-05-31 — SPEC LOCKED:** Implementation plan below; archive DB / push alerts → ROADMAP #6 only.

---

<task_session>
  <metadata>
    <task_name>user-analytics-bitacora</task_name>
    <type>Feature</type>
    <req_id>REQ-FIT-ANALYTICS-001</req_id>
    <roadmap_item>Pending #3 — Admin Analytics (tarjeta «Estadísticas y Uso»)</roadmap_item>
    <out_of_scope>/admin/ventas reimplementation; analytics_archive job (ROADMAP #6)</out_of_scope>
  </metadata>

  <implementation_plan>
    <!-- P0 — Reporting governance (A41, user-approved) -->
    <step id="1" status="complete">Write failing extension to `lib/spec_doc_verifier.rb` + `test/spec/spec_doc_test.rb` [REQ-FIT-ANALYTICS-001]: `docs/core/ANALYTICS_AND_REPORTING_CONTRACT.md` exists; `config/analytics_event_catalog.yml` event types match `Analytics::EventCatalog`; `Analytics::FunnelStages::ORDERED` matches contract; `Admin::ExportPaymentsXlsx::DETAIL_HEADERS` / `SUMMARY_HEADERS` listed in contract ventas section; `config/analytics.yml` threshold keys listed in contract.</step>
    <step id="2" status="complete">Add `docs/core/ANALYTICS_AND_REPORTING_CONTRACT.md` (Analytics + Ventas sections + “si cambias X → actualiza Y” table); seed `config/analytics_event_catalog.yml` and `config/analytics.yml` (Spanish comments, seed thresholds from archive); implement `Analytics::EventCatalog`, `Analytics::FunnelStages`; green spec_doc verifier.</step>
    <step id="3" status="complete">Add `docs/core/ADRs/0008-admin-analytics-and-user-events.md` (user_events, TrackEvent, not billing SSOT, Chart.js importmap, 404 admin gate, GeoLite2+CF, 6-layer A41). Update `docs/core/SPEC.md` (REQ-FIT-ANALYTICS-001 detail), `DATA_FLOW_MAP.md`, `SCHEMA_REFERENCE.md`.</step>
    <step id="4" status="complete">Add `.cursorrules` project rule (reporting drift); PR template checkbox “Reporting contract / catalog updated”; reference in contract doc.</step>

    <!-- P1 — Event pipeline -->
    <step id="5" status="complete">Write failing model spec `UserEvent` [REQ-FIT-ANALYTICS-001]: event_type, priority, properties jsonb, nullable user_id, anonymous_session_key, tab_id, project_id, nesting_run_id, ip, user_agent, country_code, locale, unique idempotency_key, occurred_at; no blob columns.</step>
    <step id="6" status="complete">Migration `user_events` + indexes; register catalog entries for pipeline event types in YAML.</step>
    <step id="7" status="complete">Write failing `Analytics::Thresholds` spec: YAML load, mtime hot-reload, breach for funnel %, payment failure %, nest p95.</step>
    <step id="8" status="complete">Implement `Analytics::Thresholds`; write failing `Analytics::TrackEvent` spec (idempotency no-op, rate limit 300/h low only, critical sync insert, low enqueues job).</step>
    <step id="9" status="complete">Implement `Analytics::TrackEvent`, `TrackEventJob`; write failing `Analytics::ResolveCountry` spec (GeoLite2 + CF-IPCountry fallback).</step>
    <step id="10" status="complete">Implement `Analytics::ResolveCountry`; document MMDB in `docs/DEPLOY.md` if not already covered for analytics.</step>
    <step id="11" status="complete">Write failing `Analytics::MergeAnonymousSession` spec; wire login/register to reassign `anonymous_session_key` rows to `user_id`.</step>

    <!-- P2 — Workshop instrumentation -->
    <step id="12" status="complete">Write failing specs: `workspace_started`, `first_dxf_uploaded` (filename, bytes, layer metadata, no blob), `project_discarded` snapshot.</step>
    <step id="13" status="complete">Instrument workspace/DXF upload/sheet-layer changes (low_priority); project_discarded critical snapshot.</step>
    <step id="14" status="complete">Write failing specs: nest terminal events with duration_ms, counts, orphans_by_reason; separate event per `NestingRun`.</step>
    <step id="15" status="complete">Instrument `NestingJob` terminal paths + split terminals with `nesting_run_id` correlation.</step>

    <!-- P3 — Admin routes (foundation already shipped) -->
    <step id="16" status="complete">Write failing request spec: non-admin GET `/admin/analytics` and `/admin/usuarios` → 404; admin → 200 skeleton.</step>
    <step id="17" status="complete">Add routes `admin/analytics`, `admin/usuarios`, `admin/usuarios/:id`; `Admin::AnalyticsController`, `Admin::UsersController`; enable dashboard card link (remove “Próximamente” disabled state).</step>

    <!-- P4 — Dashboard UI -->
    <step id="18" status="complete">Pin Chart.js v4 importmap + `admin_chart_controller` + analytics CSS (blueprint + coral `metric--alert`).</step>
    <step id="19" status="complete">Write failing request spec `Admin::AnalyticsController`: KPI cards, funnel counts from `user_events`, semáforo when paywall→`payment_succeeded` &lt; `funnel_conversion_min_percent`.</step>
    <step id="20" status="complete">Implement `/admin/analytics` aggregates, filters (date, locale, payment_method, currency), funnel Chart.js bars, daily/weekly toggle.</step>
    <step id="21" status="complete">Write failing spec: monetization KPIs JOIN `Admin::ReportingScope` / `Payment` (not event JSON amounts): paid downloads single vs plan, plans by tier, 1m quota exhausted.</step>
    <step id="22" status="complete">Implement billing KPI widgets + optional bot_heuristic flag from low_priority velocity.</step>

    <!-- P5 — User timeline -->
    <step id="23" status="complete">Write failing request spec `Admin::UsersController#index` search email/name; `#show` timeline `occurred_at` desc.</step>
    <step id="24" status="complete">Implement `/admin/usuarios` list + drill-down with Spanish event labels (i18n es primary).</step>

    <!-- P6 — Auth events -->
    <step id="25" status="complete">Write failing specs: `account_registered`, login/out, `email_confirmed`, `account_deleted` with historical_email/name in properties.</step>
    <step id="26" status="complete">Instrument Devise/OmniAuth/delete flow; emit critical `account_deleted` before user row anonymized.</step>

    <!-- P7 — Billing instrumentation (tables exist) -->
    <step id="27" status="complete">Write failing specs: `paywall_viewed`, `payment_succeeded`/`failed`, `download_completed` idempotency on double click.</step>
    <step id="28" status="complete">Instrument paywall, checkout fulfillment paths, nested download controllers; update event catalog YAML + contract.</step>

    <!-- P8 — Export (no cold archive — ROADMAP #6) -->
    <step id="29" status="complete">Write failing spec: GET `/admin/analytics/export.csv` admin-only, respects filters.</step>
    <step id="30" status="complete">Implement CSV export; re-run spec_doc verifier after new event types stabilized.</step>

    <!-- P9 — QA -->
    <step id="31" status="complete">System spec: anonymous events → login merge → admin funnel; threshold turns `metric--alert` in test.</step>
    <step id="32" status="complete">Update `docs/QA_MANUAL_CHECKLIST.md` admin Analytics section; i18n admin event labels `en`/`es`.</step>
  </implementation_plan>

  <working_notes>
    Admin `users.admin` + ventas shipped — do not re-migrate admin role.
    Monetization KPIs: same rules as `Admin::ReportingScope` (exclude superseded).
    Archive DB, email/Slack alerts, FU-LEGAL-003 full page: ROADMAP Pending #6 only.
    Do not store DXF, SVG, geometry, client absolute paths in `properties`.
    `account_deleted` retains historical identity in properties; user row anonymized after insert.
    Dashboard queries: single `user_events` table; jsonb `->` / `->>` in scopes.
    After any new `event_type`: update YAML catalog + contract + spec_doc verifier in same PR.
  </working_notes>
</task_session>
