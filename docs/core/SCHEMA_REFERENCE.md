# Schema Reference — Fitloop

**Source of truth:** `db/schema.rb` (version `2026_05_17_120000`). Regenerate this doc when migrations change.

**ORM models:** `Project`, `SheetStock`, `ProjectLayer`, `NestingRun` (+ Active Storage attachments on `Project`).

---

## `projects`

Nesting workspace: parameters, job status, progress UI fields, PIN digest.

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | bigint | PK | | |
| `title` | string | no | | Display name |
| `pin_digest` | string | yes | | bcrypt of 6-digit user PIN |
| `status` | string | no | `draft` | `draft`, `ready`, `processing`, `completed`, `partial`, `failed` |
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

Layer filter checklist (union of all uploaded DXF layer names).

| Column | Type | Null | Default | Notes |
|--------|------|------|---------|-------|
| `id` | bigint | PK | | |
| `project_id` | bigint | no | FK → `projects` | |
| `layer_name` | string | no | | Unique per project |
| `included` | boolean | no | `false` | Include in extraction/nesting |
| `created_at` | datetime | no | | |
| `updated_at` | datetime | no | | |

**Indexes:**

- `index_project_layers_on_project_id`
- `index_project_layers_on_project_id_and_layer_name` (unique)

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
Project 1──* ActiveStorage::Attachment (input_dxf × N, nested_dxf × 1, placements_json × 1)
```

**Cascade:** Destroying a `Project` destroys `sheet_stocks`, `project_layers`, and `nesting_runs` (FK). Purge attachment blobs via Rails destroy callbacks on attachments.

---

## Enums (application-level)

`Project.status` — Rails `enum` on string column (see `app/models/project.rb`).

`NestingRun.status` — string column; values set by `Nesting::JobRunner` / `StatusMapper` (`processing`, `completed`, `partial`, `failed`).
