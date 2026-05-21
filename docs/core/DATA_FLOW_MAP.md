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
| Create | `Workspace.create!` / `find_or_create!` via `ProjectsController#start` / `#new` | `Project(ephemeral: true)` row; `session[:workspace_project_id]` via `Workspace.bind!` |
| Draft | Default after create | `status: draft`; may have `input_dxf` attachments |
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
  → redirect new_project_path
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

## 7. Forbidden Shortcuts

- Do not write to `nested.dxf` from Rails — CLI only.
- Do not skip `ProjectReadinessValidator` before enqueueing `NestingJob`.
- Do not bypass `Workspace.resolve!` for user-facing project routes that use `SetsWorkspaceProject`.
- Do not assume `NestingRun` holds the downloadable DXF — it lives on `Project#nested_dxf`.
