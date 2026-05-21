# Task: User analytics & admin bitácora — discovery

**Created:** 2026-05-20  
**Status:** Spec locked — handoff to `start-task` (2026-05-20)  
**Depends on:** `task_auth-billing.md` — Fase A `User` + `users.admin` hook; Fase B billing tables for monetization KPIs (instrument billing events when P7 steps land)  
**Owner intent:** Bitácora y dashboard **solo para administradores internos**. Nunca visible al usuario final. Telemetría de negocio y operaciones sin guardar DXF/geometría/preview.

---

## Agreed (from user, 2026-05-20)

| # | Decision |
|---|----------|
| A1 | **Audiencia:** solo admins internos; el usuario final **nunca** ve la bitácora. |
| A2 | **Acceso admin:** rol `admin` en la app (crear — no existe hoy); UI en `/admin/analytics` (+ subrutas TBD). No depender de consola/SQL para el día a día. |
| A3 | **Single-tenant v1:** un solo operador Fitloop (no “empresas cliente” aisladas en la misma DB). |
| A4 | **Anónimos:** eventos con `session_id` + `tab_id`; al login/registro **fusionar** trazas al `user_id`. |
| A5 | **Auth/billing:** eventos de cuenta y cobro entran en la bitácora cuando existan modelos (misma épica de producto, **sesión de tarea separada**). |
| A6 | **Suspendido:** no puede entrar al sistema (`suspended_at`); no genera sesión nueva (gate en login). |
| A7 | **Alcance eventos:** todo lo **razonable** — acciones de proyecto (agregar/quitar DXF, láminas, capas, nest, cancel, re-nest como evento **separado**), resultados (piezas, láminas usadas, huérfanos + razones agregadas), auto-split, billing completo, registro/login/logout/verificación/borrado cuenta. **No** cada micro-interacción del taller. |
| A8 | **Metadata archivo:** guardar **toda** metadata útil del upload (tamaño, tipo, capas elegidas, composite roles, conteos extract) — **sin** blob ni geometría. **Sí** nombre de archivo original. |
| A9 | **Jobs:** registrar duración de cada `NestingJob` / split job; correlacionar con metadata del run para análisis de lentitud. |
| A10 | **Prohibido persistir:** DXF, preview SVG, geometría, rutas absolutas del cliente. |
| A11 | **PII técnica:** guardar **IP**, **user-agent**, **país** (derivado de IP o header). |
| A12 | **Retención:** **6 meses** en DB “caliente”; cada 6 meses **archivar** a repositorio aparte (cold storage consultable). |
| A13 | **Borrar cuenta:** se borra/anonymiza la cuenta de usuario; la **bitácora histórica de esa cuenta se conserva** (admin sigue viendo timeline por ex-`user_id` o clave estable). |
| A14 | **Dashboard:** KPIs **casi tiempo real** + reportes **diarios/semanales**. |
| A15 | **KPIs v1:** descargas de pago (suelta vs plan), planes activos/vendidos por tier, usuarios con plan 1m que **agotaron** cupo mensual, huérfanos por proyecto/run, embudo empezar→…→descarga. |
| A16 | **Filtros:** rango fechas, locale (`en`/`es`), método de pago, moneda (USD/CRC). |
| A17 | **Export:** CSV para contabilidad/marketing. |
| A18 | **Proyecto efímero destruido:** bitácora **conserva** snapshot de metadata del proyecto y todos los eventos ya emitidos (`project_id`, `nesting_run_id` históricos). |
| A19 | **Fuente de verdad billing:** `Payment`, `Subscription`, `DownloadGrant` son **sistema de registro**; bitácora **también** emite eventos (`download_completed`, etc.) para timeline y embudo — KPIs hacen **JOIN** a tablas de billing donde aplique, no duplicar montos en JSON suelto. |
| A20 | **Retención 24h DXF (D54):** no es un “evento de retención”; registrar **`download_completed`** (y opcional `download_from_mis_pagos`) con timestamp — admin ve si descargó **antes** de que expire el blob. |
| A21 | **UI admin:** `/admin/analytics`; listado usuarios con búsqueda email/nombre; **drill-down** = timeline cronológico de eventos de un usuario. |
| A22 | **Alertas** (email/Slack si conversión cae / fallos suben): **post-v1** (follow-up). |
| A23 | **Faseamiento vs auth-billing:** ver sección *Phasing* — recomendación: **en paralelo** tras Fase A (User existe) o **justo después** de modelos billing; eventos de billing se activan cuando existan controllers. |
| A24 | **v1 UX:** eventos + contadores + **gráficos** (no solo tablas). |
| A25 | **Abuso:** detección de bots (patrones en dashboard); rate limit en escritura (A32). **v1:** flag “sospechoso” + revisión manual; sin auto-suspender por bot. |
| A26 | **Modelo datos:** tabla única `user_events` + `properties` jsonb por `event_type`. |
| A27 | **Ingesta:** eventos **no críticos** → job async (Solid Queue); **críticos** → sync en request (nest terminal, pago, descarga, registro, borrado cuenta) para no perder si el proceso muere. |
| A28 | **Idempotencia:** misma acción dos veces = **una** fila (`idempotency_key` único; ej. `download_completed` + `nesting_run_id` + `user_id`). |
| A29 | **Bitácora ≠ fuente de verdad:** solo **consulta** / timeline / embudo; montos, planes y cupos vienen de tablas billing. |
| A30 | **Umbrales UI (semáforo en pantalla):** sin email/Slack v1; en el dashboard, tarjetas/números/gráficos pasan a estilo **alerta (rojo)** cuando la métrica sale de un rango “sano” definido en `config/analytics.yml` (ej. conversión &lt; 15 %, fallos de pago &gt; 20 %, duración p95 nest &gt; 10 min). Es **solo visual** para que el admin note el problema al abrir la página — no envía notificaciones. |
| A40 | **Gráficos v1:** estética **llamativa** (no tablas secas ni gráficos grises por defecto); barras/líneas/donas con color, animación suave al cargar, tipografía clara. **Propuesta técnica:** Chart.js v4 vía importmap + tema Fitloop (azul blueprint / acento coral en alertas); KPI cards grandes con icono. Chartkick solo si no alcanza el look — priorizar control visual. |
| A31 | **Faseamiento:** **en paralelo** con auth-billing (User Fase A → admin + eventos taller; Fase B billing → eventos + KPIs pago). |
| A32 | **Rate limit:** solo eventos **low_priority**; máx **300/hora** por `anonymous_session_key` o `user_id`; **exentos:** nest/split terminal, billing, auth, `download_completed`. Implementación: `Analytics::TrackEvent` rechaza o muestrea con log. |
| A33 | **Archivo frío:** segunda base **PostgreSQL** solo lectura (`analytics_archive`); job trimestral/mensual copia filas >6 meses y purga de hot DB tras copia exitosa. |
| A34 | **Primer admin:** email fijo del operador vía **`ENV["FITLOOP_ADMIN_EMAIL"]`** (o lista); seed/promoción al crear ese usuario; único operador plataforma. |
| A35 | **País:** **MaxMind GeoLite2** local (`maxminddb` o `geocoder` + DB en repo/CI); fallback header **`CF-IPCountry`** si existe; si falla → `country_code` null. Sin API paga por request en v1. |
| A36 | **Admin role v1:** `users.admin` boolean; `Admin::BaseController` exige admin; no-admin → **404** en `/admin/*`. |
| A37 | **Embudo v1:** `workspace_started` → `first_dxf_uploaded` → `nest_completed` → `paywall_viewed` → `payment_succeeded` → `download_completed`. |
| A38 | **Borrar cuenta:** usuario ve cuenta borrada; **solo admin** ve identidad histórica (email/nombre en evento `account_deleted` + timeline; cuenta activa anonimizada). |
| A39 | **Drill-down:** listado usuarios + timeline cronológico por usuario (UX amigable para consulta). |

---

## Phasing (locked)

**En paralelo con auth-billing (A31):**

1. Tras migración `User`: `users.admin`, `FITLOOP_ADMIN_EMAIL`, `/admin` skeleton.
2. `user_events` + trackers de taller (upload, nest, split) — pueden usar `anonymous_session_key` antes de login.
3. Cuando mergee billing: instrumentar paywall, checkout, `download_completed`; KPIs monetarios desde tablas billing.
4. Archive DB + job cuando volumen lo justifique (puede ser sub-paso post-MVP admin si hace falta).

---

## Open questions (remaining)

### Legal (non-blocking)
- [ ] FU-LEGAL-003: privacidad debe citar IP/UA/país, retención 6m + archivo Postgres frío, acceso solo admin.

---

## Domain Model (draft)

### UserEvent
- **Responsibility:** Append-only fact log for **admin consultation only** (A29); not billing source of truth.
- **Invariants:** no blob columns; `occurred_at` UTC; `user_id` nullable until linked; `anonymous_session_key` stable pre-login; `idempotency_key` unique when present (A28); after 6 months hot → copy to archive DB then delete from hot (A33).
- **Fields (conceptual):** `event_type`, `priority` (`critical`|`low`), `properties` jsonb, `user_id`, `anonymous_session_key`, `tab_id`, `project_id`, `nesting_run_id`, `ip`, `user_agent`, `country_code`, `locale`, `idempotency_key`.
- **Value objects:** `EventType`, `AnonymousSessionKey`, `CountryCode`, `EventProperties`, `IdempotencyKey`.

### Analytics::TrackEvent (service)
- **Responsibility:** Single entry for recording; enforces idempotency, rate limit (A32), priority → sync vs `TrackEventJob`.
- **Invariants:** critical events never dropped by rate limit; duplicate `idempotency_key` → no-op success.

### ProjectSnapshot (or embedded in first/last project event)
- **Responsibility:** Preserve project metadata after `Project` destroyed.
- **Invariants:** created on `project_discarded` or last event; no geometry; includes sheet stock summary, layer config, kerf/margin settings.

### Admin (users.admin)
- **Responsibility:** Gate `/admin/*` (A36).
- **Invariants:** `FITLOOP_ADMIN_EMAIL` promoted on create/find; non-admin 404; at least one admin in prod.

### AnalyticsArchive (second PostgreSQL)
- **Responsibility:** Read-only consultas históricas >6 meses (A33).
- **Invariants:** Rails `connects_to` secondary; writes only via archive job from primary; same schema as `user_events`.

### AccountDeletionRecord (in event or snapshot)
- **Responsibility:** Preserve `historical_email`, `historical_name` for admin-only timeline after user row anonymized (A38).

---

## Concept glossary (for user — mirrored in chat)

See explore-task step 1.2 response for plain-language explanations of: admin vs console vs Metabase, multi-tenant, user_events vs domain tables, sync/async, idempotency, correlation IDs, billing source of truth vs events, 24h retention vs download events, drill-down timeline, alerts, phasing, rate limit.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Volume de eventos + jsonb | Índices por `occurred_at`, `user_id`, `event_type`; archive job |
| PII (IP, filename) | Política retención; admin-only; no export masivo sin rol |
| Proyecto borrado | `project_id` + snapshot en eventos |
| Duplicar KPIs vs billing tables | KPIs monetarios desde `payments`/`subscriptions`; eventos para embudo/timeline |

---

## Scratchpad

- `session_workflow_log` en Project ≠ producto bitácora (in-session only, SPEC).
- Auth-billing session stays locked; link REQ-FIT-ANALYTICS-001 (TBD) in SPEC when plan locks.
- Gráficos v1: Chart.js themed (A40); KPI cards `metric--alert` cuando threshold breached (A30). Stimulus `admin_chart_controller` monta canvas por página.
- GeoLite2: documentar actualización mensual de DB en DEPLOY; licencia MaxMind attribution.
- Rate limit: si se excede, **no** error al usuario — drop silencioso + `Rails.logger` contador (solo low_priority).

---

## Follow-ups

| ID | Topic |
|----|--------|
| FU-LEGAL-003 | Privacidad: IP, UA, país, retención 6m + archivo |
| FU-ANALYTICS-001 | Valores default umbrales rojos (3 métricas) |

---

## Decisions log

- **2026-05-20 — NEW-TASK:** Sesión separada `task_user-analytics.md` (user confirmed).
- **2026-05-20 — A1–A25:** Primera ronda discovery.
- **2026-05-20 — A26–A39:** Admin app role, user_events+jsonb, sync/async, idempotency, bitácora consulta only, umbrales rojos sin push, paralelo auth, rate limit, archive PG, ENV admin email, GeoLite2+CF fallback, embudo, identidad histórica admin-only.
- **2026-05-20 — A40:** Gráficos llamativos (Chart.js + tema Fitloop); A30 aclarado = semáforo visual en dashboard, sin notificaciones.
- **2026-05-20 — SPEC COMPLETO:** Implementation plan locked; REQ-FIT-ANALYTICS-001; ADR-0006; defaults umbrales en `config/analytics.yml`.

---

## ADR-0006 + REQ (proposed)

### ADR-0006: Admin analytics & user event bitácora
- **Single-tenant** operator; `users.admin` + `FITLOOP_ADMIN_EMAIL`; `/admin/*` returns 404 for non-admins.
- **`user_events`** append-only jsonb; **not** billing source of truth; no DXF/geometry blobs in events.
- **Ingestion:** `Analytics::TrackEvent` — critical sync, low async via `TrackEventJob`; idempotency_key unique; rate limit 300/h low only.
- **Geo:** GeoLite2 local + `CF-IPCountry` fallback.
- **Retention:** 6 months hot primary DB → copy to **`analytics_archive`** PostgreSQL (read-only connection) → delete from hot.
- **Charts:** Chart.js v4 via importmap + Stimulus; themed KPI cards; threshold semáforo from `config/analytics.yml`.
- **Parallel** with auth-billing; billing KPIs JOIN `payments`/`subscriptions` when present.

### REQ-FIT-ANALYTICS-001
| Area | Requirement |
|------|-------------|
| Events | Record reasonable user/project/nest/split/auth/billing actions with metadata (filename, counts, job duration_ms); forbid geometry/DXF paths |
| Admin | Internal-only dashboard, user search, per-user timeline, funnel, CSV export, bot suspicion flag |
| Privacy | IP, UA, country; 6m hot + archive DB; account delete anonymizes user row; admin retains historical identity in events |

## Seed thresholds (`config/analytics.yml`)

```yaml
funnel_conversion_min_percent: 15
payment_failure_rate_max_percent: 20
nest_duration_p95_max_seconds: 600
low_priority_events_per_hour: 300
```

---

## Implementation plan

<task_session>
  <metadata>
    <task_name>user-analytics</task_name>
    <type>Feature</type>
    <req_id>REQ-FIT-ANALYTICS-001</req_id>
    <roadmap_item>Product &amp; platform — Admin analytics &amp; user bitácora</roadmap_item>
    <phasing>Parallel with auth-billing: events after User migration; billing instrumentation when BILL models exist</phasing>
  </metadata>

  <implementation_plan>
    <!-- P0 — Governance & anchors -->
    <step id="1" status="pending">Write failing doc/architecture test for REQ-FIT-ANALYTICS-001 in docs/core/SPEC.md (extend existing doc verifier pattern).</step>
    <step id="2" status="pending">Add docs/core/ADRs/0006-admin-analytics-and-user-events.md (user_events, TrackEvent, archive DB, Chart.js importmap, admin 404 gate, not billing SSOT).</step>
    <step id="3" status="pending">Update docs/core/SPEC.md (REQ-FIT-ANALYTICS-001 detail), DATA_FLOW_MAP.md (event ingestion points), SCHEMA_REFERENCE.md (`user_events`, `users.admin`), docs/ROADMAP.md pending P8 Analytics.</step>

    <!-- P1 — Event pipeline (can start before billing; user_id nullable) -->
    <step id="4" status="pending">Write failing model spec UserEvent [REQ-FIT-ANALYTICS-001]: event_type, priority, properties jsonb, user_id nullable, anonymous_session_key, tab_id, project_id, nesting_run_id, ip, user_agent, country_code, locale, idempotency_key unique, occurred_at; no blob columns.</step>
    <step id="5" status="pending">Migration `user_events` + indexes (`occurred_at`, `user_id`, `event_type`, unique `idempotency_key` where not null); add `config/analytics.yml` with Spanish comments and seed thresholds.</step>
    <step id="6" status="pending">Write failing Analytics::Thresholds spec: loads YAML, hot-reload on mtime, breach detection for funnel %, payment failure %, nest p95 seconds.</step>
    <step id="7" status="pending">Implement Analytics::Thresholds; implement Analytics::TrackEvent (idempotency no-op, rate limit low_priority 300/h, critical sync insert, low enqueue TrackEventJob).</step>
    <step id="8" status="pending">Write failing TrackEventJob spec: low_priority persisted async; critical never dropped by rate limit.</step>
    <step id="9" status="pending">Implement TrackEventJob; Analytics::ResolveCountry (GeoLite2 MMDB path ENV + CF-IPCountry fallback); document MMDB download in docs/DEPLOY.md.</step>
    <step id="10" status="pending">Write failing Analytics::MergeAnonymousSession spec: on login/register, reassign `user_events` rows from `anonymous_session_key` to `user_id`.</step>
    <step id="11" status="pending">Implement merge hook from SessionsController/Devise callbacks after auth-billing User exists.</step>

    <!-- P2 — Workshop instrumentation -->
    <step id="12" status="pending">Write failing spec: workspace_started, first_dxf_uploaded (filename + byte size + layer metadata, no blob), project_discarded snapshot in properties.</step>
    <step id="13" status="pending">Instrument Workspace/ProjectsController/DXF upload: reasonable add/remove sheet/layer events (low_priority); project_discarded critical snapshot.</step>
    <step id="14" status="pending">Write failing spec: nest_completed/partial/failed/cancelled with duration_ms, pieces_count, sheets_used, orphans_by_reason json; separate event per NestingRun (re-nest).</step>
    <step id="15" status="pending">Instrument NestingJob terminal paths + split job terminals (auto-split accept/reject/regenerate) with nesting_run_id correlation.</step>

    <!-- P3 — Admin gate (requires User from auth-billing) -->
    <step id="16" status="pending">Write failing spec [REQ-FIT-ANALYTICS-001]: `users.admin` boolean; user matching FITLOOP_ADMIN_EMAIL promoted on create; non-admin GET /admin/analytics → 404.</step>
    <step id="17" status="pending">Migration `users.admin`; Admin::BaseController; restrict routes namespace `admin`; seed/doc ENV FITLOOP_ADMIN_EMAIL.</step>

    <!-- P4 — Dashboard UI -->
    <step id="18" status="pending">Pin chart.js in importmap; add Stimulus admin_chart_controller + admin analytics CSS (blueprint theme, coral alert, animation on load).</step>
    <step id="19" status="pending">Write failing request spec Admin::AnalyticsController: KPI cards, funnel counts from user_events, semáforo CSS class when threshold breached.</step>
    <step id="20" status="pending">Implement GET /admin/analytics — near-real-time aggregates; daily/weekly toggle; filters date range, locale, payment_method, currency (billing JOIN when tables exist, else omit monetization widgets).</step>
    <step id="21" status="pending">Write failing spec: monetization KPIs from Payment/Subscription tables (not event amounts) — paid downloads split single vs plan, active/sold plans by tier, 1m plan users quota exhausted — skip examples if billing not merged yet.</step>
    <step id="22" status="pending">Implement billing KPI queries when REQ-FIT-BILL models present; bot_heuristic flag on users with excessive low_priority velocity.</step>

    <!-- P5 — User list & timeline -->
    <step id="23" status="pending">Write failing request spec Admin::UsersController#index search by email/name; show timeline ordered occurred_at desc.</step>
    <step id="24" status="pending">Implement /admin/usuarios and /admin/usuarios/:id (timeline drill-down, human-readable event labels i18n es primary).</step>

    <!-- P6 — Auth & account events (parallel auth-billing) -->
    <step id="25" status="pending">Write failing spec: account_registered, account_logged_in/out, email_confirmed, account_deleted with historical_email/name in properties (admin-only display).</step>
    <step id="26" status="pending">Instrument Devise/OmniAuth/delete-account flow; wire Accounts::Delete to emit account_deleted before anonymize.</step>

    <!-- P7 — Billing events (when auth-billing P4 merged) -->
    <step id="27" status="pending">Write failing spec: paywall_viewed, payment_succeeded/failed, download_completed (+ download_from_mis_pagos), idempotent double download click.</step>
    <step id="28" status="pending">Instrument paywall, simulated checkout, signed download controllers; JOIN-only KPIs remain on Payment/Subscription.</step>

    <!-- P8 — Export & archive -->
    <step id="29" status="pending">Write failing spec: GET /admin/analytics/export.csv respects filters; admin only.</step>
    <step id="30" status="pending">Implement CSV export (events + KPI summary sheets or single sheet TBD in impl).</step>
    <step id="31" status="pending">Configure second database `analytics_archive` in database.yml; migration same `user_events` schema on archive DB.</step>
    <step id="32" status="pending">Write failing Analytics::ArchiveEventsJob spec: copies rows older than 6 months, deletes from primary only after successful copy.</step>
    <step id="33" status="pending">Implement ArchiveEventsJob + recurring schedule; admin historical queries union hot + archive when date &gt; 6 months.</step>

    <!-- P9 — QA -->
    <step id="34" status="pending">System spec: anonymous session events → login → merged user_id; admin sees funnel; threshold turns metric--alert red when seed breached in test.</step>
    <step id="35" status="pending">Update docs/QA_MANUAL_CHECKLIST.md admin section; i18n admin event labels en/es; note FU-LEGAL-003 in follow-ups.</step>
  </implementation_plan>

  <working_notes>
    Run in parallel with auth-billing: steps 16–17 need User model; steps 27–28 need billing models.
    Chart.js only (no SPA); ADR required for importmap pin.
    session_workflow_log on Project remains separate (in-session only).
    Do not store DXF, SVG preview, geometry, or client absolute paths in properties.
  </working_notes>
</task_session>
