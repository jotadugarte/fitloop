# Data Flow & Side-Effect Map — Fitloop

**Purpose:** Maps how entities mutate and propagate throughout Fitloop. AI agents must consult this document to avoid orphan blobs, stale project status, or bypassing workspace bind / pre-flight gates.

**Anchors:** `docs/core/SPEC.md` (workflows W1–W5), `docs/core/SYSTEM_ARCHITECTURE.md` (stack boundaries).

---

## 1. Primary Data Flow — Nesting Job (W3)

End-to-end path from “Start nesting” to downloadable nested DXF:

```
Browser (project#show)
  → POST /projects/:id/nesting_runs
  → NestingRunsController#create
  → NestingRun.create! (status: processing, params_snapshot)
  → Project.update!(status: processing, progress_*)
  → NestingJob.perform_later(nesting_run.id)     [Solid Queue]
  → Nesting::JobRunner.call
       → Nesting::ConfigBuilder → tmp/.../config.json
       → Nesting::CliRunner → nesting_engine (Python CLI)
            → reads input DXFs from Active Storage disk paths
            → writes nested.dxf, placements.json, report.json
       → Nesting::StatusMapper maps report → completed | partial | failed
       → attach nested.dxf + placements.json to Project (Active Storage)
       → NestingRun.update!(status, report_json, finished_at)
       → Project.update!(status, progress_percent, progress_message)
       → Nesting::ProgressBroadcaster → Turbo Stream (project channel)
  → Browser refreshes preview / download via show page
```

**Working directory:** `tmp/nesting_runs/:nesting_run_id/` (ephemeral; safe to purge after attach).

**No nesting math in Ruby:** geometry and placement live only in `nesting_engine/`.

**Margin vs kerf in the engine:** `config.json` passes `margin_mm` and `kerf_mm` from the project snapshot. `nest_libnest2d.nest_multi_bin` buffers pieces via `nest_types.apply_kerf`, then runs **fill → intra-sheet repack → consolidate → intra-sheet repack → inter-sheet search** (libnest2d full-sheet batch with Shapely fallback; `_intra_sheet_repack_search`; `_consolidate_sheets` repack; `_inter_sheet_local_search`) under one `time_limit_sec`. Margin is sheet-edge inset only; kerf is piece-to-piece clearance. See `REQ-FIT-NEST-002` in `SPEC.md`.

---

## 2. Entity Lifecycles

### Project (`projects`)

| Stage | Trigger | DB / storage changes |
|-------|---------|----------------------|
| Create | `Workspace.create!` / `find_or_create!` via `ProjectsController#start` / `#new` | `Project(ephemeral: true)` row; `session[:workspaces][tab_id]` via `Workspace.bind!(session, project, tab_id:)` |
| Draft | Default after create | `status: draft`; may have `input_dxf` attachments (subject to upload validations: size ≤ 10MB, case-insensitive `.dxf` extension, and presence of the `"SECTION"` format marker). |
| Ready | Layers selected + pieces extractable (implicit or explicit) | User can start nesting when `ProjectReadinessValidator` passes |
| Processing | `NestingRunsController#create` | `status: processing`; progress fields updated by `JobRunner` |
| Completed / Partial / Failed | `JobRunner` terminal path | `status` set; `nested_dxf` / `placements_json` attached on success paths |

### SheetStock (`sheet_stocks`)

- Created/updated via nested attributes on project form or workspace sheets PATCH.
- On save/update: `SheetStocks::NormalizeConsumptionOrder` assigns dense `sort_order` `0..n-1` with **all finite stocks first** (stable prior relative order), then the single unlimited stock (if any).
- `Project` validation: at most one row with `quantity: nil` per project.
- UI (Stimulus + SortableJS): drag reorder updates `sort_order`; composer blocks a second unlimited row; finite rows insert before ∞.
- `quantity: nil` means **infinite** sheets for the engine.
- CLI `config.json`: `sheet_stocks_config` rejects more than one `quantity: null` and requires unlimited `sort_order` = max when multiple stocks exist.
- Python `nest_multi_bin`: `stocks_in_consumption_order` consumes finite stocks before unlimited regardless of raw `sort_order` values.
- Destroyed with project (`dependent: :destroy`).

### ProjectLayer (`project_layers`)

| Trigger | Side effect |
|---------|-------------|
| DXF upload | `Dxf::LayerSync` unions layer names → upsert rows (`included` default false) |
| Layer PATCH | `ProjectLayersController#update` sets `included` per checkbox |
| Pre-flight | `ProjectReadinessValidator` reads `included` + piece count |

### NestingRun (`nesting_runs`)

- One row per nesting attempt (including re-nest).
- `params_snapshot` frozen at enqueue time.
- `report_json` stores engine report (+ Rails warnings: cancel, time limit).
- History list on project show; **downloadable** nested DXF remains on **Project** (latest run wins).

### Active Storage blobs

| Attachment on `Project` | Cardinality | Replaced on re-nest? |
|-----------------------|-------------|----------------------|
| `input_dxf` | many | No (accumulates uploads) |
| `nested_dxf` | one | Yes (latest successful/partial run) |
| `placements_json` | one | Yes |

Blobs use standard `active_storage_*` tables; deleting a project does **not** automatically purge blobs unless `dependent` / purge job added — today rely on `Project` destroy cascading attachments via Rails.

---

## 3. Cascading Side Effects

| Trigger | Required side effect | Mechanism |
|---------|---------------------|-----------|
| Workspace start / bind | Session key set | `Workspace.bind!` after ephemeral `Project` create |
| DXF files uploaded | Layer rows synced | `Dxf::LayerSync` after attach |
| Nesting run created | Job enqueued; project → processing | `NestingJob.perform_later` |
| CLI success (completed/partial) | Attach outputs; update statuses | `Nesting::CliRunner` + `StatusMapper` |
| Time limit exceeded | Best-so-far partial + notice | `JobRunner#handle_timeout!` |
| Cancel requested | Run failed; broadcast | `cancel_requested_at` on `NestingRun` |
| Re-nest | New `NestingRun`; replace project blobs | `NestingRunsController#create` again |
| Locale change | Cookie + session | `LocalesController#update` → `LocaleSwitchable#persist_locale!` |

---

## 4. Access Control Flow (W5)

```
GET /empezar (start)
  → Workspace.discard!(session)  [prior workspace]
  → redirect workshop_path
  → Workspace.find_or_create!(session) → ephemeral Project
  → Workspace.bind!(session, project)

GET /projects/:id (and nested routes using SetsWorkspaceProject)
  → Workspace.resolve!(session, id)
  → if session[:workspace_project_id] != id or project discarded:
       Workspace.discard!(session) → redirect start with workspace.expired
  → else: controller action (show, edit, nesting, layers, …)
```

**No PIN gate.** Foreign ephemeral project IDs are not reachable without session bind (ADR-0004).

---

## 5. Real-Time UI (Turbo)

| Channel | Subscriber | Updates when |
|---------|------------|--------------|
| `turbo_stream_from @project` | `projects/show` | `ProgressBroadcaster` replaces `nesting_progress` partial |

No Action Cable caching layer; HTML fragments are source of truth after each broadcast.

---

## 6. Caching & Invalidation

| Layer | Strategy |
|-------|----------|
| HTTP / ETag | `stale_when_importmap_changes` on `ApplicationController` |
| Session | `workspace_project_id`, `locale` — invalidate on discard or key change |
| Active Storage | Blob `key` immutable; replacing attachment creates new blob |
| Python tmp dirs | Per-run folder under `tmp/nesting_runs/`; not shared across runs |

**Critical nodes:** After nesting completes, UI must read **reloaded** `@project` and `Nesting::PreviewPresenter.for(@project)` so `placements_json` attachment is current.

---

## 8. Auto-split workflow (W6)

Post-`partial` nest, ephemeral workspace users resolve orphans before the next nest. State persists in PostgreSQL keyed by `Nesting::PieceKey`.

```
project#show (orphan cards, post-job)
  → PATCH OrphanResolution (pending | system_split | manual)
  → [system_split] POST enqueue Nesting::SplitPlanJob
       → Nesting::SplitPlannerRunner → CLI mode plan_splits
       → split_preview.json → SplitProposal (draft) + Turbo preview SVG
  → POST SplitProposals#accept | #reject | #regenerate (per orphan)
       → accept: DerivedPiece rows, mother piece_key in excluded_piece_keys, OrphanResolution → resolved
       → append projects.session_workflow_log
  → POST “Anidar con piezas actualizadas”
       → NestingRunsController#create (auto-enqueue)
       → Nesting::ConfigBuilder adds excluded_piece_keys, derived_pieces
       → Nesting::JobRunner → normal nest CLI
       → nested.dxf includes cut lines + child labels when splits applied
```

| Entity | Lifecycle notes |
|--------|-----------------|
| `OrphanResolution` | Created/updated when user chooses resolution; `resolved` suppresses re-reporting same `piece_key` |
| `SplitProposal` | `draft` during preview; `accepted`/`rejected` terminal; invalidated on sheet stock change or nest cancel |
| `DerivedPiece` | Materialized on accept; fed into extractor/nest; mother geometry skipped via `excluded_piece_keys` |

**Manual path:** user downloads guidance, edits CAD off-app, uploads new DXF, clicks readiness CTA → `ProjectReadinessValidator` → `resolved` when mother no longer in extract set.

**Forbidden:** auto-split without user opt-in; nest with accepted splits but mother still in extract set; plan_splits math in Ruby.

---

## 9. Composite DXF layers (W7)

When the user sets a **primary layer per file** and optional **auxiliary** layers, extraction and nesting follow the composite pipeline (`REQ-FIT-DXF-002`). Rails owns UI + `ProjectLayer.layer_role`; Python owns geometry.

```
project#layers (grouped by attachment)
  → PATCH primary radio + auxiliary checkboxes
  → ProjectLayer.layer_role (primary | auxiliary) + included
  → ProjectReadinessValidator (auxiliary requires primary on same file)
  → NestingRunsController#create
  → Nesting::ConfigBuilder
       → input_files[]: { primary_layer, auxiliary_layers[] } per attachment
       → (legacy) included_layers union when no primary_layer on that file
  → Nesting::JobRunner → CLI
       → piece_loader → composite_extract.load_composite_pieces
            → CompositePiece (primary rings + decorations[])
       → nest_multi_bin (primary polygon only for placement)
       → decoration_transform (same placement transform as primary)
       → dxf_output.write_nested_dxf (original layer names on nested.dxf)
```

| Stage | Component | Notes |
|-------|-----------|--------|
| Extract | `composite_extract` | `intersection` clip for lines/arcs/polylines; insert point for TEXT/MTEXT/INSERT |
| Preview | `dxf_preview` + Rails presenter | Clipped auxiliary geometry with primary outlines |
| Split + composite | `partition_decorations` | Same cut segments as primary; mother excluded via `excluded_piece_keys` |
| Accept split | `DerivedPiece` + `decorations_json` | `derived_pieces[]` in config; `piece_loader` attaches decorations |
| Nest children | `nest_multi_bin` | Derived `CompositePiece` children nest like any piece |

**Auto-split branch (see also §8, `REQ-FIT-SPLIT-001`):**

```
orphan CompositePiece (mother has decorations)
  → CLI plan_splits → split_preview.json (child outlines + decorations[] per child)
  → SplitProposals#accept → DerivedPiece rows (geometry_json + decorations_json)
  → excluded_piece_keys + derived_pieces in config.json
  → nest → nested.dxf with per-child aux on original layers
```

**Forbidden:** nest auxiliary layers as standalone pieces when `layer_role: primary` is configured; composite association math in Ruby; drop original layer names in composite `nested.dxf` output.

---

## 10. Accounts, paywall, cart, and billing (W6)

**REQ:** `REQ-FIT-AUTH-002`, `REQ-FIT-BILL-001`, `REQ-FIT-BILL-002`, `REQ-FIT-BILL-003` — ADR-0005 (simulate), ADR-0006 (ONVO live).

```
Browser (anonymous or logged-in)
  → nest + preview (no account required)
  → GET nested DXF download
  → Billing::Entitlement (grant? plan quota? email confirmed?)
       → deny → paywall catalog (/taller/descarga-pago)
       → allow → SignedDownloadToken → stream blob

Paywall catalog
  → POST /carrito (guest or user; prices snapshotted on Cart row)
  → GET /carrito → redirect checkout (if line) or paywall (if empty)
  → GET /checkout (requires sign-in + email confirmed)
       → method-first breakdown (MEIC list vs SINPE discount; IVA CR only)

BILLING_GATEWAY=simulate (dev)
  → POST /checkout/simular → Payment (+ snapshot) → FulfillPayment / FailPayment (sync)

BILLING_GATEWAY=onvo (live)
  → POST /checkout/pagar → StartOnvoCheckout → Payment pending + ONVO intent id
       → card: POST /checkout/pagos/:id/tarjeta → confirm intent (3DS → GET /checkout/retorno)
       → sinpe: POST /checkout/pagos/:id/sinpe → transfer instructions → /checkout/procesando/:id (poll)
  → POST /webhooks/onvo (X-Webhook-Secret)
       → payment-intent.succeeded → FulfillPayment (idempotent, locking payment with @payment.lock! inside transaction; subsequent duplicates return :already_fulfilled)
       → payment-intent.failed → FailPayment (locking payment with @payment.lock! inside transaction; subsequent duplicates return :already_terminal; purges SINPE pre-retention staging when applicable)
  → GET /checkout/pagos/:id/estado (poll; client must not grant alone)

SINPE pending checkout (v1.2)
  → PreRetainNestedDxf at checkout start (blob copied; retained_until nil)
  → checkout_lock_active? blocks workshop ≤ workshop_lock_minutes (sinpe_crc only)
  → abandon / timeout releases workshop lock without marking payment failed
  → late webhook after abandon still FulfillPayment
```

| Stage | Component | Side effects |
|-------|-----------|--------------|
| Register/login | Devise + OmniAuth | `users` row; `email_confirmed_at`; merge guest cart on sign-in (user cart wins) |
| Cart add | `Billing::CartUpsert` | Upsert single `carts` row; replace requires confirm flow |
| Workspace bind | `session[:workspaces][tab_id]` | Ephemeral `Project` unchanged ownership model |
| Single purchase (simulate) | `SimulateSingleDownload` | `Payment` (+ snapshot) → `FulfillPayment` → `DownloadGrant` + `retained_nested_dxf`; `retained_until` +24h |
| Single purchase (ONVO) | `StartOnvoCheckout` + webhook | Pending `Payment` + intent; SINPE may pre-retain blob; terminal via `FulfillPayment`/`FailPayment` |
| Plan purchase | Checkout from cart or plan flow | `Subscription` active; `PlanMonthlyUsage` counter; extend `ends_at` from prior end; cart cleared on success |
| Mis pagos | `/mis-pagos` | Grant rows when `retention_active?`; pending SINPE rows while `awaiting_gateway_confirmation?`; payment history excludes `checkout_abandoned_at` |
| Purge | job / lazy / FailPayment | Drop staging or expired `retained_nested_dxf` after `retained_until` or failed pre-retention |

**Data separation:** `Project#nested_dxf` remains on ephemeral project until discard; **durable** copy only on single-purchase success (or SINPE pre-retention staging before fulfill). Plan downloads require live workspace bind + quota. **Cart** rows are billing UX state only — not entitlements until checkout succeeds.

**Forbidden:** grant download or plan entitlement on ONVO client callback alone; mark SINPE payment `failed` on workshop lock timeout or manual abandon; nest math or payment logic in Python (Rails billing only).

---

## 11. Admin ventas reporting (read-only)

**REQ:** `REQ-FIT-ADMIN-001`.

```
Admin user (users.admin)
  → GET /admin/ventas
  → Admin::VentasController#index
       → Admin::ReportingScope (Payment.where(superseded_at: nil))
       → Admin::VentasFilter (dates, status, method, search — no params mutation)
       → DeclarationTotals (succeeded aggregates by CRC/USD)
       → VentasListing (paginated CRC + USD tables)
  → GET /admin/ventas/exportar?…filters…
  → Admin::VentasController#export_xlsx
       → ExportPaymentsXlsx (detail + Hacienda summary sheets per currency)
```

| Stage | Component | Side effects |
|-------|-----------|--------------|
| Index | `VentasController`, filters, listings | **None** on `payments` — read-only |
| Export | `ExportPaymentsXlsx` | **None** — streams XLSX in memory |

**Forbidden:** include `superseded_at` payments in admin ventas scope or Hacienda totals; CSV export endpoints; redirect non-admin users to login (use 404); mutate payments from admin UI.

---

## 12. Admin User Analytics & Event Ingest

**REQ:** `REQ-FIT-ANALYTICS-001`.

```
Browser / Server side actions
  → Analytics::TrackEvent.call(event_type, properties, ...)
  → If critical (e.g. nest_completed, payment_succeeded, account_deleted):
       → sync database write to `user_events`
  → If low_priority (e.g. workspace_started, first_dxf_uploaded, paywall_viewed):
       → check rate limit (max 300/hour per session/user)
       → enqueue TrackEventJob (:analytics queue) → async database write to `user_events`
```

**Queue isolation:** `TrackEventJob` runs on the dedicated `:analytics` Solid Queue queue — separate from the `:default` queue used by `NestingJob`. This prevents high-volume low-priority event writes from competing for workers with time-sensitive nesting operations.

**Anonymization & Merge:**
* On sign-in / registration, anonymous session events are mapped to the signed-in user (`Analytics::MergeAnonymousSession`). The merge runs `in_batches(of: 500)` to avoid long-lock `UPDATE` statements on sessions with large event histories.
* Account deletion anonymizes the user record but preserves user event history. email is stored in `account_deleted` properties JSONB for admin audit.

**NestingJob telemetry:** Telemetry emitted at nesting terminal state is handled by private methods (`emit_nest_telemetry`, `nest_telemetry_properties`, `compute_duration_ms`, `parse_placements`, `parse_sheets_used`, `parse_pieces_count`, `parse_orphans_by_reason`) to keep `NestingJob#perform` under 60 lines (deterministic coding standards).

**Config hot-reload (thread safety):** `Analytics::Thresholds` and `Analytics::EventCatalog` use a class-level `Mutex` + memoized `@config` / `@catalog` to prevent race conditions in Puma multi-threaded environments. `Thresholds` re-reads `analytics.yml` on file mtime change; `EventCatalog` memoizes once per boot (catalog is stable at runtime).

---

## 7. Forbidden Shortcuts

- Do not write to `nested.dxf` from Rails — CLI only.
- Do not skip `ProjectReadinessValidator` before enqueueing `NestingJob`.
- Do not bypass `Workspace.resolve!` for user-facing project routes that use `SetsWorkspaceProject`.
- Do not assume `NestingRun` holds the downloadable DXF — it lives on `Project#nested_dxf`.
- Do not bypass `Analytics::TrackEvent` by writing directly to `UserEvent` model from controller logic.
- Do not enqueue analytics jobs on the `:default` queue — use `:analytics` to isolate telemetry from nesting workloads.
- Do not call `update_all` on unbatched `UserEvent` scopes — use `in_batches(of: 500)` for bulk updates.


