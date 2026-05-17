# Project Roadmap — Fitloop

Web app for DXF sheet nesting: multi-DXF projects, ordered sheet inventory (finite + ∞), layer filter, PIN access, Python nesting engine, live progress, nested DXF + preview. Product spec is locked in `.agenticguild/active_sessions/task_dxf-nesting.md`.

**Format:** `[x]` done · `[ ]` pending · `(REQ-ID)` → `docs/core/SPEC.md` · `— YYYY-MM-DD` done · `— Branch: name` in progress · `— Depends on: Item` blocked

**Next action:** Run `start-task` on **P2 — DXF inputs** (step 9: multi-DXF upload + layer checklist).

---

## Done

- [x] agentic:guild OS bootstrap (skills, governance docs, PR template) — 2026-05-16
- [x] Fitloop DXF nesting — requirements exploration & spec lock (decisions D1–D27, implementation plan P0–P5) — 2026-05-16 — Session: `task_dxf-nesting.md`
- [x] **P0 — Anchors & toolchain** (items 1–5) — 2026-05-16
- [x] **P1 — Domain & access** (items 6–8) — 2026-05-16

### P0 — Anchors & toolchain (complete)

1. [x] Lock stack in `docs/core/SYSTEM_ARCHITECTURE.md` (REQ-FIT-ARCH-001) — 2026-05-16
2. [x] Populate `docs/core/SPEC.md` (REQ-FIT-SPEC-001) — 2026-05-16
3. [x] Scaffold Rails 8 app + Fitloop home (REQ-FIT-APP-001) — 2026-05-16
4. [x] `nesting_engine/` extract + pytest (REQ-FIT-EXT-001) — 2026-05-16
5. [x] Nesting library spike + ADR-0001 (REQ-FIT-NEST-001) — 2026-05-16

### P1 — Domain & access (complete)

6. [x] Models: `Project`, `SheetStock`, `ProjectLayer`, `NestingRun` (REQ-FIT-DOM-001) — 2026-05-16
7. [x] PIN access + `ProjectAccess` (REQ-FIT-AUTH-001) — 2026-05-16
8. [x] Project CRUD + ordered `SheetStock` UI (REQ-FIT-UI-001) — 2026-05-16

## In Progress

- [ ] **Fitloop MVP v1 — DXF sheet nesting** — Branch: `exploring-task` — Session: `task_dxf-nesting.md` — **P2 — DXF inputs & validation** (steps 9–11)

## Pending (by priority)

### P2 — DXF inputs & validation *(start here)*

9. [x] Multi-DXF upload (Active Storage); union layer names; layer checklist UI (i18n) (REQ-FIT-DXF-001) — 2026-05-16
10. [x] Pre-flight: reject zero layers selected / zero extractable pieces (i18n) via `ProjectReadinessValidator` (REQ-FIT-VAL-001) — 2026-05-16
11. [ ] Python extractor: INSERT on layer (no explode), nested blocks depth ≤8, tessellation tolerance; warnings in report (REQ-FIT-EXT-002) — Depends on: Pre-flight

### P3 — Nesting pipeline

12. [ ] CLI contract JSON schema in `nesting_engine/README.md`; `NestingJob` + `Nesting::CliRunner` (mock → real) (REQ-FIT-CLI-001) — Depends on: Extractor
13. [ ] Python nest: multi-bin ordered `SheetStock`, ∞ sheets, kerf/margin; outputs `placements.json` + `report.json` + nested DXF (REQ-FIT-NEST-002) — Depends on: CLI bridge
14. [ ] Map job status `completed` | `partial` | `failed` from report; oversized pieces → orphans in v1 (REQ-FIT-NEST-003) — Depends on: Real CLI integration
15. [ ] Job UX: Turbo Stream progress (%, message, ETA overrun text); 600s cap → partial + notice; cancel (REQ-FIT-JOB-001) — Depends on: Status mapping

### P4 — UX completion & ship

16. [ ] Browser preview (SVG/canvas) from `placements.json` (REQ-FIT-UI-002) — Depends on: Nesting pipeline
17. [ ] Re-nest: new `NestingRun`, replace downloadable result, history list (REQ-FIT-NEST-004) — Depends on: Preview
18. [ ] **Locale switcher** (REQ-FIT-UI-005) — Depends on: Rails scaffold
19. [ ] Download nested DXF; project list without login; PIN gate on show; Fitloop UI polish (`en`/`es`) (REQ-FIT-UI-003) — Depends on: Re-nest
20. [ ] **Architecture-studio web design** (REQ-FIT-UI-004) — Depends on: Locale switcher
21. [ ] E2E with golden sample DXF; manual QA checklist; deploy notes (REQ-FIT-QA-001) — Depends on: UI polish + architecture-studio design

### Documentation (parallel)

- [ ] Enrich `docs/core/DATA_FLOW_MAP.md` — Depends on: SPEC populated
- [ ] Enrich `docs/core/TESTING_STRATEGY_MATRIX.md` — Depends on: SPEC populated
- [ ] Add `docs/core/SCHEMA_REFERENCE.md` when first migrations land — Depends on: Models (P1 step 6)

## Backlog

- [ ] **v1.1 — Auto-split** oversized pieces (REQ-FIT-SPLIT-001) — Depends on: MVP v1 shipped
- [ ] FastAPI wrapper for nesting engine (optional; v1 uses CLI only)
- [ ] Additional locales beyond `en` / `es`
- [ ] Hard limits on file size / piece count (explicitly out of v1 scope today)
- [ ] PIN recovery flow for users (out of scope v1)

<!-- Reference: full decision log and step-level TDD plan in .agenticguild/active_sessions/task_dxf-nesting.md -->
