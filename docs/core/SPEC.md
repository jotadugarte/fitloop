# Project Specification — Fitloop

> **REQ-ID format:** `REQ-FIT-[DOMAIN]-[NNN]` — every test must reference the REQ-ID it verifies. See `docs/core/TESTING_STRATEGY_MATRIX.md`.

---

## Purpose

Fitloop is a web application for **DXF sheet nesting**: users start an **ephemeral workspace** (one in-browser session per visit), attach multiple input DXFs, define an ordered **sheet inventory** (finite quantities or infinite), select layers via a **layer checklist**, and run a background nesting job. The Python `nesting_engine` returns a nested DXF, `placements.json`, and `report.json`. The UI shows live progress (Turbo Streams), browser preview, and download. Units are **millimeters** throughout.

Branding assets (logo) live under `images/`. UI copy is internationalized (`en`, `es`).

---

## Domain Glossary

| Term | Definition | In code / UX |
|------|------------|----------------|
| **Project** | Ephemeral nesting workspace: title, parameters, inputs, sheet stocks, selected layers, job state | `Project` model (`ephemeral: true`) |
| **Workspace** | Session-bound aggregate: at most one ephemeral `Project` per browser session | `Workspace` service, `session[:workspace_project_id]` |
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
- **Invariants:** all user-facing rows are `ephemeral: true`; title present when setup completes; ≥1 `SheetStock`; ≥1 `ProjectLayer` with `included: true`; on `completed`/`partial`, nested DXF attached unless validation-only failure

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

1. User starts workspace (`GET /empezar`) → `Workspace` creates/binds an ephemeral `Project` in `session[:workspace_project_id]`.
2. User completes setup (title, sheet stocks, DXF, layers) via the ephemeral setup form.
3. User adds one or more **SheetStock** rows (width, height, quantity finite or ∞). **At most one** ∞ row per project.
4. UI shows a **Priority** column (`#1`, `#2`, …) and legend: engine consumes **top → bottom**.
5. User reorders rows via **drag-and-drop** (SortableJS); new **finite** rows insert before any ∞ row; ∞ is **auto-pinned last** on add, drag, and save.
6. **Sort: finite first** button stable-sorts finite rows (preserves relative order among finites) and keeps ∞ last.
7. `sort_order` persisted; server normalizes finite-before-∞ on save (`SheetStocks::NormalizeConsumptionOrder`).

### W2 — Upload DXFs and select layers

1. User attaches multiple DXF files (Active Storage).
2. System computes union of layer names → **layer checklist** UI.
3. User checks layers to include (`ProjectLayer.included`).

### W3 — Pre-flight and start nesting

1. `ProjectReadinessValidator` blocks if zero layers selected or zero extractable pieces (i18n errors).
2. `NestingJob` enqueued (Solid Queue); status → `processing`; Turbo Stream progress.
3. Rails writes `config.json` + paths; invokes `nesting_engine` **CLI**.
4. On finish: map status **`completed`** \| **`partial`** \| **`failed`**; attach outputs; broadcast UI.

### W4 — Re-nest

1. User triggers new **NestingRun** on same project (“Volver a anidar”).
2. Previous downloadable result replaced; run history retained.

### W5 — Ephemeral session access (no accounts)

1. No user accounts or saved-project list in v1; `GET /projects` redirects to workspace start (`/empezar`).
2. Access to a `Project` requires the browser session cookie and matching `session[:workspace_project_id]` (`Workspace.resolve!`).
3. Opening another ephemeral project ID without bind → redirect to start with `workspace.expired` (HTML) or `RecordNotFound` (internal).
4. Returning home or explicit discard → `Workspace.discard!` destroys the project and clears the session key.

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
| **REQ-FIT-UI-001** | Project CRUD; ordered sheet inventory UI (finite + ∞) | P1 |
| **REQ-FIT-DXF-001** | Multi-DXF upload; union layers; **layer checklist** (i18n) | P2 |
| **REQ-FIT-DXF-002** | **Primary layer per file** + **auxiliary** layers clipped to primary polygons; composite nest + output | v1.2 |
| **REQ-FIT-VAL-001** | Pre-flight: reject zero layers / zero pieces | P2 |
| **REQ-FIT-EXT-002** | Extractor: INSERT on layer, nested blocks depth ≤8, warnings in report | P2 |
| **REQ-FIT-CLI-001** | CLI contract documented; `NestingJob` + `Nesting::CliRunner` | P3 |
| **REQ-FIT-NEST-002** | Multi-bin nest; outputs nested DXF + `placements.json` + `report.json` | P3 |
| **REQ-FIT-NEST-003** | Map job status **`completed`** \| **`partial`** \| **`failed`** from report; orphans in v1 | P3 |
| **REQ-FIT-JOB-001** | Turbo progress, 600s cap → partial + notice, cancel | P3 |
| **REQ-FIT-UI-002** | Browser preview from `placements.json` | P4 |
| **REQ-FIT-NEST-004** | Re-nest: new `NestingRun`, replace download, history | P4 |
| **REQ-FIT-UI-003** | Download nested DXF; workspace start redirect (no saved-project list); session-bound show | P4 |
| **REQ-FIT-UI-004** | Architecture-studio web design; Fitloop identity; polished UI (`en`/`es`) | P4 |
| **REQ-FIT-UI-005** | Locale switcher in layout: EN/ES toggle; `set_locale`; cookie/session persistence | P4 |
| **REQ-FIT-QA-001** | E2E golden DXF; deploy notes (Rails + Python venv) | P4 |
| **REQ-FIT-SPLIT-001** | Opt-in auto-split for orphan pieces (ephemeral workspace; preview → accept → re-nest) | P5 |

### REQ-FIT-AUTH-001 (detail)

**Supersedes pre-2026-05-19 PIN model** — see `docs/core/ADRs/0004-ephemeral-session-access.md`.

- **Create:** `Workspace.find_or_create!` / `create!` → `Project(ephemeral: true)`; `Workspace.bind!` sets `session[:workspace_project_id]`.
- **Read / mutate:** Controllers use `Workspace.resolve!(session, id)` — returns the project only when the session is bound to that ephemeral id.
- **Foreign ID:** Unbound request for another project → `ActiveRecord::RecordNotFound` or redirect to `/empezar` with `workspace.expired`.
- **Leave:** `HomeController` / `Workspace.discard!` destroys the project, cancels active nesting, clears session key.
- **Abandoned:** `Workspace.purge_all_ephemeral!` removes orphan ephemeral rows (no session cookie).
- **Non-goals:** cross-session sharing, PIN recovery, admin override via app UI.

### REQ-FIT-DOM-001 (detail)

- Migrations and models for `Project`, `SheetStock`, `ProjectLayer`, `NestingRun`.
- Defaults: kerf 0, margin 5, curve tolerance 0.1, sheet gap 15, nesting time limit 600s.

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

### REQ-FIT-SPLIT-001 (detail)

**Scope:** v1.1 feature for **ephemeral** workspace projects (`Project#ephemeral?`). After a `partial` nest (or when unresolved orphans remain visible in-session), the user resolves each orphan **opt-in** via per-card actions—no automatic splitting.

**Identity:** `Nesting::PieceKey` (stable string, e.g. `{blob_id}:piece-{index}` or `{blob_id}:fp-{fingerprint}`) keys `OrphanResolution#piece_key` across re-nests; do not rely on `piece_index` alone.

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
- Cross-session project resume (accounts, share links, export/import)
