# Project Specification — Fitloop

> **REQ-ID format:** `REQ-FIT-[DOMAIN]-[NNN]` — every test must reference the REQ-ID it verifies. See `docs/core/TESTING_STRATEGY_MATRIX.md`.

---

## Purpose

Fitloop is a web application for **DXF sheet nesting**: users start an **ephemeral workspace** (one in-browser session per visit), attach multiple input DXFs, define an ordered **sheet inventory** (finite quantities or infinite), select layers via a **layer checklist**, and run a background nesting job. The Python `nesting_engine` returns a nested DXF, `placements.json`, and `report.json`. The UI shows live progress (Turbo Streams), browser preview, and download. Units are **millimeters** throughout.

Branding assets (logo) live under `images/`. UI copy is internationalized (`en`, `es`, optional joke locale `es_panic`).

---

## Domain Glossary

| Term | Definition | In code / UX |
|------|------------|----------------|
| **Project** | Ephemeral nesting workspace: title, parameters, inputs, sheet stocks, selected layers, job state | `Project` model (`ephemeral: true`) |
| **Workspace** | Session-bound aggregate: ephemeral `Project`(s) per browser tab | `Workspace` service, `session[:workspaces]` hash (`tab_id` → `project_id`) |
| **User** | Persistent account for login, verification, and billing; does **not** own `Project` rows in v1 | `User` model, Devise + OmniAuth |
| **DownloadGrant** | Entitlement to download one `NestingRun`'s nested DXF (plan quota or single purchase) | `DownloadGrant`, signed download token |
| **SheetStock** | One sheet type: width × height (mm), quantity (integer or **∞**), consumption **sort_order** | `SheetStock` |
| **ProjectLayer** | A DXF layer name per DXF file; `included` flag; optional `layer_role` (`primary` \| `auxiliary`) | `ProjectLayer` |
| **CompositePiece** | One nestable unit: primary polygon (+ holes) + attached decoration entities (Python) | `composite_extract` |
| **DecorationEntity** | Non-nestable DXF entity associated to a primary polygon; keeps `layer_name` for output | `composite_extract` |
| **NestingRun** | One execution of the nesting pipeline for a project; stores params snapshot and results | `NestingRun` |
| **Piece** | Runtime polygon (with optional holes) extracted from DXF on selected layers | Python / `PieceId` |
| **Orphan** | Piece not placed; listed in `report.json` with reason code | Report only |
| **Kerf** | Cut width offset between pieces (default 0 mm) | `Project#kerf_mm` |
| **Margin** | Inset from sheet edge (default 5 mm) | `Project#margin_mm` |
| **Job status** | Terminal nesting outcome: `completed`, `partial`, or `failed` | `NestingRun#status` |

---

## Core Entities

### Project

- **Fields:** `title`, `ephemeral` (default `true`), `kerf_mm` (default 0), `margin_mm` (5), `curve_tolerance_mm` (0.1), `sheet_gap_mm` (15), `nesting_time_limit_sec` (600), `status` (`draft` \| `ready` \| `processing` \| `completed` \| `partial` \| `failed`), `progress_percent`, `progress_message`, `session_workflow_log` (JSON), timestamps
- **Attachments (Active Storage):** many `input_dxf`; one `nested_dxf` when job succeeds or is partial
- **Associations:** `has_many :sheet_stocks`, `has_many :project_layers`, `has_many :nesting_runs`
- **Invariants:** all user-facing rows are `ephemeral: true`; title present; ≥1 `SheetStock` before nest start; ≥1 `ProjectLayer` with `included: true` before nest; on `completed`/`partial`, nested DXF attached unless validation-only failure

### SheetStock

- `width_mm`, `height_mm`, `quantity` (nullable = **infinite**), `sort_order` (user-defined consumption priority, dense `0..n-1` per project)
- **At most one** stock per project with `quantity: nil` (∞)
- When an unlimited stock exists, its `sort_order` is **greater than every finite** stock (consumed last)
- Engine consumes stocks in ascending `sort_order`; finite quantities decrement per sheet used; ∞ runs only after finite stocks are exhausted or cannot place more pieces

### ProjectLayer

- `layer_name` per `active_storage_attachment_id`, `included` (boolean), optional `layer_role` (`primary` \| `auxiliary` \| nil)
- **Legacy mode:** no `layer_role: primary` on a file → every `included` layer yields independent nest polygons (current behavior).
- **Composite mode:** exactly one **primary layer per file**; optional **auxiliary** layers contribute decorations only (see `REQ-FIT-DXF-002`).

### NestingRun

- `project_id`, parameter snapshot, `status`, `started_at`, `finished_at`, `report_json`, links to result blobs (`nested.dxf`, `placements.json`)

### Piece (runtime, Python)

- Closed contour or INSERT-derived geometry on a selected layer; tessellated per `curve_tolerance_mm`; nested blocks resolved to depth 8; not persisted as a Rails model in v1

---

## Key Workflows

### W1 — Create project and sheet inventory

1. User starts workspace (`GET /empezar`) → `Workspace.discard!` for the tab → `Workspace.create!` / bind → redirect **`GET /taller`** (Mi taller). No separate «Parámetros iniciales» route (`/projects/new` removed).
2. **Workshop setup mode** (`Project#workshop_setup_mode?` — `draft` and zero `NestingRun` rows): Mi taller shows setup welcome, **Inventario de láminas** and **Detalle DXF** collapsibles **open**, **Parámetros de anidado** inline (not collapsible) between them, preview/progress hidden; primary CTA **«Iniciar anidado»** (errors via flash if láminas/DXF/capas missing — `ProjectReadinessValidator`, including **zero sheet stocks**). **Autosave:** láminas (add/reorder/delete → `PATCH /taller/workspace` `section=sheets`); kerf/margin (debounced `PATCH /taller/nesting_parameters`); DXF layer roles (immediate `PATCH /taller/workspace` `section=layers`, `204 No Content` — no «Aplicar capas»). No separate «Guardar láminas» / «Aplicar» buttons.
3. User adds one or more **SheetStock** rows (width, height, quantity finite or ∞). **At most one** ∞ row per project.
4. UI shows a **Priority** column (`#1`, `#2`, …) and legend: engine consumes **top → bottom**.
5. User reorders rows via **drag-and-drop** (SortableJS); new **finite** rows insert before any ∞ row; ∞ is **auto-pinned last** on add, drag, and save.
6. **Sort: finite first** button stable-sorts finite rows (preserves relative order among finites) and keeps ∞ last.
7. `sort_order` persisted; server normalizes finite-before-∞ on save (`SheetStocks::NormalizeConsumptionOrder`).

**Workshop taller mode** (after first nest run or non-`draft` status): REQ-FIT-UI-003 — láminas and DXF detail collapsibles default **closed** on `/taller`; nesting parameters in collapsed panel at bottom; preview and orphans visible.

### W2 — Upload DXFs and select layers

1. User attaches multiple DXF files (Active Storage) on `/taller`; turbo-stream replaces **`show_source_dxf_detail`** (new uploads expand only the new file's layer checklist).
2. System computes union of layer names → **layer checklist** UI.
3. User selects primary/auxiliary layers per file; selection **autosaves** via `PATCH /taller/workspace` (`section=layers`).

### W3 — Pre-flight and start nesting

1. `ProjectReadinessValidator` blocks if zero sheet stocks, zero layers selected, or zero extractable pieces (i18n errors). Triggered on **«Iniciar anidado»** from Mi taller (setup or taller mode).
2. `NestingJob` enqueued (Solid Queue); status → `processing`; Turbo Stream progress.
3. Rails writes `config.json` + paths; invokes `nesting_engine` **CLI**.
4. On finish: map status **`completed`** \| **`partial`** \| **`failed`**; attach outputs; broadcast UI.

### W4 — Re-nest

1. User triggers new **NestingRun** on same project (“Volver a anidar”).
2. Previous downloadable result replaced; run history retained.

### W5 — Ephemeral session access

1. `GET /projects` redirects to workspace start (`/empezar`); no saved-project list. **`GET /projects/new` is not routed** — configuration happens on `/taller`.
2. Access to a `Project` requires tab-scoped bind: `session[:workspaces][tab_id]` (`Workspace.resolve!` with `tab_id`).
3. Opening another ephemeral project ID without bind → redirect to start with `workspace.expired` (HTML) or `RecordNotFound` (internal).
4. Returning home, explicit discard, or user logout → `Workspace.discard!` destroys the project for that tab and clears the bind.
5. **>120s** without activity on a tab → project expired with explicit message; **≤120s** → same project.

### W6 — Accounts, paywall, and simulated billing

1. Anonymous user may upload, nest, and preview; **nested DXF download** requires login + verified email + grant or active plan.
2. Register/login via OAuth (Google → Facebook → Apple → email) or email/password; terms checkbox; name required.
3. Paywall offers: pay this run (single), view `/planes`, or `/iniciar-sesion`.
4. Simulated checkout: **Tarjeta (USD)** or **SINPE Móvil (CRC)** with success/fail demo buttons.
5. Single purchase: auto-download + blob retained **24h** under user (`/mis-pagos`); plan downloads require live ephemeral project.

---

## Requirements Traceability

| REQ-ID | Summary | Phase |
|--------|---------|-------|
| **REQ-FIT-SPEC-001** | This document: glossary, entities, workflows, REQ traceability | P0 |
| **REQ-FIT-ARCH-001** | `SYSTEM_ARCHITECTURE.md` locks stack; no nesting math in Ruby | P0 |
| **REQ-FIT-APP-001** | Rails 8 scaffold: PostgreSQL, Hotwire, Active Storage, Solid Queue, i18n | P0 |
| **REQ-FIT-EXT-001** | Python package; extract ≥1 closed contour from sample DXF | P0 |
| **REQ-FIT-NEST-001** | Nesting library spike (libnest2d or ADR fallback) | P0 |
| **REQ-FIT-DOM-001** | Models: `Project`, `SheetStock`, `ProjectLayer`, `NestingRun` with defaults | P1 |
| **REQ-FIT-AUTH-001** | Ephemeral **workspace session bind** via `Workspace`; no PIN; `resolve!` for project access | P1 |
| **REQ-FIT-UI-001** | Ephemeral workshop UI (`/taller`); ordered sheet inventory (finite + ∞); contextual setup vs taller modes | P1 |
| **REQ-FIT-DXF-001** | Multi-DXF upload; union layers; **layer checklist** (i18n) | P2 |
| **REQ-FIT-DXF-002** | **Primary layer per file** + **auxiliary** layers clipped to primary polygons; composite nest + output | v1.2 |
| **REQ-FIT-VAL-001** | Pre-flight: reject zero sheet stocks / zero layers / zero pieces | P2 |
| **REQ-FIT-EXT-002** | Extractor: INSERT on layer, nested blocks depth ≤8, warnings in report | P2 |
| **REQ-FIT-CLI-001** | CLI contract documented; `NestingJob` + `Nesting::CliRunner` | P3 |
| **REQ-FIT-NEST-002** | Multi-bin nest; outputs nested DXF + `placements.json` + `report.json` | P3 |
| **REQ-FIT-NEST-003** | Map job status **`completed`** \| **`partial`** \| **`failed`** from report; orphans in v1 | P3 |
| **REQ-FIT-JOB-001** | Live CLI `progress.json`, phased Turbo UI, ETA/cancel in progress panel, 600s cap | P3 |
| **REQ-FIT-UI-002** | Browser preview from `placements.json` | P4 |
| **REQ-FIT-NEST-004** | Re-nest: new `NestingRun`, replace download, history | P4 |
| **REQ-FIT-UI-003** | Download nested DXF; workspace start redirect (no saved-project list); session-bound show | P4 |
| **REQ-FIT-UI-004** | Architecture-studio web design; Fitloop identity; polished UI (`en`/`es`) | P4 |
| **REQ-FIT-UI-005** | Locale switcher: `en` / `es` / optional `es_panic` (easter egg); `set_locale`; cookie/session persistence | P4 |
| **REQ-FIT-QA-001** | E2E golden DXF; deploy notes (Rails + Python venv on Linux VM) | P4 |
| **REQ-FIT-SPLIT-001** | Opt-in auto-split for orphan pieces (ephemeral workspace; preview → accept → re-nest) | P5 |
| **REQ-FIT-AUTH-002** | User accounts: Devise + OmniAuth, email verification, merge opt-in, account routes, delete account | P6 |
| **REQ-FIT-BILL-001** | Paywall on nested DXF only; `config/billing.yml` prices; country-driven CRC/USD + IVA (CR only); ONVO payment intents + webhook fulfillment (`BILLING_GATEWAY`) | P7 |
| **REQ-FIT-BILL-002** | Plans 1/2/4 months; 50 downloads/month; overage 50%; `/mis-pagos`; plan extension from `ends_at` | P7 |
| **REQ-FIT-BILL-003** | `DownloadGrant` authorization; signed download URLs; 24h `retained_nested_dxf` for single purchase | P7 |
| **REQ-FIT-ADMIN-001** | Admin foundation + `/admin/ventas` sales report (filters, CRC/USD tables, Hacienda totals, XLSX export, `cabys_code` on `payments`); stealth 404 gate on `/admin/*` | Pre-live |
| **REQ-FIT-ANALYTICS-001** | Admin analytics & user event bitácora (dashboard, funnel stages, event catalog, analytics.yml thresholds, geo-IP, user timeline, A41 drift contract verifier) | Pre-live |

### REQ-FIT-AUTH-001 (detail)

**Supersedes pre-2026-05-19 PIN model** — see `docs/core/ADRs/0004-ephemeral-session-access.md`.

- **Create:** `Workspace.find_or_create!` / `create!` → `Project(ephemeral: true)`; `Workspace.bind!(session, project, tab_id:)` sets `session[:workspaces][tab_id]`.
- **Read / mutate:** Controllers use `Workspace.resolve!(session, id, tab_id:)` — returns the project only when the tab's bind matches the ephemeral id.
- **Multi-tab:** Each browser tab has a UUID `tab_id` (Stimulus `workspace_tab_controller`); independent ephemeral projects per tab.
- **Tab-close TTL:** On real tab close (`pagehide` without in-app Turbo visit), client sets `fitloop_workspace_tab_left_at` cookie; **>120s** after closing the tab without logout → expire bind on return with `workspace.tab_closed_expired`. Navigating within Fitloop (planes, Mis pagos, paywall) does not start the timer. No idle expiry while the tab stays open.
- **Foreign ID:** Unbound request for another project → `ActiveRecord::RecordNotFound` or redirect to `/empezar` with `workspace.expired`.
- **Leave:** `HomeController` / `Workspace.discard!` destroys the project, cancels active nesting, clears session key.
- **Abandoned:** `Workspace.purge_all_ephemeral!` removes orphan ephemeral rows (no session cookie).
- **Non-goals:** cross-session sharing, PIN recovery, admin override via app UI.
- **Superseded session key:** migrate from `session[:workspace_project_id]` to `session[:workspaces]` per ADR-0005.

### REQ-FIT-QA-001 (detail)

- **Automated E2E:** `spec/system/golden_nesting_e2e_spec.rb` with golden DXF fixture.
- **Production deploy:** bare-metal **Linux VM** — Rails + PostgreSQL + repo-root Python `.venv` on one host ([ADR-0007](ADRs/0007-production-vm-deploy.md), `docs/DEPLOY.md`).
- **Not v1 path:** Northflank, stock `Dockerfile`/Kamal without Python nesting.
- **ONVO webhooks:** local test via ngrok; production via `https://<domain>/webhooks/onvo` on the VM.
- **Manual QA:** `docs/QA_MANUAL_CHECKLIST.md` (includes **Production VM go-live** section).

### REQ-FIT-AUTH-002 (detail)

**Scope:** Persistent `User` accounts orthogonal to ephemeral `Workspace` (ADR-0005). Projects are **not** saved per user.

**Stack:** **Devise** (email/password, `:confirmable`, password minimum **12** characters, password reset) + **OmniAuth** (Google, Facebook, Apple — enabled only when credentials present). UI order: Google → Facebook → Apple → email.

**Routes (Spanish, D41):**

| Path | Purpose |
|------|---------|
| `/iniciar-sesion` | Login |
| `/crear-cuenta` | Registration |
| `/mi-cuenta` | Profile; link to Mis pagos |
| `/mis-pagos` | Payment history (billing) |
| `/planes` | Plan pricing and checkout |

**Registration:**

- **OAuth:** one-click create or sign-in; capture `name`, `email`; trusted-provider email may set `email_confirmed_at` when policy allows.
- **Email/password:** `name` required; `terms_accepted_at` + `terms_version` required; confirmation link before billing actions.
- **Email collision:** if email exists with another method → opt-in **merge** screen (no silent merge).
- **Timezone:** `users.time_zone` captured via `Intl.DateTimeFormat().resolvedOptions().timeZone` on register/plan checkout (Stimulus `timezone_capture_controller`); required before plan purchase.

**Gates:**

- `email_confirmed_at` required before pay or activate plan (D22); rest of app usable while unconfirmed.
- `suspended_at` blocks login actions that pay or download (admin via console in v1).

**Session + workspace:**

- Login/register mid-workflow **keeps** the bound ephemeral `Project` (D18).
- Logout runs `Workspace.discard!` with confirmation when project active (D19).
- Delete account: multi-step confirm; warn if active plan (D15).

**Non-goals v1:** link additional OAuth providers from Mi cuenta (D12); age verification (D17).

**Tests:** `test/spec/auth_billing_spec_doc_test.rb`; Devise/OmniAuth request specs (implementation plan P1).

### REQ-FIT-ADMIN-001 (detail)

**Scope:** Admin foundation to support internal operations (analytics, sales reporting) secure from unauthorized access.

- **Role flag:** `User#admin` is a boolean column default `false`. ActiveRecord automatically generates helper predicate `admin?`.
- **Promotion:** On application boot, the initializer `config/initializers/promote_admins.rb` checks the `FITLOOP_ADMIN_EMAILS` environment variable. If present, it maps the comma-separated emails and updates the matched users setting `admin: true`. Promotion logic checks for the presence of the environment variable and database table before execution, preventing early setup or migration failures and warning log clutter.
- **Admin routes:** Under the `/admin` namespace (linked to `/admin` root index).
- **Stealth access gate:** `Admin::BaseController` enforces authorization via `require_admin!`. Unauthorized requests (both unauthenticated guest requests and authenticated non-admin users) raise `ActionController::RoutingError` which returns a standard **404 Not Found** response to the client. This avoids leaking the existence of the administrative endpoints.
- **Admin dashboard skeleton:** Landing at `/admin` with links to **Ventas** (active: `/admin/ventas`, payment history, Hacienda declaration panels, XLSX export) and **Analytics** (active: `/admin/analytics` KPI dashboard + CSV export, `/admin/usuarios` user bitácora).
- **Admin ventas (`/admin/ventas`):** Read-only reporting on `Payment` rows via `Admin::ReportingScope` (excludes `superseded_at` set). Filters by date (default: current month in `America/Costa_Rica`), status, payment method, and search; separate CRC/USD tables with independent pagination (`crc_page` / `usd_page`). Spanish product labels via `Admin::PaymentDisplayLabels` (e.g. `single_download` → “Procesamiento de anidado DXF”; `plan_N_months` from `product_description`). **Export (XLSX only):** `GET /admin/ventas/exportar` — workbook with per-currency detail + Hacienda summary sheets. **Formulario 150 export:** `GET /admin/ventas/exportar-formulario-150` — second XLSX with «Soporte ventas» (editable detail) + «Formulario 150» (Sección I casillas linked via Excel `SUMIFS` formulas); date filter uses `paid_at` in CR timezone (`Admin::VentasFilter` `date_column: :paid_at`) while the ventas **list** date range uses `created_at` (same query params, different columns). When `status` is omitted (or `status` is an empty array), export defaults to `succeeded` only (`VentasFilter.normalize_form150_export_params`). Period label: both date params explicitly blank → «Sin filtro de fechas»; one bound blank → «—» on that side; timestamp-based filename when any bound is blank. **Sección I casillas (formula-linked):** Total ventas a 13%, Monto de impuesto a 13%, Total ventas exentas con derecho a crédito pleno (USD exportación servicios). Soporte «Rubro Form 150»: succeeded + CRC → gravado 13%; succeeded + USD → exenta crédito pleno; non-succeeded → «No declarable» (outside `SUMIFS` totals). Services: `Admin::ExportForm150Xlsx`, `Admin::VentasXlsxStyles` (shared with `ExportPaymentsXlsx`). Honors status/method/search when provided. Legacy `/admin/ventas/exportar-xlsx` redirects preserving query string. No CSV export.
- **CAByS (Hacienda CR):** `payments.cabys_code` required, default `Payment::DEFAULT_CABYS_CODE` (`8314200000100`), assigned on create; backfill migration for legacy NULL rows.
- **Admin layout:** A clean, minimal layout separate from the main public application shell. CSS rules are kept clean and maintainable under `app/assets/stylesheets/admin.css`.

### REQ-FIT-ANALYTICS-001 (detail)

**Scope:** Internal user analytics dashboard and per-user historical event timeline log (bitácora).

- **Data Model:** Flat `user_events` table with standard columns and `properties` JSONB for metadata. Append-only.
- **Domain types (CbC):** Analytics ingestion uses value objects under `app/models/analytics/` at the `TrackEvent` boundary — `Analytics::EventType` (catalog-validated identifier) and `Analytics::EventPayload` (validated properties + session/geo context, `to_event_attributes` for persistence). Call sites may pass keyword args; `TrackEvent` wraps them via `EventPayload.from_kwargs` before `call_payload`.
- **Pipeline:** `Analytics::TrackEvent` service records events. Critical events are recorded synchronously in the request path; low-priority events are enqueued asynchronously to `TrackEventJob` with a 300/hour rate limit.
- **Queue isolation:** `TrackEventJob` runs on the dedicated `:analytics` Solid Queue queue to prevent high-volume low-priority writes from competing with time-sensitive nesting jobs on the `:default` queue.
- **Funnel Stages:** Sequential conversion stages matching `Analytics::FunnelStages::ORDERED`.
- **Thread-safe config:** `Analytics::EventCatalog` and `Analytics::Thresholds` use a class-level `Mutex` to guard memoized class variables. `Thresholds` hot-reloads on file mtime change; `EventCatalog` memoizes once per boot.
- **Session merge:** `Analytics::MergeAnonymousSession` reassigns anonymous session events to `user_id` on login/register. Uses `in_batches(of: 500)` to prevent long-lock `UPDATE` statements.
- **Drift Governance (A41):** 6-layer contract check enforcing consistency between `ANALYTICS_AND_REPORTING_CONTRACT.md`, `analytics_event_catalog.yml`, code constants, and the `SpecDocVerifier` test suite.
- **Geolocation:** Country code resolved via local GeoLite2 database or Cloudflare header fallback.
- **Anonymization:** Deleting accounts anonymizes user record, but keeps historical timelines by storing email snapshots inside `account_deleted` event properties.
- **Dashboard UI:** Graced with custom Chart.js v4 graphs in internal `/admin/analytics` and `/admin/usuarios` routes.

### REQ-FIT-BILL-001 (detail)

**Scope:** Paywall and **ONVO live payments** (or **simulated** checkout when `BILLING_GATEWAY=simulate`) for **nested DXF** download only (D23). Preview and `placements.json` remain free. Remove orphan DXF download button. See **ADR-0006** for gateway contract.

**Pricing:** `config/billing.yml` with Spanish comments; `Billing::Pricing` hot-reloads on file mtime (D53). Per-product **official** and **SINPE** prices in CRC and USD; overage amounts are explicit keys (not derived from a percentage at display/checkout time). **Typed domain layer:** validated value objects under `app/models/billing/` (`TierMonths`, `PaymentMethod`, `Money`, `CountryCode`, etc.) enforce billing invariants at service boundaries; see ADR-0005 addendum.

**Regional currency and tax (country resolution):**

- Country from `CF-IPCountry` header (Cloudflare **required** in production), GeoLite2 Country MMDB fallback (`GEOLITE2_COUNTRY_MMDB_PATH`), and dev override `FITLOOP_BILLING_COUNTRY_OVERRIDE` (`Billing::GeoPaymentDefaults`). Missing `CF-IPCountry` on billing routes logs `[billing.geo] CF-IPCountry missing` in production (throttled). See `docs/DEPLOY.md` § Billing geo.
- **Default:** `country_code == 'CR'` → CRC + SINPE/card methods; otherwise USD + card only.
- **Manual override:** Paywall/workspace billing selector may set `session[:billing_currency]` and `session[:billing_payment_method]`; overrides IP default until changed.
- **`country_code == 'CR'`:** Prices in CRC. **IVA 13%** on net subtotal (after SINPE discount when applicable), shown only at **checkout**, persisted on `Payment` snapshot fields (`tax_amount`, `total_amount`).
- **`country_code != 'CR'` (or USD selected):** Prices in USD. **No IVA** — do not calculate, charge, or render a tax line.

**Cart (single-item, `REQ-FIT-BILL-001` v1.1):**

- One line per guest (`guest_token`) or user (`user_id`); unique partial indexes enforce at most one row each.
- **Kinds:** `single_download` (requires `nesting_run_id`) or `plan` (requires `tier_months` ∈ {1, 2, 4}).
- **Snapshot at add:** `list_price_cents`, `sinpe_price_cents`, `currency_mode` (`crc` \| `usd`), `overage` flag — frozen until replace or currency refresh.
- **Replace:** POST `/carrito` with a different line → confirm at `/carrito/reemplazar` → PATCH `/carrito` applies pending session payload (`Billing::PendingCart`).
- **Guest flow:** Guest may POST `/carrito`; **checkout requires sign-in** (`RequiresBillingConfirmation`). On login, **user cart wins** — guest cart discarded if both exist (`Billing::CartMergeOnLogin`).
- **Routes:** GET `/carrito` redirects to checkout when a line exists, else paywall. GET `/planes` redirects to checkout when the signed-in user has a cart line.

**MEIC pricing UX (list vs SINPE):**

- Paywall catalog (`/taller/descarga-pago`): hero **SINPE** price in CR; struck/reference **card official** price. Abroad (USD): card price only, no SINPE copy.
- Checkout: dynamic breakdown — list subtotal, optional SINPE discount line, IVA (CR only), total. Method selector precedes breakdown (method-first flow).

**Checkout — amounts (all modes, D37):**

- Display and charge amounts come from **`Billing::CheckoutBreakdown`** only (list, SINPE discount, IVA CR, total). ONVO **payment intent** `amount` = breakdown **total in minor units** (CRC/USD). No ad-hoc cent math in controllers.
- Methods: **Tarjeta (CRC or USD per selection/region)** and **SINPE Móvil (CRC, CR only)**.
- **Payment snapshot (D20, D24):** On terminal success or failure, persist immutable purchaser + financial breakdown on `Payment` (`purchaser_name`, `purchaser_email`, `product_description`, `list_price`, `discount_amount`, `subtotal`, `tax_amount`, `total_amount`, `payment_method`, `currency`). Cart snapshot cents preferred when currency matches checkout method.

**Checkout — ONVO live (`BILLING_GATEWAY=onvo`, ADR-0006):**

- **Provider:** ONVO Payment Intents + embedded SDK (`sdk.onvopay.com`); no hosted Checkout redirect; no ONVO Subscriptions API (plans = one-time intents).
- **Start pay:** Server creates `Payment` `pending`, calls ONVO to create **payment intent** (`metadata` includes internal `payment_id`), stores `onvo_payment_intent_id`.
- **Card:** SDK `onvo.pay` with `ONVO_PUBLISHABLE_KEY`; 3DS return **`/checkout/retorno`**.
- **SINPE:** Collect transferente **cédula** + **teléfono móvil**; create `mobile_number` payment method; show destination number and exact amount from intent.
- **Webhook (authoritative):** `POST /webhooks/onvo` — verify `X-Webhook-Secret` against `ONVO_WEBHOOK_SECRET`; handle `payment-intent.succeeded` \| `payment-intent.failed`. Delegate to **`Billing::FulfillPayment`** / **`Billing::FailPayment`** (idempotent; no double `DownloadGrant`).
- **Client UX:** `onSuccess` → processing screen (poll `GET /checkout/pagos/:payment_id/estado` every 2–3s, max ~60s); do **not** grant on client callback alone.
- **ENV:** `ONVO_MODE`, `ONVO_SECRET_KEY`, `ONVO_PUBLISHABLE_KEY`, `ONVO_WEBHOOK_SECRET`.

**SINPE pending checkout — workshop lock & pre-retention (v1.2):**

- **Config:** `config/billing.yml` → `onvo_pending_checkout.workshop_lock_minutes` (default **15**). `Billing::PendingCheckoutPolicy` computes `lock_expires_at` from `Payment#created_at` + window.
- **Workshop lock:** `Payment#checkout_lock_active?` is true only when `payment_method` is **`sinpe_crc`**, `status` is `pending`, the payment is within `workshop_lock_minutes`, `checkout_lock_released_at` is blank, `superseded_at` is blank, and there is no **downloadable** grant (`DownloadGrant#retention_active?`). **`Billing::PendingCheckoutLock`** delegates to `checkout_lock_active?` (not raw pending).
- **Card pending:** Tarjeta pending payments never set `checkout_lock_active?` — the workshop is not blocked while card checkout awaits ONVO.
- **Lock ≠ payment status:** Workshop lock timeout or user abandon **does not mark payment failed**; `status` stays `pending` until the ONVO webhook (or simulate terminal path) updates it.
- **Manual abandon:** `POST /checkout/pagos/:id/liberar` → **`Billing::ReleasePendingCheckoutLock`** sets `checkout_abandoned_at` and `checkout_lock_released_at` (v1 local only; no ONVO cancel API). Copy warns: if the user already transferred, do not abandon expecting cancellation.
- **Supersede:** Starting a new SINPE checkout for the same `nesting_run_id` while another is pending → **`Billing::SupersedePendingCheckout`** marks the older row `superseded_at` and releases its lock before creating the new pending payment. Block duplicate checkout while `checkout_lock_active?` on the prior attempt.
- **Late webhook:** `payment-intent.succeeded` after `checkout_abandoned_at` or after lock timeout still runs **`Billing::FulfillPayment`** — ONVO is authoritative; user may download once grant is fulfilled.
- **pre-retention (SINPE only):** On SINPE checkout start, **`Billing::PreRetainNestedDxf`** copies `Project#nested_dxf` to `DownloadGrant#retained_nested_dxf` with **`retained_until` nil** until fulfill — staging only; **not** downloadable until `FulfillPayment` sets `retained_until = paid_at + 24.hours` (see REQ-FIT-BILL-003 D54).
- **Failed webhook purge:** On `payment-intent.failed`, **`Billing::FailPayment`** **purge**s the pre-retained blob when the grant has `retained_nested_dxf` attached but `retention_active?` is false (staging never fulfilled). Fulfilled grants are not purged.
- **Lazy lock release:** On first read after `workshop_lock_minutes` elapses, persist `checkout_lock_released_at` (no cron in v1).
- **Status poll / Mis pagos:** Poll while `Payment#awaiting_gateway_confirmation?` (pending single download without terminal status and without a downloadable grant). **SINPE:** includes lock expired and manual abandon (`checkout_abandoned_at`) — transfer may still complete. **Card:** excludes abandoned 3DS-cancel attempts (`checkout_abandoned_at` + card methods) from Mis pagos rows and payment history (`listed_in_payment_history`); poll stops for those attempts.

**Checkout — simulated dev fallback (`BILLING_GATEWAY=simulate`):**

- Demo UI: **Pago exitoso** / **Pago fallido** + environment indicator (hidden when `onvo`).
- `Billing::SimulateSingleDownload` / `Billing::SimulatePlanPurchase` call the same **`Billing::FulfillPayment`** / **`Billing::FailPayment`** services on success/failure.

**Paywall UX (D42):** Catalog at `/taller/descarga-pago` with inline plans + “Añadir al carrito”; paths to checkout (after login), `/iniciar-sesion`.

**Tests:** billing doc verifier (`AuthBillingSpecDocVerifier` + ADR-0006); cart, checkout, webhook, and paywall request specs.

### REQ-FIT-BILL-002 (detail)

**Scope:** Subscription plans **1, 2, and 4 months** (not 3); simulated purchase; entitlement while active.

**Quota (D27):** **50** nested DXF downloads per **calendar month** within the subscription period (tier 1m → 50; 2m → 50+50; 4m → up to 200 total across months). Counters **reset each month** inside the cycle — not one pooled cap.

**Overage (D34):** When monthly plan quota is exhausted, user may buy a **single download** at **50%** of the normal single-download list price (document in terms/plans, FU-LEGAL-002).

**Plan rules:**

- **One active plan** per user at a time.
- Additional purchase of same or different tier **extends** `ends_at` from the **end** of the current plan (D28) — does not restart from today.
- `starts_at` = payment instant; `ends_at` = end of natural day N months later in `users.time_zone` (23:59:59 anchor day, D29).
- **No grace period** after expiry (D30); manual renewal after expiry (D31).
- Post-plan purchase redirect to `project#show` (D43).
- Plan-active download shows brief “Incluido en tu plan” i18n (D33).

**Mis pagos (D38):** `/mis-pagos` — payment history, active plan (expiry, monthly quota used/remaining), single-purchase rows.

**Tests:** plan checkout specs; quota counter specs (implementation plan P4).

### REQ-FIT-BILL-003 (detail)

**Scope:** Authorize nested DXF downloads via **`DownloadGrant`** (and plan quota), not rate limiting (D44).

**Grant model:**

- One active grant per (`user_id`, `nesting_run_id`).
- Re-download same run allowed while grant valid (signed URL per attempt).
- Kinds: `single_purchase` | `plan_included`.

**Signed URLs (D45):** Download endpoint requires token bound to `NestingRun` + user; expiry ~**15 minutes** per request.

**Single-purchase retention (D54):**

- On successful single purchase, copy `Project#nested_dxf` blob to grant attachment **`retained_nested_dxf`** (or `DeliveredDownload` row) **before** workspace may discard project.
- `retained_until` = `paid_at + 24.hours`; download from `/mis-pagos` authorized while `Time.current <= retained_until` even if ephemeral `Project` is gone.
- i18n copy: file available in Mis pagos for **24 hours** after purchase (D55).
- Purge blob after `retained_until` (job or lazy, D56); history row may remain without download button.

**Plan downloads (D50):** No retained blob; re-download only while ephemeral project still bound and quota OK; session loss requires re-nest.

**Auto-download (D39):** Single purchase success triggers auto-download + “Descargar ahora” fallback; plan purchase returns to project without extra step.

**Tests:** `test/spec/auth_billing_spec_doc_test.rb`; download authorization and retention specs (implementation plan P4).

### REQ-FIT-DOM-001 (detail)

- Migrations and models for `Project`, `SheetStock`, `ProjectLayer`, `NestingRun`, `OrphanResolution`, `SplitProposal`, `DerivedPiece` (split/composite v1.1+).
- Defaults: kerf 0, margin 5, curve tolerance 0.1, sheet gap 15, nesting time limit 600s.
- **Typed service boundary (Rails):** Nesting and workshop services parse domain numerics and piece keys via value objects in `app/models/nesting/` (`KerfMm`, `MarginMm`, `CurveToleranceMm`, `SheetGapMm`, `NestingTimeLimitSec`, `JobParameters`, `SheetStockRow`, `PieceKey`). ActiveRecord columns remain `float` / `string`; VOs validate at service and controller boundaries before persistence or CLI payload emission. Kerf and margin are **separate types** (never conflated).

### REQ-FIT-DXF-001 (detail)

- Multiple DXF per project; layer names unioned across files.
- Checkbox **layer filter** persists `ProjectLayer.included`.

### REQ-FIT-DXF-002 (detail)

**Scope:** v1.2 — one DXF file may define a **primary layer** (cut outlines) and optional **auxiliary** layers (engraving, marks, text). Auxiliary geometry is **not** nested alone; it is associated to the primary polygon that contains it and moves with that piece after placement.

**Rails (`ProjectLayer`):**

- `layer_role` enum: `primary` \| `auxiliary` \| nil (legacy).
- **Exclusive primary layer per file:** at most one `layer_role: primary` per `(project_id, active_storage_attachment_id)`; `ProjectLayer::SetPrimary` clears sibling primaries and sets `included: true`.
- UI: one **primary** radio per attachment; **auxiliary** checkboxes; i18n **Capa principal** / **Primary layer**.
- Pre-flight (`REQ-FIT-VAL-001`): if any auxiliary layer is `included` on a file, a **primary layer** must be set for that same attachment.
- `Nesting::ConfigBuilder` emits per-file `primary_layer` + `auxiliary_layers[]` in `input_files[]`; when no primary is set for a file, legacy flat `included_layers` union applies.

**Python value objects:**

- **`CompositePiece`:** primary closed polygon (+ holes) + `decorations[]` (`DecorationEntity` list). Nesting optimizer uses **primary polygon only** (kerf/margin unchanged). `piece_key` identity derives from primary geometry, not decorations.
- **`DecorationEntity`:** normalized DXF entity with preserved **`layer_name`** for output emission.

**Spatial association (per source file, normative):**

- **Inside** = primary polygon fill **including holes as interior** (geometry inside a hole associates to the same piece).
- **Lines / arcs / polylines:** `intersection(entity, primary_polygon)` — keep interior segments only (Option B clip); discard exterior. One entity crossing two primary polygons → two decorations, each clipped independently.
- **TEXT / MTEXT:** include whole entity if **insert point** ∈ primary polygon; no glyph clipping. Outside → silent discard.
- **INSERT:** include if **insert point** ∈ primary polygon; nested block resolution depth ≤8 (`REQ-FIT-EXT-002`). Outside → silent discard.
- **Circles / points:** center-in or clipped arc segments per entity type in `composite_extract`.
- **Outside all primary polygons:** silent discard (no report requirement).

**Extract (`nesting_engine/composite_extract.py`):**

- `load_composite_pieces(path, primary_layer, auxiliary_layers, …)` returns `CompositePiece[]` with spatial index per file.
- `piece_loader` uses composite path when `primary_layer` is present in config; legacy path unchanged otherwise.

**Nest and output:**

- Placement applies the same translate/rotate to primary and decorations (`decoration_transform`).
- **`nested.dxf`** writes primary rings on the **source primary layer name** and decoration entities on their **original layer names** (not forced `PIECES` for composite runs).

**Integration with auto-split (`REQ-FIT-SPLIT-001`):**

- Split cuts apply to the **primary polygon** only; auxiliary layers are **not** split independently.
- `partition_decorations(mother, split_children, cut_segments)` assigns each mother decoration to children via `intersection(decoration, child_primary_polygon)`; decorations crossing a cut split between children (same clip rules as extract).
- Mother `piece_key` remains in `excluded_piece_keys`; children are supplied via `derived_pieces[]` with `rings` and `decorations` / `decorations_json`.
- Split preview and accept materialize per-child decoration payloads; nest of derived composite children preserves **original layer names** after placement.

**Out of v1.2:** different cut angles per auxiliary layer; re-associating decorations across children after nest (only at extract + split).

### REQ-FIT-NEST-002 (detail)

- **Rails typed layer:** `Nesting::JobParameters.from_project` is the SSOT for CLI numeric fields (`kerf_mm`, `margin_mm`, `curve_tolerance_mm`, `sheet_gap_mm`, `time_limit_sec`) consumed by `Nesting::ConfigBuilder`; `Nesting::SheetStockRow` wraps each sheet stock row. Python engine validates parsed config in Phase F (`nesting_config.py`); JSON key names unchanged.
- **Multi-bin:** `nesting_engine/nest_bin.py` consumes ordered `SheetStock` rows (finite quantity or ∞); opens additional sheets when a bin is full.
- **`margin_mm` (sheet edge):** Applied only as inset from the usable bin rectangle (`nest_placement` bin fit and anchor candidates). Does **not** add extra gap between adjacent pieces on the same sheet.
- **`kerf_mm` (piece-to-piece):** Applied in `nest_types.apply_kerf` as a symmetric buffer on each piece polygon before placement; obstacle geometry uses the buffered shape so placed pieces maintain at least `kerf_mm` clearance.
- **Outputs:** `nested.dxf`, `placements.json`, `report.json` per CLI contract; `sheet_gap_mm` offsets sheet rectangles in the combined output DXF (orthogonal to margin/kerf).
- **Placement scoring (`nest_placement.py`):** Among valid placements, the engine **maximizes the largest continuous free area** (mm²) inside the usable sheet (`sheet.difference(occupied ∪ placed)`); **layout footprint** (bounding box of all pieces on the sheet) is the **secondary** tie-breaker, then bottom-left preference. Rotation candidates use `ROTATION_STEP_DEG` (default 5°). Compaction slides pieces toward the origin without overlaps.
- **v1 engine:** Per-piece placement uses Shapely (`nest_placement.py`); single-bin and full-sheet batch paths use libnest2d (`nest_libnest2d.nest_sheet`, `nest_sheet_with_obstacles`). `nest_multi_bin` runs **fill → intra-sheet repack → consolidate → intra-sheet repack → inter-sheet local search** under one `time_limit_sec` (best-so-far on deadline). Intra-sheet repack full re-nests each bin (≥2 pieces), scores with largest continuous free area via `score_sheet_layout`, accepts on layout improvement or successful pull from a later same-stock sheet; rolls back on regression or failed batch map (ADR-0001).

### REQ-FIT-NEST-003 (detail)

- **`completed`:** all extractable pieces placed within time limit.
- **`partial`:** time cap reached or some orphans; best-so-far nested DXF + orphan list in report.
- **`failed`:** unrecoverable error (e.g. validation, CLI crash, no usable geometry).
- v1: oversized-for-sheet pieces → **orphans** (no auto-split). v1.1 adds opt-in resolution per `REQ-FIT-SPLIT-001`.

### REQ-FIT-JOB-001 (detail)

**Scope:** Friendly nesting progress while `Project#status == processing` — phased labels, engine-driven percent, visible cancel and time-remaining copy (`en` / `es` / optional `es_panic`). See `nesting_engine/README.md` § `progress.json`.

**Python (`nesting_engine/progress_reporter.py`):**

- Writes `{output_dir}/progress.json` (schema v1) atomically (temp + rename); throttled updates (≥1s or ≥1% delta); monotonic `percent` 0–100.
- `phase_id` values: `extracting`, `fill`, `optimizing`, `consolidating`, `refining`, `writing_outputs`.
- Hooked in `nest.py` / `nest_libnest2d.py` at pipeline boundaries **without** changing placement algorithms.

**Rails orchestration:**

- **Enqueue:** `StartsNesting` sets `progress_message` to `nesting.phase.queued` (3%) and `estimated_finished_at` to `now + nesting_time_limit_sec` (not a fixed 30s stub).
- **Pre-CLI:** `NestingJob` → `nesting.phase.preparing` (8%); `Nesting::JobRunner` → `nesting.phase.starting` (12%) before `CliRunner`.
- **During CLI:** `Nesting::CliRunner` polls `progress.json` every ~0.2s; `Nesting::ProgressSnapshot` + `Nesting::ProgressSync` update `progress_percent`, `progress_message`, and `estimated_finished_at` (heuristic from `pieces_placed` / `pieces_total` + elapsed, capped by time limit).
- **UI:** `projects/_nesting_progress` shows progress bar (`aria-valuetext` = phase + percent + optional time remaining), **Cancel** (`data-testid="cancel-nesting"`), `nesting.time_remaining`, and `nesting.eta_overrun`. Cancel is **not** duplicated in `show_actions` while processing.
- **Broadcast / poll:** `Nesting::ProgressBroadcaster` and `ProjectsController#nesting_sync` use `Nesting::ProgressLocals` (`active_run`, `time_remaining`, `eta_overrun`).
- **Terminal:** 600s `Timeout` in `JobRunner` → `partial` + `nesting.time_limit_notice`; cancel via `cancel_requested_at` + `Nesting::ApplyCancel` (unchanged).

**Tests:** `nesting_engine/tests/test_progress_reporter.py`, `test_nest_progress.py`, `test_cli_mock.py`; `spec/services/nesting/progress_*_spec.rb`, `cli_runner_spec.rb`, `spec/system/nesting_progress_spec.rb`, `spec/i18n/nesting_phase_labels_spec.rb`.

### REQ-FIT-UI-001 (detail)

**Scope:** Single ephemeral workshop at **`GET /taller`**. No `/projects/new` setup page.

**Modes (`Workshop::UxMode` / `Project#workshop_setup_mode?`):**

| Mode | Predicate | UX |
|------|-----------|-----|
| **Setup** | `draft?` && `nesting_runs.none?` | Welcome copy from `projects.setup.welcome`; láminas + DXF `<details open>`; kerf/margin inline between them; preview/progress hidden; «Iniciar anidado» with readiness errors |
| **Taller** | otherwise | REQ-FIT-UI-003 collapsed láminas/DXF; preview + orphans; nesting parameters panel at bottom |

**Entry:** `GET /empezar` → discard tab project → bind new ephemeral → redirect `/taller`. Toolbar **Mi taller** → `/taller` (auto `find_or_create!` when unbound).

**Collapsible persistence:** On `/taller` in taller mode, `workshop-sheet-inventory` and `workshop-source-dxf-detail` default closed (Stimulus `collapsible_persistence_controller`); setup mode skips forced closed.

**Autosave (setup and taller):** Sheet inventory, nesting parameters, and DXF layer selection persist without explicit save buttons — see W1 step 2 and W2. Layer autosave responds `204 No Content` to avoid turbo-stream races on rapid radio/check changes.

**Tests:** `spec/models/project_spec.rb` (`workshop_setup_mode?`), `spec/presenters/workshop/ux_mode_spec.rb`, `spec/requests/ephemeral_workspace_spec.rb`, `spec/requests/project_nesting_parameters_spec.rb`, `spec/requests/project_dxf_upload_spec.rb`.

### REQ-FIT-UI-005 (detail)

**Scope:** Layout locale switcher and persistence for product locales `en` and `es`, plus optional joke locale **`es_panic`** (“Modo Arquitecto en Pánico”) — humorous Spanish copy across the main workflow; not a fourth production language.

**Rails:**

- `config.i18n.available_locales` includes `:es_panic`.
- `config/locales/es_panic.yml` mirrors the `es.yml` key tree (no runtime fallback to `:es`).
- `LocaleSwitchable` + `LocalesController#update` persist `fitloop_locale` cookie (string `"es_panic"`).
- `shared/_locale_switcher`: row 1 `EN` | `ES`; row 2 full-width **📐 PÁNICO** via `locale.labels.*` (never `locale.to_s.upcase` for `es_panic`).
- i18n keys: `locale.switcher_label` (nav), `locale.switcher_row_primary` (aria-label for EN/ES group), `locale.labels.en` / `es` / `es_panic`.

**Non-goals:** parallel `fitloop.*` namespace; percent-band progress strings (use existing `nesting.phase.*` keys).

**Tests:** `spec/requests/locale_spec.rb`, `spec/i18n/locale_key_parity_spec.rb`, `spec/i18n/nesting_phase_labels_spec.rb`, `spec/lib/fitloop_home_verifier_spec.rb`.

### REQ-FIT-SPLIT-001 (detail)

**Scope:** v1.1 feature for **ephemeral** workspace projects (`Project#ephemeral?`). After a `partial` nest (or when unresolved orphans remain visible in-session), the user resolves each orphan **opt-in** via per-card actions—no automatic splitting.

**Identity:** `Nesting::PieceKey` keys `OrphanResolution#piece_key` across re-nests; do not rely on `piece_index` alone. Accepted formats (Rails `Nesting::PieceKey` / CLI `piece_keys`):

- **Stable:** `{blob_id}:piece-{index}` or `{blob_id}:fp-{16-char hex fingerprint}` (from `Nesting::PieceKeyBuilder` after extract).
- **Legacy numeric:** decimal string index only (e.g. `"0"`, `"11"`) — v1 CLI/orphan rows and ephemeral fixtures; still valid at service boundaries; prefer stable keys for new materialized rows when blob context exists.

**Rails models:**

- **`OrphanResolution`** (`project_id`, `piece_key`, `resolution_state`, `reason` snapshot, optional `last_nesting_run_id`). States: `pending`, `system_split`, `manual`, `resolved`. One active row per `piece_key` per project. `resolved` orphans do not reappear in later runs for the same key.
- **`SplitProposal`** (belongs to `OrphanResolution`): `draft` | `accepted` | `rejected`; JSON `cut_segments`, `child_piece_geometries`, `labels`; `version` for regenerate-after-reject.
- **`DerivedPiece`** (`project_id`, `parent_piece_key`, `label` e.g. Pieza-3a, `geometry_json`, `sort_order`): nestable children after accept.
- **`Project#session_workflow_log`**: append-only JSON array for in-session audit (`splits_applied`, `split_rejected`); not a multi-day history product.

**User workflow (post-job UI on `project#show`):**

1. Orphan cards show badge + choice: leave **`pending`**, **Dividir con Fitloop** (`system_split`), or **Resolver manualmente** (`manual`). User may change mind before materializing.
2. **`system_split`:** enqueue split plan job → mandatory **preview** (inline SVG from engine geometry) → **Aceptar** / **Rechazar** / **Regenerar** per orphan. Accept materializes `DerivedPiece` rows and excludes the mother from nest input.
3. **`manual`:** explicit copy—edit CAD off-app, remove mother geometry, upload corrected DXF; **“He actualizado mis DXF”** runs pre-flight; auto-`resolved` when mother no longer extracts.
4. When all targeted splits are accepted (or user is ready), CTA **“Anidar con piezas actualizadas”** auto-enqueues a normal nest (not only generic re-nest).
5. System split offered for `oversized_for_sheet` and `no_sheet_capacity` when exportable `rings` exist; disabled without rings. No “add sheet” shortcut from orphan UI—user edits `SheetStock` inventory and re-nests. Sheet inventory changes invalidate draft `SplitProposal` rows.

**Engine (`nesting_engine/split_planner.py`):** straight cuts at any angle; preserve holes; minimize sub-piece count; recursive re-split until each child fits largest applicable stock or emit **`split_not_feasible`**. Kerf applies only during nest placement, **not** on the split cut plane. Cut lines and labels (Pieza-Na/Nb) appear in **`nested.dxf`** on successful nest with derived pieces.

**CLI (two invocations, same `config.json` schema extensions):**

| Mode | `config.json` | Output |
|------|---------------|--------|
| Plan | `"mode": "plan_splits"`, `piece_keys[]` (and piece geometry refs as needed) | `split_preview.json` (cuts, child outlines, labels; may include `split_not_feasible` per key) |
| Nest | normal nest fields + `excluded_piece_keys[]`, `derived_pieces[]` | `nested.dxf`, `placements.json`, `report.json` |

Rails: `Nesting::SplitPlanJob` + `Nesting::SplitPlannerRunner` for plan mode; `Nesting::ConfigBuilder` merges exclusions and derived geometry for nest mode. Cancel of an in-flight nesting run invalidates draft proposals tied to that run.

**Out of v1.1:** in-app DXF editing, bulk orphan actions, persistent cross-session orphan history UI.

---

## CLI Contract

v1 integration is **CLI-only** (no FastAPI in MVP). Rails `Nesting::CliRunner` invokes `nesting_engine` with a working directory containing:

### Input: `config.json` (written by Rails)

| Field | Type | Description |
|-------|------|-------------|
| `project_id` | string | Correlation id |
| `input_dxf_paths` | string[] | Absolute paths to input DXFs |
| `included_layers` | string[] | Layer names from **layer filter** |
| `sheet_stocks` | object[] | `{ width_mm, height_mm, quantity \| null, sort_order }` — `null` quantity = infinite |
| `kerf_mm`, `margin_mm`, `curve_tolerance_mm`, `sheet_gap_mm` | number | Project parameters |
| `time_limit_sec` | integer | Default 600 |
| `output_dir` | string | Directory for engine outputs |

### Output files (under `output_dir`)

| File | Description |
|------|-------------|
| `nested.dxf` | Combined nested DXF; sheets offset +X by `sheet_gap_mm` (default 15 mm) |
| `placements.json` | Piece placements per sheet for preview |
| `report.json` | Status hint, orphans, warnings (nested block skips, etc.) |

### Exit semantics

- Process exit code 0 with `report.json` → Rails maps to **`completed`**, **`partial`**, or **`failed`** per report body.
- Non-zero exit → **`failed`** unless partial artifacts present (policy in `Nesting::CliRunner`).

Full JSON schema to be maintained in `nesting_engine/README.md` when the package is scaffolded (P0 step 4 / P3 step 12).

---

## Out of scope (v1)

- FastAPI microservice wrapper
- Hard caps on file size / piece count
- Cross-session **project** resume (projects stay ephemeral; accounts enable billing and 24h single-download retention only)
- Payment providers other than ONVO (e.g. Stripe) — ONVO is the v1 live gateway per ADR-0006
