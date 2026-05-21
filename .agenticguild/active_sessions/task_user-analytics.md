# Task: User analytics & admin bitácora — discovery

**Created:** 2026-05-20  
**Status:** Discovery in progress (explore-task phase 1)  
**Depends on:** `task_auth-billing.md` (User, billing tables — eventual; bitácora can scaffold events before billing ships)  
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

### Umbrales semáforo (A30)
- [ ] Valores iniciales en `config/analytics.yml` (propuesta en plan: 3 métricas con defaults razonables; editables sin redeploy en dev).

### Legal
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
