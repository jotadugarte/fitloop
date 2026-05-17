# Project Roadmap — Fitloop

Web app for DXF sheet nesting: multi-DXF projects, ordered sheet inventory (finite + ∞), layer filter, PIN access, Python nesting engine, live progress, nested DXF + preview. Product spec is locked in `.agenticguild/active_sessions/task_dxf-nesting.md`.

**Format:** `[x]` done · `[ ]` pending · `(REQ-ID)` → `docs/core/SPEC.md` · `— YYYY-MM-DD` done · `— Branch: name` in progress · `— Depends on: Item` blocked

**Next action:** Run `start-task` on **P0 — Anchors & toolchain** (first pending item below).

---

## Done

- [x] agentic:guild OS bootstrap (skills, governance docs, PR template) — 2026-05-16
- [x] Fitloop DXF nesting — requirements exploration & spec lock (decisions D1–D27, implementation plan P0–P5) — 2026-05-16 — Branch: `exploring-task` — Session: `task_dxf-nesting.md`

## In Progress

- [ ] **Fitloop MVP v1 — DXF sheet nesting** — Branch: `exploring-task` — Session: `task_dxf-nesting.md` — Depends on: *(none; start P0)*

## Pending (by priority)

### P0 — Anchors & toolchain *(start here)*

1. [ ] Lock stack in `docs/core/SYSTEM_ARCHITECTURE.md` (Rails 8, Hotwire, PostgreSQL, Solid Queue, Active Storage; nesting math only in Python; kill list) (REQ-FIT-ARCH-001) — Depends on: *(none)*
2. [ ] Populate `docs/core/SPEC.md` with domain glossary, entities, workflows, and REQ-FIT-* traceability (PIN, sheets, layers, statuses `completed|partial|failed`, CLI contract) (REQ-FIT-SPEC-001) — Depends on: Lock stack
3. [ ] Scaffold Rails 8 app at repo root: PostgreSQL, Hotwire, Active Storage, Solid Queue, I18n (`en`, `es`); failing request spec for home → green (REQ-FIT-APP-001) — Depends on: SPEC populated
4. [ ] Add `nesting_engine/` Python package + `requirements.txt` + pytest; failing test: sample DXF → ≥1 closed contour on selected layer (ezdxf + Shapely) (REQ-FIT-EXT-001) — Depends on: Rails scaffold
5. [ ] Spike nesting library (libnest2d or fallback): holes + any-angle rotation; ADR `docs/core/ADRs/0001-nesting-library.md` (REQ-FIT-NEST-001) — Depends on: Python extractor skeleton

### P1 — Domain & access

6. [ ] Models & migrations: `Project`, `SheetStock`, `ProjectLayer`, `NestingRun` (defaults: kerf 0, margin 5, curve tolerance 0.1, sheet gap 15, time limit 600s) (REQ-FIT-DOM-001) — Depends on: P0 complete
7. [ ] PIN access: user 6-digit PIN at create (bcrypt); admin 10-digit master PIN from credentials; `ProjectAccess` service (REQ-FIT-AUTH-001) — Depends on: Models
8. [ ] Project CRUD UI: create project, ordered `SheetStock` (finite + ∞) with Stimulus sortable (REQ-FIT-UI-001) — Depends on: PIN access

### P2 — DXF inputs & validation

9. [ ] Multi-DXF upload (Active Storage); union layer names; layer checklist UI (i18n) (REQ-FIT-DXF-001) — Depends on: Project CRUD
10. [ ] Pre-flight: reject zero layers selected / zero extractable pieces (i18n) via `ProjectReadinessValidator` (REQ-FIT-VAL-001) — Depends on: DXF upload
11. [ ] Python extractor: INSERT on layer (no explode), nested blocks depth ≤8, tessellation tolerance; warnings in report (REQ-FIT-EXT-002) — Depends on: Pre-flight

### P3 — Nesting pipeline

12. [ ] CLI contract JSON schema in `nesting_engine/README.md`; `NestingJob` + `Nesting::CliRunner` (mock → real) (REQ-FIT-CLI-001) — Depends on: Extractor
13. [ ] Python nest: multi-bin ordered `SheetStock`, ∞ sheets, kerf/margin; outputs `placements.json` + `report.json` + nested DXF (sheets offset +X, gap 15mm) (REQ-FIT-NEST-002) — Depends on: CLI bridge
14. [ ] Map job status `completed` | `partial` | `failed` from report; oversized pieces → orphans in v1 (REQ-FIT-NEST-003) — Depends on: Real CLI integration
15. [ ] Job UX: Turbo Stream progress (%, message, ETA overrun text); 600s cap → partial + notice; cancel (REQ-FIT-JOB-001) — Depends on: Status mapping

### P4 — UX completion & ship

16. [ ] Browser preview (SVG/canvas) from `placements.json` (REQ-FIT-UI-002) — Depends on: Nesting pipeline
17. [ ] Re-nest: new `NestingRun`, replace downloadable result, history list (REQ-FIT-NEST-004) — Depends on: Preview
18. [ ] **Locale switcher** — EN/ES toggle in app layout; `LocalesController`; `before_action :set_locale`; persist locale via cookie/session (REQ-FIT-UI-005) — Depends on: Rails scaffold (P0 step 3)
19. [ ] Download nested DXF; project list without login; PIN gate on show; Fitloop UI polish (`en`/`es`) (REQ-FIT-UI-003) — Depends on: Re-nest
20. [ ] **Architecture-studio web design** — Fitloop identity (name + `images/logo.png`), visual language aligned with architecture study workflows, approachable and polished UI (`en`/`es`); locale control styled in header/nav (REQ-FIT-UI-004) — Depends on: Locale switcher (step 18)
21. [ ] E2E with golden sample DXF; manual QA checklist; deploy notes (Rails + Python venv on same host); run `sync-docs` + mark roadmap items done (REQ-FIT-QA-001) — Depends on: UI polish + architecture-studio design (steps 19–20)

### Documentation (parallel after P0 step 2)

- [ ] Enrich `docs/core/DATA_FLOW_MAP.md` (project lifecycle, nesting job side-effects, Turbo broadcasts) — Depends on: SPEC populated
- [ ] Enrich `docs/core/TESTING_STRATEGY_MATRIX.md` (RSpec, pytest, system specs, REQ-ID rule) — Depends on: SPEC populated
- [ ] Add `docs/core/SCHEMA_REFERENCE.md` when first migrations land — Depends on: Models (P1 step 6)

## Backlog

- [ ] **v1.1 — Auto-split** oversized pieces (curved polygons), split-line preview, apply splits then nest; labels Pieza-1a/1b in output DXF (REQ-FIT-SPLIT-001) — Depends on: MVP v1 shipped
- [ ] FastAPI wrapper for nesting engine (optional; v1 uses CLI only)
- [ ] Additional locales beyond `en` / `es`
- [ ] Hard limits on file size / piece count (explicitly out of v1 scope today)
- [ ] PIN recovery flow for users (out of scope v1)

<!-- Reference: full decision log and step-level TDD plan in .agenticguild/active_sessions/task_dxf-nesting.md -->
