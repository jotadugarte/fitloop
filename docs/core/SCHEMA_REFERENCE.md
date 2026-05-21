# Schema Reference — Fitloop

**Source of truth:** `db/schema.rb` (version `2026_05_21_025640`). Regenerate this doc when migrations change.

**ORM models:** `Project`, `SheetStock`, `ProjectLayer`, `NestingRun`, `OrphanResolution`, `SplitProposal`, `DerivedPiece` (+ Active Storage attachments on `Project`).

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

## Entity Relationship (logical)

```
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
