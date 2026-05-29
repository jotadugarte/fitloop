# Project Roadmap — Fitloop

Web app for DXF sheet nesting: ephemeral workspace sessions, multi-DXF projects, ordered sheet inventory (finite + ∞), layer filter, Python nesting engine, live progress, nested DXF + preview. Product requirements are locked in `docs/core/SPEC.md`; historical agent session logs live under `.agenticguild/completed_sessions/` (e.g. `task_dxf-nesting_2026-05-17.md`).

**Format:** `[x]` done · `[ ]` pending · `(REQ-ID)` → `docs/core/SPEC.md` · `— YYYY-MM-DD` done · `— Branch: name` in progress · `— Depends on: Item` blocked · **Session:** archived log in `.agenticguild/completed_sessions/` (filename with date suffix)

**Last audit:** 2026-05-28 — **ONVO live billing** implemented on branch `feat/onvo-payments` (ADR-0006, webhooks, SDK checkout, SINPE, processing poll). **Billing cart + MEIC UX** on `add-cart` (pending merge). P6/P7 on `main` (PR #11).

**Next action:** Merge `add-cart` then `feat/onvo-payments`; **Northflank** staging for ONVO webhooks (`BILLING_GATEWAY=onvo`); **Admin ventas**; **user analytics & admin bitácora**.

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
| P5 / Backlog | v1.1+ | **Complete** (auto-split + composite v1.2 shipped) |
| P6 | User accounts (auth) | **Complete** (PR #11) |
| P7 | Simulated billing | **Complete** (PR #11) |
| Post-P7 | UI / billing / auth polish on `main` | **Complete** (see Done) |
| Post-P7b | Billing cart + MEIC UX | **Complete** on branch `add-cart` (pending merge) |
| Post-P7c | ONVO live billing | **Complete** on branch `feat/onvo-payments` (pending merge) |

**MVP v1 (REQ-FIT-APP-001 through REQ-FIT-QA-001, excluding UI-004/005):** merged to `main` via PR #1 (`exploring-task`, 2026-05-16).

**Auth + billing (REQ-FIT-AUTH-002, REQ-FIT-BILL-001..003):** merged to `main` via PR #11 (`auth-billing`, 2026-05-21).

**Verified in codebase:** Rails 8 app, domain models + migrations, `Workspace` session bind (no PIN), multi-DXF + layers, `nesting_engine/` CLI, `NestingJob` + Turbo progress, preview SVG, re-nest history, golden E2E spec, `docs/DEPLOY.md` + `docs/QA_MANUAL_CHECKLIST.md`, REQ-tagged RSpec + pytest suites; Devise + simulated billing; workshop at `/taller`; paywall + plans + Mis pagos; **ONVO** Payment Intents + webhooks on `feat/onvo-payments` (`BILLING_GATEWAY=onvo`, ADR-0006).

**Not implemented:** optional FastAPI wrapper; hard file/piece caps; **ONVO on `main`** until `feat/onvo-payments` merges; Northflank staging + full Docker nesting E2E (follow-up).

---

## Done

- [x] agentic:guild OS bootstrap (skills, governance docs, PR template) — 2026-05-16
- [x] Fitloop DXF nesting — requirements exploration & spec lock (decisions D1–D27, implementation plan P0–P5) — 2026-05-16 — Session: `task_dxf-nesting_2026-05-17.md`
- [x] **P0 — Anchors & toolchain** (items 1–5) — 2026-05-16
- [x] **P1 — Domain & access** (items 6–8) — 2026-05-16
- [x] **P2 — DXF inputs & validation** (items 9–11) — 2026-05-16
- [x] **P3 — Nesting pipeline** (items 12–15) — 2026-05-16
- [x] **Fitloop MVP v1 — core product** (P4 items 16–17, 19, 21; merged PR #1) — 2026-05-16 — Session: `task_dxf-nesting_2026-05-17.md`

### P0 — Anchors & toolchain

1. [x] Lock stack in `docs/core/SYSTEM_ARCHITECTURE.md` (REQ-FIT-ARCH-001) — 2026-05-16
2. [x] Populate `docs/core/SPEC.md` (REQ-FIT-SPEC-001) — 2026-05-16
3. [x] Scaffold Rails 8 app + Fitloop home (REQ-FIT-APP-001) — 2026-05-16
4. [x] `nesting_engine/` extract + pytest (REQ-FIT-EXT-001) — 2026-05-16
5. [x] Nesting library spike + ADR-0001 (REQ-FIT-NEST-001) — 2026-05-16

### P1 — Domain & access

6. [x] Models: `Project`, `SheetStock`, `ProjectLayer`, `NestingRun` (REQ-FIT-DOM-001) — 2026-05-16
7. [x] Ephemeral workspace session access (`Workspace`, REQ-FIT-AUTH-001; ADR-0004 supersedes PIN) — 2026-05-19
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
19. [x] Download nested DXF; workspace start redirect (no saved-project list); session-bound show; functional UI + `en`/`es` locale files (REQ-FIT-UI-003) — 2026-05-16 (access model updated 2026-05-19, ADR-0004)
21. [x] E2E with golden sample DXF; manual QA checklist; deploy notes (REQ-FIT-QA-001) — 2026-05-16
18. [x] Locale switcher: EN/ES toggle, `LocalesController#update`, `LocaleSwitchable#set_locale`, cookie + session persistence (REQ-FIT-UI-005) — 2026-05-16
- [x] **Modo Arquitecto en Pánico** (`:es_panic`) — joke locale YAML, 2+1 switcher (📐 PÁNICO), key parity + request/i18n specs (REQ-FIT-UI-005) — 2026-05-19 — Session: `task_es-panic-locale_2026-05-20.md`
20. [x] Architecture-studio web design: IBM Plex, blueprint grid, sidebar/bottom nav, landing, project cards, CAD preview, visual layers (REQ-FIT-UI-004) — 2026-05-16
- [x] Core docs: `DATA_FLOW_MAP.md`, `TESTING_STRATEGY_MATRIX.md`, `SCHEMA_REFERENCE.md` — 2026-05-16
- [x] **libnest2d integration** — `nest_libnest2d` + `python-libnest2d==0.1.3`; DEPLOY native deps; CI `nesting_engine` job (REQ-FIT-NEST-001, REQ-FIT-NEST-002, REQ-FIT-QA-001) — 2026-05-17 — Session: `task_libnest2d-integration_2026-05-17.md`
- [x] **Full-sheet libnest2d placement (kerf + obstacles)** — `nest_sheet_with_obstacles`, batch fill in `_place_on_one_sheet`, `_consolidate_sheets` repack, `_inter_sheet_local_search`; invariant tests (REQ-FIT-NEST-002, ADR-0001) — 2026-05-18 — Session: `task_full-sheet-libnest2d-epic_2026-05-18.md`
- [x] **Intra-sheet repack (void closure)** — `_intra_sheet_repack_search` (×2 post-fill/post-consolidate), `score_sheet_layout` / `_layout_better_than`, opportunistic pull from later sheets; peluo DXF fixture + `@pytest.mark.slow` (REQ-FIT-NEST-002, ADR-0001) — 2026-05-17 — Session: `task_intra-sheet-repack_2026-05-17.md`
- [x] **v1.1 — Auto-split** — opt-in orphan resolution (`OrphanResolution`, `SplitProposal`, `DerivedPiece`), `split_planner.py`, `plan_splits` CLI, ephemeral UI, manual CAD path, nest-with-updated-pieces CTA, `split_not_feasible`, cancel/sheet invalidation (REQ-FIT-SPLIT-001, ADR-0002) — 2026-05-19 — Session: `task_v11-auto-split_2026-05-20.md`
- [x] **v1.2 — Composite DXF layers (core)** — `layer_role` primary/auxiliary per file, `composite_extract`, clipped aux in preview, layer-preserved `nested.dxf`, primary-only piece count (REQ-FIT-DXF-002, ADR-0003) — 2026-05-18 — Session: `task_composite-dxf-layers_2026-05-20.md`
- [x] **v1.2 — Composite + auto-split** — `partition_decorations`, `decorations_json` on `DerivedPiece`, composite `plan_splits` preview, nest derived children with aux layers (REQ-FIT-DXF-002, REQ-FIT-SPLIT-001) — 2026-05-18 — Session: `task_composite-dxf-layers_2026-05-20.md`
- [x] **Remove PIN / saved-project access** — drop `pin_digest`, `ProjectAccess` / gate UI, ephemeral-only `Workspace.resolve!`; docs + ADR-0004 (REQ-FIT-AUTH-001) — 2026-05-19 — Session: `task_remove-pin_2026-05-20.md`
- [x] **Sheet stock consumption priority** — Priority column, drag reorder, finite-first button, ∞ auto-last, max one ∞ per project; server + CLI + engine alignment (REQ-FIT-UI-001, REQ-FIT-DOM-001, REQ-FIT-NEST-002) — 2026-05-17 — Session: `task_sheet-stock-consumption-priority_2026-05-18.md`
- [x] **Nesting progress / status bar UX** — CLI `progress.json`, phased labels (queued → preparing → starting → engine phases → writing outputs), live percent via `CliRunner` poll, cancel + time remaining in progress panel, `en`/`es` copy (REQ-FIT-JOB-001) — 2026-05-20 — Session: `task_nesting-progress-ux_2026-05-20.md`
- [x] **P6 — User accounts (auth)** — Devise + OmniAuth; email verification; merge opt-in; Spanish routes; workspace re-bind on login (REQ-FIT-AUTH-002, ADR-0005) — 2026-05-21 — Session: `task_auth-billing_2026-05-21.md`
- [x] **P7 — Simulated billing** — paywall nested DXF; `config/billing.yml`; plans 1/2/4m; grants + 24h retention; `/mis-pagos` (REQ-FIT-BILL-001..003, ADR-0005) — 2026-05-21 — Session: `task_auth-billing_2026-05-21.md`

### Post-P7 polish (merged `main`, after PR #11)

- [x] **Workshop URL `/taller`** — session/tab-bound workshop; legacy `/projects/:id` redirects; Mi taller helpers (REQ-FIT-UI-003) — 2026-05-21
- [x] **Toolbar + Mi taller** — locale switcher left, account actions right, tab-bound workshop shortcut (REQ-FIT-UI-003) — 2026-05-21
- [x] **Workspace stale binds + resume** — discard orphaned session binds; return to workshop after profile edit; smart Mi taller across tabs (REQ-FIT-AUTH-001) — 2026-05-21
- [x] **Workspace tab TTL** — tab-closure cookie only after real browser close (>120 s); in-app navigation no longer expires workshop (REQ-FIT-AUTH-001) — 2026-05-21
- [x] **Locale switcher: preserve setup drafts** — `PersistWorkspaceSheetInventoryDraft` + `PersistWorkspaceLayerSelectionDraft` on locale PATCH; Turbo off on switcher (REQ-FIT-UI-005, REQ-FIT-UI-001) — 2026-05-21
- [x] **Nesting progress i18n on locale change** — resolve terminal progress copy in active locale, not stored translated string (REQ-FIT-JOB-001, REQ-FIT-UI-005) — 2026-05-21
- [x] **Billing: plan dates in user time zone** — `PlanPeriod` end-of-day in `users.time_zone`; `l_in_user_zone` on Mis pagos / Planes (REQ-FIT-BILL-002, D29) — 2026-05-21
- [x] **Billing: Mis pagos active plan detail** — tier duration (1/2/4 months), period bounds, monthly vs contract quota copy (REQ-FIT-BILL-002, D38) — 2026-05-21
- [x] **Auth: resend confirmation email prefill** — signed-in user email on `/confirmacion` (REQ-FIT-AUTH-002) — 2026-05-21
- [x] **i18n: long date/time for plan expiry** — `es.time.formats.long` for Mis pagos (REQ-FIT-UI-005) — 2026-05-21

### Post-P7 polish (local on `main`, uncommitted)

- [x] **Billing: plan quota before single-download checkout** — block paywall/checkout when monthly plan quota available; overage at 50% when exhausted; `PlanDownloadAvailability.single_download_checkout_allowed?` (REQ-FIT-BILL-002, D33/D34) — 2026-05-27
- [x] **Billing cart UX (single-item) + MEIC pricing display** — DB cart (guest/user), paywall catalog, method-first checkout, MEIC list/SINPE UX, geo defaults, payment snapshots, replace-confirm (REQ-FIT-BILL-001..002) — 2026-05-28 — Branch: `add-cart` — Session: `task_billing-cart.md`
- [x] **Workshop: Mi taller panels collapsed by default** — sheet inventory + source DXF detail stay closed on `/taller` (REQ-FIT-UI-003) — 2026-05-28 — Branch: `add-cart` (mixed scope, D30)
- [x] **Auth: sign-in failure UX** — inline alert in form (`auth_flash_alert`), `turbo: false`, password label `auth.session.password` (REQ-FIT-AUTH-002) — 2026-05-27

### Post-P7c — ONVO live billing (branch `feat/onvo-payments`, pending merge)

- [x] **ONVO payments (live gateway)** — `BILLING_GATEWAY=onvo`; Payment Intents + embedded SDK; SINPE cédula/móvil; `POST /webhooks/onvo`; `Billing::FulfillPayment` / `FailPayment`; processing poll + 3DS `/checkout/retorno`; MEIC `CheckoutBreakdown` SSOT; simulate fallback when `BILLING_GATEWAY=simulate` (REQ-FIT-BILL-001, ADR-0006) — 2026-05-28 — Branch: `feat/onvo-payments` — Session: `task_onvo-payments.md`
- [x] **ONVO QA docs** — `docs/QA_MANUAL_CHECKLIST.md` ONVO section; `docs/QA_ONVO_SINPE.md`; DEPLOY ngrok webhook notes — 2026-05-28 — Branch: `feat/onvo-payments`

---

## In Progress

_(none)_

---

## Pending (by priority)

### Product / UX

_(none)_

### Nesting engine

_(no pending engine items)_

---

## Backlog

### Nesting engine (v1.1+)

### Product & platform

- [ ] **User analytics & admin bitácora** — `admin` role, `/admin/analytics`, event timeline, KPIs (downloads, plans, orphans, funnel); no DXF/geometry persistence; 6-month retention — Depends on: P6/P7 merged — Session: `task_user-analytics_2026-05-21.md` (discovery archived in `.agenticguild/completed_sessions/`)
- [ ] **Admin ventas / reporte de pagos** — UI admin sobre snapshots en `payments` (comprador, producto, lista, descuento SINPE/overage, subtotal, IVA, total; exitosos y fallidos); export CSV opcional — Depends on: **Billing cart merged** (snapshot columns shipped on `add-cart`) — Session: `task_billing-cart.md`
- [ ] **Northflank staging — ONVO webhooks** — deploy Rails with fixed HTTPS URL; register `POST /webhooks/onvo` in ONVO test dashboard; `BILLING_GATEWAY=onvo`, `ONVO_*` ENV — Depends on: **`feat/onvo-payments` merged** — Scope v1: billing + webhooks + checkout only (no real nesting in container) — Session: `task_onvo-payments.md`
- [ ] **Northflank / Docker — full nesting E2E** — add `nesting_engine` + Python venv to image/worker; DXF upload → nest → pay → download on staging — Depends on: **Northflank staging (ONVO)** — Follow-up from ONVO epic (D-ONVO-13)
- [ ] **Billing domain types (CbC refactor)** — replace raw `Integer`/`String` + loose enums in `app/services/billing/` with value objects (`TierMonths`, `PaymentMethod`, `Money`, etc.) per `deterministic_coding_standards.md`; update ADR-0005 + SPEC if public shapes change — Depends on: **ONVO merged to `main`** — Also noted in `.agenticguild/pending_refactors.md`
- [ ] FastAPI wrapper for nesting engine (optional; v1 uses CLI only)
- [ ] Hard limits on file size / piece count (explicitly out of v1 scope today)

<!-- Reference: archived decision log in .agenticguild/completed_sessions/task_dxf-nesting_2026-05-17.md -->
