# System Architecture & Boundaries — moduSLoop

**Purpose:** Unchangeable technical laws for the moduSLoop platform (with fiTLoop DXF sheet-nesting as its first tool). AI agents must not violate these boundaries without an approved ADR in `docs/core/ADRs/`.

**Product:** moduSLoop is a platform where fiTLoop is the first active tool (ephemeral workspace sessions, multi-DXF projects, ordered sheet inventory (finite + ∞), layer filter, Python nesting engine, live job progress, nested DXF download + browser preview). Brand assets live under `images/` (logo-modusloop.png, fitloop-logo.png).

---

## 1. Technology Stack

| Layer | Choice | Notes |
|-------|--------|--------|
| **Language / runtime** | Ruby 3.x (Rails), Python 3.x (nesting) | Units: millimeters everywhere |
| **Core framework** | **Rails 8** | Monolith at repo root |
| **UI / realtime** | **Hotwire** (Turbo Drive/Frames/Streams + Stimulus) | Progress via Turbo Streams during nesting jobs |
| **Primary database** | **PostgreSQL** | Project persistence, job metadata |
| **File blobs** | **Active Storage** | Input DXFs, nested result DXF |
| **Background jobs** | **Solid Queue** | `NestingJob` invokes Python CLI; cancel + time cap |
| **i18n** | Rails I18n | `en`, `es` in v1; optional joke locale `es_panic` (easter egg, same key tree as `es`) |
| **Auth** | **Devise** | Email/password only (OAuth removed for MVP). Spanish routes (`/iniciar-sesion`, `/crear-cuenta`, `/mi-cuenta`, …). See ADR-0005. |
| **Billing (v1)** | Rails + `config/billing.yml` + **ONVO** (`BILLING_GATEWAY=onvo`) | Live **ONVO** Payment Intents + webhook (`ADR-0006`) or **simulated** checkout (`BILLING_GATEWAY=simulate`, ADR-0005). Paywall on **nested DXF** download; preview and `placements.json` remain free. |
| **Rate Limiting** | **Rack::Attack** (`rack-attack` gem) | Enabled in all environments except test. Throttles authentication and payment routes to 5 requests per minute per IP. Uses `ActiveSupport::Cache::MemoryStore` cache for rate limit states to remain environment-agnostic. |
| **Nesting engine** | Python package `nesting_engine/` | **v1 production:** `nest_libnest2d.nest_multi_bin` (fill → intra-sheet repack ×2 → consolidate → inter-sheet search) with libnest2d full-sheet batch (`nest_sheet`, `nest_sheet_with_obstacles`, ≤128 pieces) and Shapely fallback/scoring (`nest_placement.py`). ezdxf + Shapely. See ADR-0001. |
| **Bridge (v1)** | CLI | Rails writes `config.json` + paths → Python returns `nested.dxf`, `placements.json`, `report.json` |

Rails owns HTTP, **user accounts**, **workspace session access** (`Workspace`), billing orchestration, persistence, validations, and nesting job I/O. Python owns DXF parse, tessellation, nesting math, and nested DXF emission. Python does not serve HTML, own the database, or process payments.

---

## 2. Architectural Paradigm

* **Design pattern:** Rails MVC + **service objects** for domain workflows (`Workspace`, `ProjectReadinessValidator`, `Nesting::CliRunner`). No fat controllers.
* **State:** Server-rendered HTML; Turbo for partial updates and job progress. No separate SPA framework in v1.
* **API:** Server-rendered routes + Turbo Streams; no public REST API in v1.
* **Nesting integration:** ActiveJob → Solid Queue → subprocess/CLI to `nesting_engine` → attach results + broadcast status (`completed` | `partial` | `failed`).

---

## 3. Kill List (Forbidden Patterns)

AI agents **must not** introduce the following without an ADR:

* 🚫 **Nesting math in Ruby:** polygon clipping, placement, rotation search, or libnest2d bindings in Rails. **Rails does not perform nesting math** — only orchestration and I/O.
* 🚫 **Sidekiq / Redis job backend in v1:** use **Solid Queue** only unless ADR changes queue adapter.
* 🚫 **JavaScript SPA frameworks** (React/Vue/Angular app shell) for core UI in v1.
* 🚫 **Exploding INSERT entities to loose geometry** for piece count (v1): one INSERT on selected layer = one piece; nested blocks resolved to depth 8 in Python.
* 🚫 **Python owning persistence:** no SQLAlchemy/ORM project DB in the engine; Rails is system of record.
* 🚫 **Tailwind / CSS-in-JS** unless explicitly adopted later via ADR (default: Rails/CSS following app conventions).
* 🚫 **Margin as inter-piece gap:** Do not apply `margin_mm` between pieces on the same sheet. Sheet-edge inset only (`nest_placement`); piece-to-piece clearance via `kerf_mm` in `nest_types.apply_kerf` (see §7 and `REQ-FIT-NEST-002`).
* 🚫 **Unsanctioned payment gateways:** no Stripe or providers outside **ADR-0006**. Live card/SINPE capture only via **ONVO** when `BILLING_GATEWAY=onvo` (`Billing::Onvo::*`, `POST /webhooks/onvo`). Simulated buttons remain for `BILLING_GATEWAY=simulate` (`Billing::SimulateSingleDownload`, `Billing::SimulatePlanPurchase`).
* 🚫 **Billing math in Python:** prices, grants, subscriptions, and paywall checks stay in Rails.
* 🚫 **Analytics context via thread-locals or class variables in billing services:** `Billing::FulfillPayment` and `Billing::FailPayment` accept `request:` and `session:` as optional keyword arguments — never pass geo/session context via thread-local storage, class-level state, or globals. Services receiving `nil` for these args must gracefully emit analytics with `nil` for geo fields (webhook / job paths).

---

## 4. Environment & Infrastructure

* **Deployment target (v1):** **Bare-metal Linux VM** — Rails + PostgreSQL + repo-root Python `.venv` on one host ([ADR-0007](ADRs/0007-production-vm-deploy.md), `docs/DEPLOY.md`). Docker/Kamal and Northflank are **not** the v1 production path.
* **Secrets:** Rails encrypted credentials for deploy secrets (`RAILS_MASTER_KEY`); OmniAuth and **ONVO** keys via ENV (see `.env.example`, ADR-0006); **no access secrets on `Project`** (session bind only per ADR-0004).
* **Storage:** Active Storage (disk or cloud per env) for DXF inputs and nested output.

---

## 5. Repository Layout (normative)

```
fitloop/                 # Rails 8 app (root)
  app/                   # MVC, jobs, services
  nesting_engine/        # Python package (extract, nest, CLI)
  docs/core/             # SPEC, ADRs, this file
  images/                # moduSLoop / fiTLoop logos and static brand assets
  test/                  # Minitest/RSpec (see TESTING_STRATEGY_MATRIX.md)
```

---

## 6. Traceability

Stack and boundary requirements are tracked in `docs/core/SPEC.md` as `REQ-FIT-ARCH-*` and verified by `test/architecture/system_architecture_doc_test.rb` (`[REQ-FIT-ARCH-001]`).

---

## 7. Nesting engine — margin vs kerf (normative)

| Parameter | Role | Where enforced |
|-----------|------|----------------|
| **`margin_mm`** | Inset from **sheet edges** only | `nest_placement` bin fit and anchor candidates |
| **`kerf_mm`** | Minimum **piece-to-piece** clearance | `nest_types.apply_kerf` (symmetric buffer before placement obstacles) |

**Requirement detail:** `REQ-FIT-NEST-002` in `docs/core/SPEC.md`. **Data flow:** `docs/core/DATA_FLOW_MAP.md` §1 (W3).

**v1 placement library (ADR-0001):** Multi-bin orchestration in `nest_libnest2d.nest_multi_bin` under one `time_limit_sec` deadline:

1. **Fill** — `_place_on_one_sheet`: full-sheet `nest_sheet` / `nest_sheet_with_obstacles` (kerf via `apply_kerf`; fixed obstacle `Item`s); Shapely per-piece fallback when batch places zero.
2. **Intra-sheet repack** (×2, post-fill and post-consolidate) — `_intra_sheet_repack_search`: full re-nest per bin with ≥2 pieces; accept on `score_sheet_layout` / layout-score improvement or pull from a later same-stock sheet; rollback on regression.
3. **Consolidate** — `_consolidate_sheets`: pairwise per-piece merge + `_try_repack_merge_sheets` for sparse donors.
4. **Inter-sheet search** — `_inter_sheet_local_search`: repack from sparse later sheets onto earlier same-size sheets.

Shapely in `nest_placement.py` is used for per-piece fallback, whole-sheet scoring (`score_sheet_layout`, `_layout_better_than`), and largest-free-area tie-breaks—not for the primary multi-bin fill path.

---

## 8. Sheet inventory & consumption order (normative)

| Layer | Module / service | Responsibility |
|-------|------------------|----------------|
| **Rails UI** | Stimulus `sheet_inventory_controller.js` + SortableJS | Priority column, drag reorder, pin unlimited (∞) row last, block second ∞ in composer |
| **Rails domain** | `SheetStocks::NormalizeConsumptionOrder` | Dense `sort_order` `0..n-1`: all finite stocks first (stable prior order), then the single unlimited stock |
| **Rails domain** | `SheetStocks::SyncInventory` | Form is source of truth: destroy sheet stocks omitted from nested attributes |
| **Rails domain** | `SheetStocks::InvalidateNestingOutputs` | Purge stale `nested_dxf` / `placements_json` when inventory changes after a terminal nest |
| **Rails validation** | `Project#at_most_one_unlimited_sheet_stock` | At most one `SheetStock` with `quantity: nil` per project |
| **CLI contract** | `nesting_engine/sheet_stocks_config.py` | Parse and validate `config.json` `sheet_stocks` (one ∞ max; ∞ must have highest `sort_order` when multiple stocks) |
| **Engine** | `nest_libnest2d.stocks_in_consumption_order` | Consume finite stocks before unlimited regardless of mis-ordered client `sort_order` |

**Requirement detail:** `REQ-FIT-UI-001`, `REQ-FIT-DOM-001`, `REQ-FIT-NEST-002`, `REQ-FIT-CLI-001` in `docs/core/SPEC.md`. **Data flow:** `docs/core/DATA_FLOW_MAP.md` § SheetStock.

---

## 9. CLI progress, split planner, and composite extract (normative)

| Mode / artifact | Python module | Rails role |
|-----------------|---------------|------------|
| **`progress.json`** | `progress_reporter.py` (write); `nest.py` phases | `Nesting::CliRunner` polls; `ProgressSnapshot` + `ProgressSync` update UI |
| **`plan_splits` / split preview** | `split_planner.py`, CLI `plan_splits` | `Nesting::SplitPlannerRunner` → `split_preview.json`; Turbo preview SVG |
| **Composite pieces** | `composite_extract.py`, `decoration_transform.py` | `ProjectLayer.layer_role`; config via `Nesting::ConfigBuilder` |
| **Flat layer filter (legacy)** | `extract.py` | `ProjectLayer.included` without `primary` |

Rails orchestrates subprocess I/O only; no split geometry or composite clipping in Ruby.

**Requirement detail:** `REQ-FIT-JOB-001`, `REQ-FIT-SPLIT-001`, `REQ-FIT-DXF-002` in `docs/core/SPEC.md`. **Data flow:** `docs/core/DATA_FLOW_MAP.md` §§ Nesting job, Auto-split, Composite layers.

### 9.1 Nesting / workshop domain types (CbC, normative)

| Layer | Location | Responsibility |
|-------|----------|----------------|
| **Rails VOs** | `app/models/nesting/` | Pure Ruby types (`KerfMm`, `MarginMm`, `CurveToleranceMm`, `SheetGapMm`, `NestingTimeLimitSec`, `JobParameters`, `SheetStockRow`, `PieceKey`) — parse/validate at service and controller boundaries; **not** ActiveRecord models |
| **CLI numerics SSOT** | `Nesting::JobParameters.from_project` → `Nesting::ConfigBuilder` | Emits legacy `config.json` keys (`kerf_mm`, `margin_mm`, `curve_tolerance_mm`, `sheet_gap_mm`, `time_limit_sec`) unchanged |
| **Workshop kerf/margin** | `Nesting::AssignNestingParameters` | Parses `PATCH` nesting parameters before AR assign; invalid values → `422` |
| **Python validation** | `nesting_engine/nesting_config.py` | `parse_job_parameters_from_config` fail-fast before `nest.py` / `plan_splits` |
| **Persistence edge** | `Project`, `SheetStock`, `OrphanResolution` | DB columns remain `float` / `string`; `.to_f` / `.to_s` only when saving or building JSON |

**Invariants:** `KerfMm` and `MarginMm` are **separate types** (never conflated). Do **not** use `Billing::*` types in nesting or workshop code paths.

**Requirement detail:** `REQ-FIT-NEST-002`, `REQ-FIT-DOM-001`, `REQ-FIT-CLI-001`, `REQ-FIT-SPLIT-001` in `docs/core/SPEC.md`. **ADR:** `docs/core/ADRs/0001-nesting-library.md` (Rails CbC addendum).

---

## 10. User accounts, admin, and billing (normative)

| Layer | Module / service | Responsibility |
|-------|------------------|----------------|
| **Auth** | Devise controllers under `app/controllers/users/` | Register, login, email confirmation, password reset; account edit/delete (OAuth callbacks removed for MVP) |
| **Admin** | `BaseController`, `DashboardController`, `VentasController`, `promote_admins.rb`; `Admin::ReportingScope`, `VentasFilter` (optional `date_column: :paid_at` for Form 150), `VentasListing`, `DeclarationTotals`, `HaciendaSummaryRows`, `ExportPaymentsXlsx`, `ExportForm150Xlsx`, `VentasXlsxStyles`, `PaymentDisplayLabels` | `users.admin` promoted via `FITLOOP_ADMIN_EMAILS` on boot. `/admin/*` requires `admin?` else `RoutingError` (404). **Ventas:** read-only `Payment` reporting at `/admin/ventas`; excludes superseded rows; XLSX at `/admin/ventas/exportar` (detail + Hacienda summary) and `/admin/ventas/exportar-formulario-150` (soporte + Formulario 150 `SUMIFS` casillas) via **`caxlsx`** only (`require "axlsx"` — shared styles in `VentasXlsxStyles`; do not add `caxlsx_rails` without ADR). List filters use `created_at`; Form 150 export uses `paid_at`. No nesting or billing mutation in admin layer |
| **Workspace** | `Workspace`, `SetsWorkspaceProject`, `ResolvesWorkspaceTab` | Ephemeral `Project` per browser tab (`session[:workspaces]`); tab cookie/header; 120s TTL after tab close (ADR-0004, extended in ADR-0005) |
| **Paywall** | `DownloadPaywallController`, `RequiresNestedDownloadAuthorization` | Nested DXF only; catalog at `/taller/descarga-pago` with MEIC pricing; guests and unconfirmed users redirected; signed download token (~15 min) |
| **Cart** | `Cart`, `CartController`, `Billing::CartUpsert`, `Billing::CartMergeOnLogin`, `Billing::PendingCart` | Single-item DB cart (guest or user); price snapshot at add; replace-confirm; merge on login (user wins) |
| **Billing** | `Billing::Pricing`, `Billing::CheckoutBreakdown`, `Billing::CheckoutPaymentMethod`, `Billing::Onvo::*`, `Billing::FulfillPayment`, `Billing::Simulate*`, `config/billing.yml` | **ONVO** card (CRC/USD) and SINPE (CRC) when `BILLING_GATEWAY=onvo`; simulated fallback; MEIC list vs SINPE discount; IVA CR only at checkout; webhook at `POST /webhooks/onvo`; plans 1/2/4 months; monthly quota; payment snapshots; 24h retention on `DownloadGrant` |
| **Account UI** | `/mis-pagos`, `/planes`, `/carrito`, `/checkout` | Plan purchase and retained download after workspace loss; cart is internal redirect to checkout |
| **Rate Limiting** | `Rack::Attack` | Throttles brute-force attempts on `/iniciar-sesion`, `/crear-cuenta`, `/checkout/pagar`, `/checkout/pagos/*/sinpe`, and `/checkout/pagos/*/tarjeta` to 5 requests per minute per IP. Bypassed in tests. |
| **Log Filtering** | `config/initializers/filter_parameter_logging.rb` | Masks sensitive credit card, CVV, holder names, Sinpe mobile numbers/identities, and generic variants from application log trails to preserve PCI-DSS compliance in production. |

Projects remain **ephemeral** — `User` does not own saved projects. Persisted billing rows (`payments`, `subscriptions`, `download_grants`) are the system of record for monetization.

**Requirement detail:** `REQ-FIT-AUTH-002`, `REQ-FIT-BILL-001`..`003`, `REQ-FIT-ADMIN-001` in `docs/core/SPEC.md`. **ADRs:** `docs/core/ADRs/0005-user-accounts-and-simulated-billing.md`, `docs/core/ADRs/0006-onvo-live-billing.md`. **Data flow:** `docs/core/DATA_FLOW_MAP.md` § User and billing.

---

## 11. Analytics pipeline (normative)

**REQ:** `REQ-FIT-ANALYTICS-001`. **ADR:** `docs/core/ADRs/0008-admin-analytics-and-user-events.md`.

| Layer | Module / service | Responsibility |
|-------|------------------|----------------|
| **Event type** | `Analytics::EventType` | Parses and validates `event_type` strings against `EventCatalog`; rejects unknown types at VO construction |
| **Payload** | `Analytics::EventPayload` | Boundary VO: catalog `required_properties`, session/geo context, `to_event_attributes` for `UserEvent` / job serialization |
| **Ingestion** | `Analytics::TrackEvent` | Single call-site; accepts kwargs → `EventPayload.from_kwargs` → `call_payload`; dispatches critical events synchronously, low-priority via `TrackEventJob` with 300/hour rate limit per session/user |
| **Nest telemetry context** | `Analytics::NestTelemetryContext` | Resolves user/session fields for `nest_completed` from pre-start project events (workshop types preferred on async fallback) |
| **Queue isolation** | `TrackEventJob` (`queue_as :analytics`) | Dedicated Solid Queue queue; isolates analytics writes from nesting workloads on `:default` queue |
| **Catalog** | `Analytics::EventCatalog` (`config/analytics_event_catalog.yml`) | Memoized with `Mutex` (thread-safe); maps `event_type` → `priority` + `required_properties`; reloaded only on boot |
| **Thresholds** | `Analytics::Thresholds` (`config/analytics.yml`) | Hot-reload on file mtime with `Mutex` guard; exposes funnel conversion %, payment failure %, nest p95, low-priority rate limit |
| **Funnel** | `Analytics::FunnelStages::ORDERED` | Ordered constant: `workspace_started → first_dxf_uploaded → nest_completed → paywall_viewed → payment_succeeded → download_completed` |
| **Geo** | `Analytics::ResolveCountry` | `CF-IPCountry` header (Cloudflare production), GeoLite2 MMDB fallback; returns nil when request is nil |
| **Session merge** | `Analytics::MergeAnonymousSession` | On login/register: reassigns anonymous events to `user_id`; uses `in_batches(of: 500)` to prevent long-lock UPDATE on large event histories |
| **Dashboard** | `Admin::AnalyticsController` | `/admin/analytics` — funnel KPIs (single GROUP BY with `reorder(nil)` to avoid Postgres ORDER BY conflict), monetization from `Admin::ReportingScope`, bot heuristic, CSV export; safe `Date.parse` with rescue |
| **Timeline** | `Admin::UsersController` | `/admin/usuarios` — search + per-user event timeline |
| **Drift governance** | `SpecDocVerifier` + `spec_doc_test.rb` | Asserts: catalog event types ↔ Ruby constants ↔ contract doc; funnel stages ↔ contract; XLSX headers ↔ contract; threshold keys ↔ contract. Failing = reminder to update dashboards/ventas |

**Invariants:**
- Never bypass `Analytics::TrackEvent` — do not write directly to `UserEvent` from controllers or jobs.
- Ingestion boundary is `Analytics::EventPayload` — validate event type and required properties via the VO, not ad hoc in controllers.
- Analytics jobs use `:analytics` queue only — never `:default`.
- Bulk `UserEvent` updates (e.g. session merge) must use `in_batches` — no unbounded `update_all`.
- `EventCatalog` and `Thresholds` config access must go through the memoized class method (not `load_catalog` / `load_config` directly) to benefit from thread-safe caching.
- After any new `event_type`: update `analytics_event_catalog.yml` + `ANALYTICS_AND_REPORTING_CONTRACT.md` + `SpecDocVerifier` in the same PR (rule 67 in `.cursorrules`).
