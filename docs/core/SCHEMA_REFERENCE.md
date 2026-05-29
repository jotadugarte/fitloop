# Schema Reference — Fitloop

**Source of truth:** `db/schema.rb` (version `2026_05_28_032214`). Regenerate this doc when migrations change.

**ORM models:** `Project`, `SheetStock`, `ProjectLayer`, `NestingRun`, `OrphanResolution`, `SplitProposal`, `DerivedPiece`, `User`, `Subscription`, `Payment`, `DownloadGrant`, `PlanMonthlyUsage`, `Cart` (+ Active Storage attachments on `Project` and `DownloadGrant`).

---

## `projects`

Ephemeral nesting workspace: parameters, job status, progress UI fields.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | bigint | PK | | |
| `title` | string | no | | Display name |
| `ephemeral` | boolean | no | `true` | User-facing projects are session-scoped only (ADR-0004) |
| `status` | string | no | `draft` | `draft`, `ready`, `processing`, `completed`, `partial`, `failed` |
| `session_workflow_log` | jsonb | no | `[]` | Append-only in-session audit (e.g. split actions) |
| `kerf_mm` | float | no | `0.0` | |
| `margin_mm` | float | no | `5.0` | |
| `curve_tolerance_mm` | float | no | `0.1` | Tessellation tolerance |
| `sheet_gap_mm` | float | no | `15.0` | Offset between sheets in output DXF |
| `nesting_time_limit_sec` | integer | no | `600` | Job timeout → partial best-so-far |
| `progress_percent` | integer | yes | | 0–100 during `processing` |
| `progress_message` | string | yes | | i18n message key or text |
| `estimated_finished_at` | datetime | yes | | ETA for progress UI |
| `created_at` | datetime | no | | |
| `updated_at` | datetime | no | | |

**Active Storage (not columns):**

- `has_many_attached :input_dxf`
- `has_one_attached :nested_dxf`
- `has_one_attached :placements_json`

---

## `sheet_stocks`

Ordered sheet inventory per project.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | bigint | PK | | |
| `project_id` | bigint | no | FK → `projects` | |
| `width_mm` | float | no | | |
| `height_mm` | float | no | | |
| `quantity` | integer | yes | | `NULL` = **infinite** sheets; **at most one** `NULL` per `project_id` |
| `sort_order` | integer | no | `0` | Consumption priority (ascending; UI label `#1` = `0`). When `quantity` is `NULL`, `sort_order` must be the maximum among the project's stocks. |
| `created_at` | datetime | no | | |
| `updated_at` | datetime | no | | |

**Indexes:** `index_sheet_stocks_on_project_id`

**Business rules:** At most one unlimited (`quantity IS NULL`) stock per project. After save, all finite stocks have lower `sort_order` than the unlimited stock (if present). Ranks are gapless `0..n-1` per project.

---

## `project_layers`

Per-DXF layer rows: inclusion filter and optional composite roles (`REQ-FIT-DXF-002`).

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | bigint | PK | | |
| `project_id` | bigint | no | FK → `projects` | |
| `active_storage_attachment_id` | bigint | yes | | FK → `active_storage_attachments` (which input DXF) |
| `layer_name` | string | no | | Unique per `(project_id, attachment_id)` |
| `included` | boolean | no | `false` | Include in extraction/nesting |
| `layer_role` | string | yes | | `primary` \| `auxiliary` \| null (legacy flat filter) |
| `color` | string | yes | | UI swatch |
| `created_at` | datetime | no | | |
| `updated_at` | datetime | no | | |

**Indexes:**

- `index_project_layers_on_project_id`
- `index_project_layers_on_active_storage_attachment_id`
- `index_project_layers_on_project_attachment_and_name` (unique)
- `index_project_layers_one_primary_per_attachment` (unique partial: one `primary` per attachment)

**Business rules:** At most one `layer_role: primary` per input DXF attachment; auxiliary layers clip decorations to primary contours in Python.

---

## `nesting_runs`

One row per nesting execution (history); outputs attached to **Project**, not run.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | bigint | PK | | |
| `project_id` | bigint | no | FK → `projects` | |
| `status` | string | no | `processing` | Run-level status |
| `params_snapshot` | jsonb | no | `{}` | Config at enqueue |
| `report_json` | jsonb | no | `{}` | Engine report + Rails metadata |
| `started_at` | datetime | yes | | |
| `finished_at` | datetime | yes | | |
| `cancel_requested_at` | datetime | yes | | User cancel |
| `created_at` | datetime | no | | |
| `updated_at` | datetime | no | | |

**Indexes:** `index_nesting_runs_on_project_id`

---

## `orphan_resolutions`

Per-orphan resolution state for auto-split workflow (`REQ-FIT-SPLIT-001`).

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | bigint | PK | | |
| `project_id` | bigint | no | FK → `projects` | |
| `piece_key` | string | no | | Stable orphan id (`Nesting::PieceKey`) |
| `resolution_state` | string | no | `pending` | `pending`, `system_split`, `manual`, `resolved` |
| `reason` | string | yes | | Snapshot from last orphan report |
| `last_nesting_run_id` | bigint | yes | FK → `nesting_runs` | Run that produced the orphan |
| `created_at` | datetime | no | | |
| `updated_at` | datetime | no | | |

**Indexes:**

- `index_orphan_resolutions_on_project_id`
- `index_orphan_resolutions_on_project_id_and_piece_key` (unique)
- `index_orphan_resolutions_on_last_nesting_run_id`

---

## `split_proposals`

Draft/accepted/rejected split preview for one `OrphanResolution` (`REQ-FIT-SPLIT-001`).

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | bigint | PK | | |
| `orphan_resolution_id` | bigint | no | FK → `orphan_resolutions` | |
| `status` | string | no | `draft` | `draft`, `accepted`, `rejected` |
| `feasible` | boolean | no | `true` | Planner could not split when false |
| `version` | integer | no | `1` | Increments on regenerate |
| `plan_reason` | string | yes | | Engine/planner reason code |
| `cut_segments` | jsonb | no | `[]` | Cut lines for preview |
| `child_piece_geometries` | jsonb | no | `[]` | Child polygons for preview/accept |
| `labels` | jsonb | no | `[]` | Child labels (e.g. Pieza-3a) |
| `created_at` | datetime | no | | |
| `updated_at` | datetime | no | | |

**Indexes:** `index_split_proposals_on_orphan_resolution_id`

**Lifecycle:** Invalidated (destroyed) on sheet inventory change or nest cancel when still `draft`.

---

## `derived_pieces`

Nestable child pieces materialized after split accept (`REQ-FIT-SPLIT-001`, composite via `REQ-FIT-DXF-002`).

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | bigint | PK | | |
| `project_id` | bigint | no | FK → `projects` | |
| `parent_piece_key` | string | no | | Mother orphan key |
| `label` | string | no | | Display label (e.g. Pieza-3a) |
| `geometry_json` | jsonb | no | `{}` | Closed rings for nest |
| `decorations_json` | jsonb | no | `[]` | Auxiliary decorations per child (composite split) |
| `sort_order` | integer | no | `0` | UI ordering |
| `created_at` | datetime | no | | |
| `updated_at` | datetime | no | | |

**Indexes:** `index_derived_pieces_on_project_id`

**Nest config:** Mother's `piece_key` listed in `excluded_piece_keys`; children injected via `derived_pieces` in `Nesting::ConfigBuilder`.

---

## Active Storage tables

Standard Rails 8 tables for blob metadata:

| Table | Purpose |
|-------|---------|
| `active_storage_blobs` | File metadata (`key`, `filename`, `content_type`, `byte_size`, …) |
| `active_storage_attachments` | Polymorphic link `record` → blob (`name`: `input_dxf`, `nested_dxf`, `placements_json`) |
| `active_storage_variant_records` | Image variants (unused for DXF in v1) |

---

## Auth and billing (ADR-0005)

### `users`

| Column | Type | Notes |
|--------|------|-------|
| `email` | string | Unique (Devise) |
| `encrypted_password` | string | Min 12 chars for email auth |
| `name` | string | Required at registration |
| `confirmed_at` | datetime | Gate before billing (`billing_ready?`) |
| `terms_accepted_at` | datetime | Required at registration |
| `terms_version` | string | Legal version id |
| `time_zone` | string | Plan period anchoring |
| `suspended_at` | datetime | Blocks pay/download when set |
| `provider`, `uid` | string | OmniAuth (optional) |

### `carts`

Single-item shopping line for paywall → checkout (guest or signed-in user).

| Column | Type | Notes |
|--------|------|-------|
| `kind` | string | `single_download` \| `plan` (Rails enum on `Cart`) |
| `nesting_run_id` | bigint | FK → `nesting_runs`; set when `kind == single_download` |
| `tier_months` | integer | Set when `kind == plan` (1, 2, or 4) |
| `currency_mode` | string | `crc` \| `usd` — snapshot currency at add |
| `overage` | boolean | Single-download overage flag (default false) |
| `list_price_cents` | integer | Official/card list price at add (integer CRC cents or USD cents) |
| `sinpe_price_cents` | integer | SINPE reference price at add |
| `guest_token` | string | UUID for anonymous cart (unique partial index) |
| `user_id` | bigint | FK → `users` (unique partial index) |

**Business rules:** Exactly one of `guest_token` or `user_id`. Exactly one of `nesting_run_id` or `tier_months`. On login, guest cart merges to user or is discarded if user already has a cart.

### `payments`

Simulated checkout records; financial snapshot columns support admin reporting (D20).

| Column | Type | Notes |
|--------|------|-------|
| `user_id` | bigint | FK → `users` |
| `status` | string | `pending`, `succeeded`, `failed` |
| `payment_method` | string | `card_usd`, `card_crc`, `sinpe_crc` |
| `currency` | string | `usd` \| `crc` |
| `amount` | decimal | Charged unit amount (method-specific base) |
| `purpose` | string | `single_download` \| `plan_subscription` |
| `nesting_run_id` | bigint | Optional; single-download payments |
| `subscription_id` | bigint | Optional; plan payments |
| `paid_at` | datetime | Set on success |
| `purchaser_name` | string | Immutable snapshot at attempt |
| `purchaser_email` | string | Immutable snapshot at attempt |
| `product_description` | string | Immutable snapshot at attempt |
| `list_price` | decimal | List/card price before discount |
| `discount_amount` | decimal | SINPE promo (0 for card) |
| `subtotal` | decimal | Net before tax |
| `tax_amount` | decimal | IVA (0 outside CR) |
| `total_amount` | decimal | Final total |

**Business rules:** Snapshot populated for both `succeeded` and `failed` simulated attempts.

### `subscriptions`

| Column | Type | Notes |
|--------|------|-------|
| `user_id` | bigint | FK → `users` |
| `tier_months` | integer | 1, 2, or 4 |
| `starts_at` | datetime | First purchase instant |
| `ends_at` | datetime | Extended on repurchase from prior `ends_at` |

### `download_grants`

| Column | Type | Notes |
|--------|------|-------|
| `user_id` | bigint | FK → `users` |
| `nesting_run_id` | bigint | FK → `nesting_runs` |
| `kind` | string | `single_purchase` \| `plan_included` |
| `retained_until` | datetime | Single purchase: `paid_at + 24h` |

**Active Storage:** `retained_nested_dxf` attachment for single-purchase retention after workspace discard.

### `plan_monthly_usages`

| Column | Type | Notes |
|--------|------|-------|
| `subscription_id` | bigint | FK → `subscriptions` |
| `period_year`, `period_month` | integer | Calendar month bucket |
| `downloads_used` | integer | Counter within period |
| `quota_limit` | integer | Default 50 |

---

## Entity Relationship (logical)

```
User 1──* Subscription
User 1──* Payment
User 1──* DownloadGrant
User 0..1 Cart
Cart *──0..1 NestingRun
DownloadGrant *──1 NestingRun (via nesting_run_id)
Project 1──* SheetStock
Project 1──* ProjectLayer
Project 1──* NestingRun
Project 1──* OrphanResolution
Project 1──* DerivedPiece
OrphanResolution 1──* SplitProposal
Project 1──* ActiveStorage::Attachment (input_dxf × N, nested_dxf × 1, placements_json × 1)
```

**Cascade:** Destroying a `Project` destroys `sheet_stocks`, `project_layers`, `nesting_runs`, `orphan_resolutions`, and `derived_pieces` (FK). Purge attachment blobs via Rails destroy callbacks on attachments. `split_proposals` cascade via `orphan_resolutions`.

---

## Enums (application-level)

`Project.status` — Rails `enum` on string column (see `app/models/project.rb`).

`NestingRun.status` — string column; values set by `Nesting::JobRunner` / `StatusMapper` (`processing`, `completed`, `partial`, `failed`).

`Cart.kind`, `Cart.currency_mode` — Rails string enums (`single_download`/`plan`, `crc`/`usd`).

`Payment.status`, `Payment.payment_method`, `Payment.currency`, `Payment.purpose` — Rails string enums (see `app/models/payment.rb`).
