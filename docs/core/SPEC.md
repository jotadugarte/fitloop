# Project Specification — Fitloop

> **REQ-ID format:** `REQ-FIT-[DOMAIN]-[NNN]` — every test must reference the REQ-ID it verifies. See `docs/core/TESTING_STRATEGY_MATRIX.md`.

---

## Purpose

Fitloop is a web application for **DXF sheet nesting**: users create projects with multiple input DXFs, define an ordered **sheet inventory** (finite quantities or infinite), select layers via a **layer checklist**, protect projects with a **6-digit PIN**, and run a background nesting job. The Python `nesting_engine` returns a nested DXF, `placements.json`, and `report.json`. The UI shows live progress (Turbo Streams), browser preview, and download. Units are **millimeters** throughout.

Branding assets (logo) live under `images/`. UI copy is internationalized (`en`, `es`).

---

## Domain Glossary

| Term | Definition | In code / UX |
|------|------------|----------------|
| **Project** | A nesting workspace: title, parameters, PIN, inputs, sheet stocks, selected layers, job state | `Project` model |
| **SheetStock** | One sheet type: width × height (mm), quantity (integer or **∞**), consumption **sort_order** | `SheetStock` |
| **ProjectLayer** | A DXF layer name discovered from uploads; `included` flag for nesting | `ProjectLayer` |
| **NestingRun** | One execution of the nesting pipeline for a project; stores params snapshot and results | `NestingRun` |
| **Piece** | Runtime polygon (with optional holes) extracted from DXF on selected layers | Python / `PieceId` |
| **Orphan** | Piece not placed; listed in `report.json` with reason code | Report only |
| **Kerf** | Cut width offset between pieces (default 0 mm) | `Project#kerf_mm` |
| **Margin** | Inset from sheet edge (default 5 mm) | `Project#margin_mm` |
| **PIN (user)** | 6-digit code chosen at project create; bcrypt digest stored | `Pin6` |
| **Admin PIN** | 10-digit master PIN in Rails credentials; unlocks any project | `AdminPin10` |
| **Job status** | Terminal nesting outcome: `completed`, `partial`, or `failed` | `NestingRun#status` |

---

## Core Entities

### Project

- **Fields:** `title`, `pin_digest`, `kerf_mm` (default 0), `margin_mm` (5), `curve_tolerance_mm` (0.1), `sheet_gap_mm` (15), `nesting_time_limit_sec` (600), `status` (`draft` \| `ready` \| `processing` \| `completed` \| `partial` \| `failed`), `progress_percent`, `progress_message`, timestamps
- **Attachments (Active Storage):** many `input_dxf`; one `nested_dxf` when job succeeds or is partial
- **Associations:** `has_many :sheet_stocks`, `has_many :project_layers`, `has_many :nesting_runs`
- **Invariants:** title present; ≥1 `SheetStock`; ≥1 `ProjectLayer` with `included: true`; valid 6-digit PIN at create; on `completed`/`partial`, nested DXF attached unless validation-only failure

### SheetStock

- `width_mm`, `height_mm`, `quantity` (nullable = **infinite**), `sort_order` (user-defined consumption priority)
- Engine consumes stocks in `sort_order`; finite quantities decrement per sheet used; ∞ creates additional sheets as needed

### ProjectLayer

- `layer_name` (union of all uploaded DXF layer names), `included` (boolean) — **layer filter** for extraction/nesting

### NestingRun

- `project_id`, parameter snapshot, `status`, `started_at`, `finished_at`, `report_json`, links to result blobs (`nested.dxf`, `placements.json`)

### Piece (runtime, Python)

- Closed contour or INSERT-derived geometry on a selected layer; tessellated per `curve_tolerance_mm`; nested blocks resolved to depth 8; not persisted as a Rails model in v1

---

## Key Workflows

### W1 — Create project and sheet inventory

1. User enters title and chooses a **6-digit PIN**.
2. User adds one or more **SheetStock** rows (width, height, quantity finite or ∞).
3. User orders stocks (Stimulus sortable); `sort_order` persisted.

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

### W5 — Access without account

1. Project list/history visible without login.
2. Opening a project requires user **PIN** or **admin PIN** (`ProjectAccess` service).

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
| **REQ-FIT-AUTH-001** | User **6-digit PIN** at create (bcrypt); admin **10-digit** master PIN from credentials; `ProjectAccess` | P1 |
| **REQ-FIT-UI-001** | Project CRUD; ordered sheet inventory UI (finite + ∞) | P1 |
| **REQ-FIT-DXF-001** | Multi-DXF upload; union layers; **layer checklist** (i18n) | P2 |
| **REQ-FIT-VAL-001** | Pre-flight: reject zero layers / zero pieces | P2 |
| **REQ-FIT-EXT-002** | Extractor: INSERT on layer, nested blocks depth ≤8, warnings in report | P2 |
| **REQ-FIT-CLI-001** | CLI contract documented; `NestingJob` + `Nesting::CliRunner` | P3 |
| **REQ-FIT-NEST-002** | Multi-bin nest; outputs nested DXF + `placements.json` + `report.json` | P3 |
| **REQ-FIT-NEST-003** | Map job status **`completed`** \| **`partial`** \| **`failed`** from report; orphans in v1 | P3 |
| **REQ-FIT-JOB-001** | Turbo progress, 600s cap → partial + notice, cancel | P3 |
| **REQ-FIT-UI-002** | Browser preview from `placements.json` | P4 |
| **REQ-FIT-NEST-004** | Re-nest: new `NestingRun`, replace download, history | P4 |
| **REQ-FIT-UI-003** | Download nested DXF; list without login; PIN gate on show | P4 |
| **REQ-FIT-UI-004** | Architecture-studio web design; Fitloop identity; polished UI (`en`/`es`) | P4 |
| **REQ-FIT-UI-005** | Locale switcher in layout: EN/ES toggle; `set_locale`; cookie/session persistence | P4 |
| **REQ-FIT-QA-001** | E2E golden DXF; deploy notes (Rails + Python venv) | P4 |
| **REQ-FIT-SPLIT-001** | Auto-split oversized pieces (v1.1 backlog) | P5 |

### REQ-FIT-AUTH-001 (detail)

- User selects a **6-digit PIN** at project creation; validate format; store `pin_digest` (bcrypt).
- Admin **10-digit PIN** in `Rails.application.credentials`; grants access to any project.
- No end-user PIN recovery in v1.
- Rate-limit admin PIN attempts.

### REQ-FIT-DOM-001 (detail)

- Migrations and models for `Project`, `SheetStock`, `ProjectLayer`, `NestingRun`.
- Defaults: kerf 0, margin 5, curve tolerance 0.1, sheet gap 15, nesting time limit 600s.

### REQ-FIT-DXF-001 (detail)

- Multiple DXF per project; layer names unioned across files.
- Checkbox **layer filter** persists `ProjectLayer.included`.

### REQ-FIT-NEST-003 (detail)

- **`completed`:** all extractable pieces placed within time limit.
- **`partial`:** time cap reached or some orphans; best-so-far nested DXF + orphan list in report.
- **`failed`:** unrecoverable error (e.g. validation, CLI crash, no usable geometry).
- v1: oversized-for-sheet pieces → **orphans** (no auto-split).

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

- Auto-split oversized pieces → v1.1 (`REQ-FIT-SPLIT-001`)
- FastAPI microservice wrapper
- Hard caps on file size / piece count
- User PIN recovery flow
