# Data Flow & Side-Effect Map — Fitloop

**Purpose:** Maps how entities mutate and propagate throughout Fitloop. AI agents must consult this document to avoid orphan blobs, stale project status, or bypassing PIN / pre-flight gates.

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

**Margin vs kerf in the engine:** `config.json` passes `margin_mm` and `kerf_mm` from the project snapshot. `nest_bin.nest_multi_bin` buffers each piece for **kerf** (piece-to-piece gap), then calls `nest_spike` placement with **margin** enforced only against the sheet edges. See `REQ-FIT-NEST-002` in `SPEC.md`.

---

## 2. Entity Lifecycles

### Project (`projects`)

| Stage | Trigger | DB / storage changes |
|-------|---------|----------------------|
| Create | `ProjectsController#create` | Row + `sheet_stocks`; `pin_digest` from 6-digit PIN; session `project_access` granted to creator |
| Draft | Default after create | `status: draft`; may have `input_dxf` attachments |
| Ready | Layers selected + pieces extractable (implicit or explicit) | User can start nesting when `ProjectReadinessValidator` passes |
| Processing | `NestingRunsController#create` | `status: processing`; progress fields updated by `JobRunner` |
| Completed / Partial / Failed | `JobRunner` terminal path | `status` set; `nested_dxf` / `placements_json` attached on success paths |

### SheetStock (`sheet_stocks`)

- Created/updated via nested attributes on project form.
- `sort_order` reassigned on save (`assign_sheet_stock_sort_orders!`).
- `quantity: nil` means **infinite** sheets for the engine.
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
| Project created with valid PIN | Creator session unlock | `grant_project_access!` in `ProjectsController#create` |
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
GET /projects/:id
  → ProjectsController#show
  → project_access_granted? (session flag per project id)
  → if false: render pin_gate (minimal layout)
  → POST verify_pin → ProjectAccess.granted? (user PIN or admin credentials PIN)
  → grant_project_access! → redirect show
```

**Edit/update** require `require_project_access!` (same session flag).

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
| Session | `project_access`, `locale` — invalidate by key change only |
| Active Storage | Blob `key` immutable; replacing attachment creates new blob |
| Python tmp dirs | Per-run folder under `tmp/nesting_runs/`; not shared across runs |

**Critical nodes:** After nesting completes, UI must read **reloaded** `@project` and `Nesting::PreviewPresenter.for(@project)` so `placements_json` attachment is current.

---

## 7. Forbidden Shortcuts

- Do not write to `nested.dxf` from Rails — CLI only.
- Do not skip `ProjectReadinessValidator` before enqueueing `NestingJob`.
- Do not store plaintext PIN — only `pin_digest`.
- Do not assume `NestingRun` holds the downloadable DXF — it lives on `Project#nested_dxf`.
