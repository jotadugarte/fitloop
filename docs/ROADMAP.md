# Project Roadmap — Fitloop

Web app for DXF sheet nesting: multi-DXF projects, ordered sheet inventory (finite + ∞), layer filter, PIN access, Python nesting engine, live progress, nested DXF + preview. Product spec is locked in `.agenticguild/active_sessions/task_dxf-nesting.md`.

**Format:** `[x]` done · `[ ]` pending · `(REQ-ID)` → `docs/core/SPEC.md` · `— YYYY-MM-DD` done · `— Branch: name` in progress · `— Depends on: Item` blocked

**Last audit:** 2026-05-18 — full-sheet libnest2d epic shipped (`nest_multi_bin` fill + consolidate repack + inter-sheet search).

**Next action:** Backlog — v1.1 auto-split (`REQ-FIT-SPLIT-001`) or optional FastAPI wrapper.

---

## Status summary

| Phase | Scope | Status |
|-------|--------|--------|
| P0 | Anchors & toolchain | **Complete** |
| P1 | Domain & access | **Complete** |
| P2 | DXF inputs & validation | **Complete** |
| P3 | Nesting pipeline | **Complete** |
| P4 | UX completion & ship | **Complete** |
| Docs | Core reference docs | **Complete** |
| P5 / Backlog | v1.1+ | **Not started** |

**MVP v1 (REQ-FIT-APP-001 through REQ-FIT-QA-001, excluding UI-004/005):** merged to `main` via PR #1 (`exploring-task`, 2026-05-16). Branch `finish` tracks post-merge cleanup.

**Verified in codebase:** Rails 8 app, domain models + migrations, PIN gate, multi-DXF + layers, `nesting_engine/` CLI, `NestingJob` + Turbo progress, preview SVG, re-nest history, golden E2E spec, `docs/DEPLOY.md` + `docs/QA_MANUAL_CHECKLIST.md`, REQ-tagged RSpec + pytest suites.

**Not implemented:** sheet-stock consumption priority UX (finite → ∞ default); v1.1 auto-split; optional FastAPI wrapper; hard file/piece caps; PIN recovery.

---

## Done

- [x] agentic:guild OS bootstrap (skills, governance docs, PR template) — 2026-05-16
- [x] Fitloop DXF nesting — requirements exploration & spec lock (decisions D1–D27, implementation plan P0–P5) — 2026-05-16 — Session: `task_dxf-nesting.md`
- [x] **P0 — Anchors & toolchain** (items 1–5) — 2026-05-16
- [x] **P1 — Domain & access** (items 6–8) — 2026-05-16
- [x] **P2 — DXF inputs & validation** (items 9–11) — 2026-05-16
- [x] **P3 — Nesting pipeline** (items 12–15) — 2026-05-16
- [x] **Fitloop MVP v1 — core product** (P4 items 16–17, 19, 21; merged PR #1) — 2026-05-16 — Session: `task_dxf-nesting.md`

### P0 — Anchors & toolchain

1. [x] Lock stack in `docs/core/SYSTEM_ARCHITECTURE.md` (REQ-FIT-ARCH-001) — 2026-05-16
2. [x] Populate `docs/core/SPEC.md` (REQ-FIT-SPEC-001) — 2026-05-16
3. [x] Scaffold Rails 8 app + Fitloop home (REQ-FIT-APP-001) — 2026-05-16
4. [x] `nesting_engine/` extract + pytest (REQ-FIT-EXT-001) — 2026-05-16
5. [x] Nesting library spike + ADR-0001 (REQ-FIT-NEST-001) — 2026-05-16

### P1 — Domain & access

6. [x] Models: `Project`, `SheetStock`, `ProjectLayer`, `NestingRun` (REQ-FIT-DOM-001) — 2026-05-16
7. [x] PIN access + `ProjectAccess` (REQ-FIT-AUTH-001) — 2026-05-16
8. [x] Project CRUD + ordered `SheetStock` UI (REQ-FIT-UI-001) — 2026-05-16

### P2 — DXF inputs & validation

9. [x] Multi-DXF upload (Active Storage); union layer names; layer checklist UI (i18n) (REQ-FIT-DXF-001) — 2026-05-16
10. [x] Pre-flight: reject zero layers selected / zero extractable pieces (i18n) via `ProjectReadinessValidator` (REQ-FIT-VAL-001) — 2026-05-16
11. [x] Python extractor: INSERT on layer (no explode), nested blocks depth ≤8, tessellation tolerance; warnings in report (REQ-FIT-EXT-002) — 2026-05-16

### P3 — Nesting pipeline

12. [x] CLI contract JSON schema in `nesting_engine/README.md`; `NestingJob` + `Nesting::CliRunner` (mock → real) (REQ-FIT-CLI-001) — 2026-05-16
13. [x] Python nest: multi-bin ordered `SheetStock`, ∞ sheets, kerf/margin; outputs `placements.json` + `report.json` + nested DXF (REQ-FIT-NEST-002) — 2026-05-16
14. [x] Map job status `completed` | `partial` | `failed` from report; oversized pieces → orphans in v1 (REQ-FIT-NEST-003) — 2026-05-16
15. [x] Job UX: Turbo Stream progress (%, message, ETA overrun text); 600s cap → partial + notice; cancel (REQ-FIT-JOB-001) — 2026-05-16

### P4 — UX completion (shipped in MVP)

16. [x] Browser preview (SVG/canvas) from `placements.json` (REQ-FIT-UI-002) — 2026-05-16
17. [x] Re-nest: new `NestingRun`, replace downloadable result, history list (REQ-FIT-NEST-004) — 2026-05-16
19. [x] Download nested DXF; project list without login; PIN gate on show; functional UI + `en`/`es` locale files (REQ-FIT-UI-003) — 2026-05-16
21. [x] E2E with golden sample DXF; manual QA checklist; deploy notes (REQ-FIT-QA-001) — 2026-05-16
18. [x] Locale switcher: EN/ES toggle, `LocalesController#update`, `LocaleSwitchable#set_locale`, cookie + session persistence (REQ-FIT-UI-005) — 2026-05-16
20. [x] Architecture-studio web design: IBM Plex, blueprint grid, sidebar/bottom nav, landing, project cards, CAD preview, visual layers (REQ-FIT-UI-004) — 2026-05-16
- [x] Core docs: `DATA_FLOW_MAP.md`, `TESTING_STRATEGY_MATRIX.md`, `SCHEMA_REFERENCE.md` — 2026-05-16
- [x] **libnest2d integration** — `nest_libnest2d` + `python-libnest2d==0.1.3`; DEPLOY native deps; CI `nesting_engine` job (REQ-FIT-NEST-001, REQ-FIT-NEST-002, REQ-FIT-QA-001) — 2026-05-17 — Session: `task_libnest2d-integration.md`
- [x] **Full-sheet libnest2d placement (kerf + obstacles)** — `nest_sheet_with_obstacles`, batch fill in `_place_on_one_sheet`, `_consolidate_sheets` repack, `_inter_sheet_local_search`; invariant tests (REQ-FIT-NEST-002, ADR-0001) — 2026-05-18 — Session: `task_full-sheet-libnest2d-epic.md`

---

## In Progress

_(none)_

---

## Pending (by priority)

### Product / UX

- [ ] **Sheet stock consumption priority** — user can set which `SheetStock` rows the engine consumes first (`sort_order`); default policy: **finite quantities first**, then unlimited (∞) stocks (REQ-FIT-UI-001, REQ-FIT-DOM-001)

### Nesting engine

_(complete)_

### Documentation

_(complete)_

---

## Backlog

### Nesting engine (v1.1+)

_(complete)_

### Product & platform

- [ ] **v1.1 — Auto-split** oversized pieces (REQ-FIT-SPLIT-001) — Depends on: MVP v1 shipped
- [ ] FastAPI wrapper for nesting engine (optional; v1 uses CLI only)
- [ ] Hard limits on file size / piece count (explicitly out of v1 scope today)

<!-- Reference: full decision log and step-level TDD plan in .agenticguild/active_sessions/task_dxf-nesting.md -->
