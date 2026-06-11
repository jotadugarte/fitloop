# Project Roadmap — moduSLoop

moduSLoop is a platform for student tools. Its first tool is fiTLoop (web app for DXF sheet nesting: ephemeral workspace sessions, multi-DXF projects, ordered sheet inventory (finite + ∞), layer filter, Python nesting engine, live progress, nested DXF + preview). Product requirements are locked in `docs/core/SPEC.md`; historical agent session logs live under `.agenticguild/completed_sessions/` (e.g. `task_dxf-nesting_2026-05-17.md`).

**Format:** `[x]` done · `[ ]` pending · `(REQ-ID)` → `docs/core/SPEC.md` · `— YYYY-MM-DD` done · `— Branch: name` in progress · `— Depends on: Item` blocked · **Session:** archived log in `.agenticguild/completed_sessions/` (filename with date suffix)

**Last audit:** 2026-06-11 — **Production Hardening (REQ-FIT-QA-001)**: SSL/TLS Full strict active in Cloudflare, automatic database backups via Coolify to Cloudflare R2, file storage sync via rclone to R2, and weekly Docker system prune cleanup task configured.
**Next action:** Backlog triage / Product feature feedback.

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
| Post-P7b | Billing cart + MEIC UX | **Complete** (PR #18) |
| Post-P7c | ONVO live billing + SINPE pending lock | **Complete** (PR #19) |
| Pre-live | T&C plan checkout, deploy checklist, admin IVA export | **Complete** (T&C and IVA export shipped) |
| Go-live | Production VM + Cloudflare + ONVO live webhook | **Complete** |

**MVP v1 (REQ-FIT-APP-001 through REQ-FIT-QA-001, excluding UI-004/005):** merged to `main` via PR #1 (`exploring-task`, 2026-05-16).

**Auth + billing (REQ-FIT-AUTH-002, REQ-FIT-BILL-001..003):** merged to `main` via PR #11 (`auth-billing`, 2026-05-21).

**Verified in codebase:** Rails 8 app, domain models + migrations, `Workspace` session bind (no PIN), multi-DXF + layers, `nesting_engine/` CLI, `NestingJob` + Turbo progress, preview SVG, re-nest history, golden E2E spec, `docs/DEPLOY.md` + `docs/QA_MANUAL_CHECKLIST.md`, REQ-tagged RSpec + pytest suites; Devise + billing cart (PR #18) + ONVO Payment Intents + webhooks on `main` (`BILLING_GATEWAY=onvo`, ADR-0006, PR #19); SINPE pending workshop lock + pre-retention.

**Not implemented:** optional FastAPI wrapper; hard file/piece caps.

---

## Done

- [x] agentic:guild OS bootstrap (skills, governance docs, PR template) — 2026-05-16
- [x] **moduSLoop Platform Rebrand & Tool Hub** — Rebranded application layouts, titles, Auth views, PWA manifest, and favicons to moduSLoop; designed the home landing page into a multi-tool hub dashboard displaying active (`fiTLoop` DXF nesting) and upcoming (`synCLoop` schedule sync) student tools; added navigation Home icon. — 2026-06-03 — Session: `task_modulusloop-platform.md`
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
- [x] **Términos y condiciones — compra de plan + Eliminar OAuth (FU-LEGAL-001, FU-LEGAL-002, MVP-AUTH-001)** — T&C reales leídos desde Markdown con Redcarpet; versión legal `2026-06-01`; eliminación completa de OmniAuth/OAuth para el MVP — 2026-06-02 — Session: `task_terminos-plan-checkout.md`

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

### Post-P7b — Billing cart + MEIC UX (merged `main`, PR #18)

- [x] **Billing: plan quota before single-download checkout** — block paywall/checkout when monthly plan quota available; overage at 50% when exhausted; `PlanDownloadAvailability.single_download_checkout_allowed?` (REQ-FIT-BILL-002, D33/D34) — 2026-05-27
- [x] **Billing cart UX (single-item) + MEIC pricing display** — DB cart (guest/user), paywall catalog, method-first checkout, MEIC list/SINPE UX, geo defaults, payment snapshots, replace-confirm (REQ-FIT-BILL-001..002) — 2026-05-28 — Session: `task_billing-cart_2026-05-28.md`
- [x] **Workshop: Mi taller panels collapsed by default** — sheet inventory + source DXF detail stay closed on `/taller` (REQ-FIT-UI-003) — 2026-05-28 — Session: `task_mi-taller-panels-collapsed_2026-05-28.md`
- [x] **Auth: sign-in failure UX** — inline alert in form (`auth_flash_alert`), `turbo: false`, password label `auth.session.password` (REQ-FIT-AUTH-002) — 2026-05-27

### Post-P7c — ONVO live billing (merged `main`, PR #19)

- [x] **ONVO payments (live gateway)** — `BILLING_GATEWAY=onvo`; Payment Intents + card form + SINPE cédula/móvil; `POST /webhooks/onvo`; `Billing::FulfillPayment` / `FailPayment`; processing poll + 3DS `/checkout/retorno`; MEIC `CheckoutBreakdown` SSOT; simulate fallback when `BILLING_GATEWAY=simulate` (REQ-FIT-BILL-001, ADR-0006) — 2026-05-30 — Session: `task_onvo-payments_2026-05-30.md`
- [x] **ONVO QA docs** — `docs/QA_MANUAL_CHECKLIST.md` ONVO section; `docs/QA_ONVO_SINPE.md`; DEPLOY ONVO webhook notes (ngrok dev + production VM) — 2026-05-30
- [x] **SINPE pending checkout lock + pre-retention** — 15-min workshop lock (`sinpe_crc` only); manual abandon without `FailPayment`; pre-retain nested DXF at checkout; late webhook fulfill; Mis pagos pending/expired rows; `BlocksWorkshopDuringPendingPayment` (REQ-FIT-BILL-001, REQ-FIT-BILL-003) — 2026-05-30 — Session: `task_onvo-sinpe-pending-lock_2026-05-30.md`

### Hardening, timeouts, and cleanup (this task)

- [x] **Límite de Concurrencia de Anidado** (REQ-FIT-JOB-001) — Created `config/queue.yml` to partition queue workers: limited the CPU-intensive `nesting` queue to exactly 3 concurrent workers (threads: 1, processes: 3) to match physical host i7 CPU cores and prevent starvation of Puma/Postgres. — 2026-06-07 — Session: `task_nesting-resource-hardening.md`
- [x] **Timeout de OS robusto** (REQ-FIT-JOB-001) — Modified `Nesting::CliRunner` and `Nesting::JobRunner` to ensure child process is forcefully killed on thread timeout or cancellation with a TERM-to-KILL signal fallback and post-condition checks. — 2026-06-07 — Session: `task_nesting-resource-hardening.md`
- [x] **Limpieza inmediata de `/tmp`** (REQ-FIT-JOB-001) — Modified `Nesting::JobRunner` to ensure immediate removal of the workspace directory `tmp/nesting_runs/:id/` inside an `ensure` block after file uploads finish. — 2026-06-07 — Session: `task_nesting-resource-hardening.md`
- [x] **Filtrado estricto de logs (Compliance PCI-DSS)** (REQ-FIT-BILL-001) — Configured `filter_parameter_logging.rb` to mask card credentials, CVV, holder names, Sinpe numbers/identifications, and their generic variants in application logs. — 2026-06-07 — Branch: `test-coolifyv` — Session: `task_security-hardening.md`
- [x] **Rate Limiting (Rack::Attack)** (REQ-FIT-AUTH-002, REQ-FIT-BILL-001) — Installed and configured the `rack-attack` gem to throttle authentication and payment endpoints to 5 requests per minute per IP using an environment-agnostic in-memory state store. — 2026-06-07 — Branch: `test-coolifyv` — Session: `task_security-hardening.md`
- [x] **Modo de mantenimiento rápido** (REQ-FIT-QA-001) — Implemented environment-controlled maintenance mode (`MAINTENANCE_MODE=true`) rendering a customized 503 error page with responsive glassmorphism styles, while bypassing health checks, assets, admin users, and Devise login routes. — 2026-06-07 — Branch: `test-coolifyv` — Session: `task_security-hardening.md`
- [x] **Tests de arquitectura para colas de fondo** (REQ-FIT-APP-001) — Validated Solid Queue array config and ApplicationJob class queue routing. — 2026-06-08 — Session: `task_hardening-grupo-1.md`
- [x] **Validación de DXF (Sanitización)** (REQ-FIT-DXF-001) — Implemented DXF upload size (10MB), extension, and SECTION marker validations in controllers and models. — 2026-06-08 — Session: `task_hardening-grupo-1.md`
- [x] **Idempotencia de ONVO Webhooks** (REQ-FIT-BILL-001) — Guarded webhook duplicate fulfillments and concurrent payloads using database pessimistic locking on the payment record. — 2026-06-08 — Session: `task_hardening-grupo-1.md`

### Pre-live polish (branch `merge-setup-into-workshop`)

- [x] **Billing domain types (CbC refactor)** — typed value objects at billing service boundaries (`TierMonths`, `PaymentMethod`, `Money`, `CountryCode`, etc.); no HTTP/JSON shape change (REQ-FIT-BILL-001, ADR-0005) — 2026-05-30 — Session: `task_merge-setup-into-workshop.md`
- [x] **Unified workshop UX — eliminate Parámetros iniciales** — contextual setup/taller modes on single `/taller` show; remove `/projects/new`; autosave láminas, nesting params, DXF layers; preview hidden until first nest (REQ-FIT-UI-001, REQ-FIT-UI-003, REQ-FIT-AUTH-001) — 2026-05-30 — Session: `task_merge-setup-into-workshop.md`
- [x] **Nesting / workshop domain types (CbC refactor)** — `Nesting::*` VOs in `app/models/nesting/`; `JobParameters` + `ConfigBuilder` CLI SSOT; `AssignNestingParameters`; Python `nesting_config.py`; separate `KerfMm`/`MarginMm`; legacy + stable `PieceKey` (REQ-FIT-NEST-002, REQ-FIT-DOM-001, REQ-FIT-CLI-001, REQ-FIT-SPLIT-001, ADR-0001) — 2026-05-30 — Session: `task_nesting-workshop-domain-types-cbc.md` — Branch: `refactor/nesting-workshop-domain-types-cbc`

### Pre-live polish (branch admin-foundation)

- [x] **Admin foundation** — `users.admin`, `FITLOOP_ADMIN_EMAILS`, `Admin::BaseController` (non-admin → 404 on `/admin/*`), `/admin` skeleton dashboard + shared layout for ventas and analytics (REQ-FIT-ADMIN-001) — 2026-05-31 — Session: `task_admin-foundation.md`
- [x] **Admin ventas / reporte de pagos** — `/admin/ventas` con filtros, tablas CRC/USD, declaración Hacienda, export XLSX, `cabys_code` en `payments` (REQ-FIT-ADMIN-001) — 2026-05-31 — Session: `task_admin-sales-report.md` — Branch: `admin-dashboard-pay`
- [x] **Admin Analytics (tarjeta «Estadísticas y Uso»)** — `user_events`, `Analytics::TrackEvent`, instrumentación taller + billing, `GET /admin/analytics` (KPIs, embudo, semáforo `config/analytics.yml`), `GET /admin/usuarios` + timeline, export CSV; gobernanza anti-drift A41 (REQ-FIT-ANALYTICS-001, ADR-0008) — 2026-05-31 — Session: `task_user-analytics-bitacora.md` — Branch: `user-analytics`
- [x] **Declaración de IVA (formato Hacienda)** — `GET /admin/ventas/exportar-formulario-150` (Formulario 150 / IVA01): hojas «Soporte ventas» + «Formulario 150» con fórmulas `SUMIFS`, filtro `paid_at`, mismos filtros que ventas (REQ-FIT-ADMIN-001) — 2026-05-31 — Session: `task_hacienda-iva-declaration.md` — Branch: `declaracion-iva`

### Production VM Go-Live (Coolify + Docker)

- [x] **Production VM deploy** (REQ-FIT-QA-001, ADR-0007) — Configured and deployed on Coolify + Docker on a Linux VPS. Configured PostgreSQL database connections (primary, cache, queue, cable) using direct internal IP connectivity to bypass internal Docker DNS resolution issues. Configured SSL trust behind Cloudflare (`config.assume_ssl = true`) to fix CSRF 422 errors, and routed ActionCable via `solid_cable` adapter (removing Redis runtime requirements). — 2026-06-06
- [x] **Deploy checklist (pre-live)** (REQ-FIT-QA-001) — Hardened `docs/DEPLOY.md` to document webhook bypassing under Cloudflare Zero Trust (path `/webhooks/onvo`). Prefilled email field in Devise confirmation resends, added global notification banners for unconfirmed users, and configured Logger delivery fallback for emails to prevent registration crashes when SMTP is absent. — 2026-06-06
- [x] **Habilitar RSpec en CI** (REQ-FIT-QA-001) — Configured GitHub Actions in `ci.yml` to spin up a PostgreSQL test service and run the full RSpec suite (unit, controllers, request, system/E2E specs) on every PR and push. — 2026-06-07 — Branch: `refactor/test-coverage-100`
- [x] **Enforcement de cobertura al 100%** (REQ-FIT-QA-001) — Integrated SimpleCov in the RSpec suite, set strict line (100.0%) and branch (100.0%) coverage minimums, and fixed all uncovered paths in controllers, models, and services. — 2026-06-07 — Branch: `refactor/test-coverage-100`
- [x] **Script de desarrollo con Solid Queue local** (REQ-FIT-QA-001) — Configured `bin/dev` to run with Solid Queue and Puma integrated supervisor using the `--solid` flag or `USE_SOLID_QUEUE=true` environment variable, aligning development environment closely with production/Coolify background queue adapter. — 2026-06-07 — Branch: `test-coolifyv` — Session: `task_local-solid-queue-development.md`
- [x] **Certificado SSL/TLS (conexión encriptada)** (REQ-FIT-QA-001) — Cloudflare Dashboard cambiado de Full a Full (strict). Cloudflare Tunnel garantiza cifrado end-to-end sin certificado de origen adicional. — 2026-06-10
- [x] **Respaldos de base de datos (Backups)** — Programadas tareas de backup diario de PostgreSQL en Coolify con destino a Cloudflare R2 (`modusloop-backups`) y retención de 30 días. — 2026-06-10
- [x] **Limpieza automática de Docker (Disk Purge)** — Configurada tarea cron en el host (`server-zelda`) para ejecutar `docker system prune -f` semanalmente (miércoles a las 11:00 AM) y evitar llenado de disco. — 2026-06-10

### Monitoreo & feedback (branch `monitoring-feedback`)

- [x] **Botón de sugerencias (Feedback)** — FAB + dialog, persistencia en DB, notificaciones email/Discord, panel admin `/admin/feedbacks`, mejoras UI hub/paywall/preview pan-zoom; fix formularios anidados en dialog (REQ-FIT-OPS-001) — 2026-06-09 — Session: `task_monitoring-feedback.md` — Branch: `monitoring-feedback`
- [x] **Honeybadger (integración código)** — gem + initializer activo solo con `HONEYBADGER_API_KEY` (REQ-FIT-OPS-001) — 2026-06-09 — Branch: `monitoring-feedback`
- [x] **Verificación post-deploy feedback (Coolify dev)** — `dev.modusloop.com`: `SMTP_*`, `DISCORD_WEBHOOK_URL`, `DISCORD_INVITE_URL`, `FEEDBACK_NOTIFY_EMAIL` en env Coolify; smoke test FAB → flash → fila en `/admin/feedbacks` → email a `soporte@modusloop.com` + embed Discord (REQ-FIT-OPS-001) — 2026-06-09 — Session: `task_monitoring-feedback.md`
- [x] **Verificación post-deploy feedback (Coolify prod)** — `modusloop.com`: mismas env vars en Production; smoke test FAB → DB → email + Discord confirmado (REQ-FIT-OPS-001) — 2026-06-09 — Session: `task_monitoring-feedback.md`
- [x] **Variables SMTP en Coolify (prod)** — Credenciales Brevo en Production verificadas vía smoke test de feedback (email a `soporte@modusloop.com`) — 2026-06-09
- [x] **Honeybadger operativo (Coolify prod)** — Proyecto Honeybadger + `HONEYBADGER_API_KEY` solo en Production; smoke test con `Honeybadger.notify` verificado en dashboard — 2026-06-10
- [x] **Monitoreo de caídas (Uptime)** — Configurado monitor externo en Better Stack SaaS en `https://modusloop.com/up` con alertas por correo electrónico verificadas — 2026-06-10
- [x] **Alertas de métricas del servidor (Home Ops)** — Instalado Netdata Agent en el host (`server-zelda`) y configuradas alertas centralizadas a Discord vía Netdata Cloud — 2026-06-10
- [x] **Enrutamiento de correos en Cloudflare** — Configuradas reglas de redirección para `soporte@`, `facturacion@` y `admin@modusloop.com` hacia Gmail; verificado recibo de email de prueba en bandeja. — 2026-06-10 — Session: `task_email-discord-setup.md`
- [x] **DNS SPF/DKIM/DMARC para Brevo** — Añadidos registros TXT en Cloudflare DNS para legitimar envío de correos transaccionales desde `modusloop.com` vía Brevo; verificado end-to-end con smoke test de feedback. — 2026-06-10 — Session: `task_email-discord-setup.md`

---

## In Progress

_(none)_

---

## Pending (by priority)

### 1. Pruebas, Calidad & Cobertura (CI/CD)

_(none)_

### 2. Estabilidad, Seguridad & Hardening (Código)

_(none)_

### 3. Monitoreo & Feedback del Usuario (Operaciones)

_(none)_

### 4. Configuración de Producción & DevOps (Fuera de código)

_(none)_

### 5. Resiliencia del Entorno Casero (Home Ops)

_(none)_

---

## Backlog

### Nesting engine (v1.1+)

_(no pending engine items)_

### Product & platform (deferred)

- [ ] **Analytics archive (cold storage)** — `analytics_archive`, retención 6 meses hot + job de copia/purga (fuera de Analytics v1)
- [ ] **Analytics operational alerts** — email/Slack cuando conversión o fallos de pago salgan de umbral (hoy solo semáforo en `/admin/analytics`)
- [ ] **External BI** (Metabase u otro) — opcional; conectar a `user_events` o réplica read-only
- [ ] Hard limits on file size / piece count (explicitly out of v1 scope today)

<!-- Reference: archived decision log in .agenticguild/completed_sessions/task_dxf-nesting_2026-05-17.md -->
