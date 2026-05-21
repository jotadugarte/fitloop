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
| A25 | **Abuso:** detección de bots (patrones); rate limit en **escritura** de eventos (anti-spam a la tabla). |

---

## Phasing (recommendation — pending user confirm)

| Opción | Significado |
|--------|-------------|
| **Antes** | Implementar bitácora antes de terminar auth/billing — más eventos “huérfanos” sin `user_id` real hasta que exista User. |
| **En paralelo** | Misma ventana de desarrollo: Fase A User + rol admin + esqueleto `UserEvent`; billing añade eventos y KPIs de pago cuando mergee Fase B. **Recomendado.** |
| **Después** | Bitácora solo cuando auth+billing estén en `main` — menos rework, KPIs completos desde día 1 del admin. |

_User dijo “no sé” en 23 — marcar TBD hasta confirmar._

---

## Open questions (remaining)

### Archivo cold (A12)
- [ ] ¿Formato del repositorio aparte? (S3 bucket, parquet en disco, segunda DB Postgres read-only, dump gzip a `storage/archive/`)
- [ ] ¿Job mensual automático o manual con rake task?

### Admin role (A2)
- [ ] ¿Un solo flag `users.admin` boolean o tabla `roles`?
- [ ] ¿Primer admin por seed/ENV o consola one-off?

### País (A11)
- [ ] ¿GeoIP en app (gem MaxMind) o solo país si CDN/proxy lo envía (`CF-IPCountry`)?

### Idempotencia (reintentos)
- [ ] ¿Clave `idempotency_key` por (user, event_type, nesting_run_id, occurred_at bucket minute) para no duplicar doble-click en descargar?

### Rate limit
- [ ] ¿Límite por IP/sesión ej. 200 eventos/hora para eventos no críticos; eventos de billing/nest siempre permitidos?

### Bot detection (A25)
- [ ] ¿Solo flag en dashboard o auto-`suspended_at` sugerido? (probable: flag + review manual v1)

### Embudo — pasos exactos
- [ ] Confirmar pasos: `workspace_start` → `first_upload` → `nest_success` → `paywall_view` → `payment_success` → `download_complete`

### Legal
- [ ] Política de privacidad debe mencionar IP/UA/país y retención 6m+cold — FU-LEGAL-003

---

## Domain Model (draft)

### UserEvent
- **Responsibility:** Append-only fact log for admin analytics; one row per meaningful action or outcome.
- **Invariants:** no blob columns; `occurred_at` UTC; `user_id` nullable until linked; `anonymous_session_key` stable pre-login; after 6 months hot → row copied/archived and removed from hot table (TBD mechanics).
- **Fields (conceptual):** `event_type` (enum/string), `properties` (jsonb metadata), `user_id`, `anonymous_session_key`, `tab_id`, `project_id`, `nesting_run_id`, `ip`, `user_agent`, `country_code`, `locale`, `idempotency_key` (optional unique).
- **Value objects:** `EventType`, `AnonymousSessionKey`, `CountryCode`, `EventProperties` (jsonb schema per type).

### ProjectSnapshot (or embedded in first/last project event)
- **Responsibility:** Preserve project metadata after `Project` destroyed.
- **Invariants:** created on `project_discarded` or last event; no geometry; includes sheet stock summary, layer config, kerf/margin settings.

### AdminUser / Role
- **Responsibility:** Gate `/admin/*`.
- **Invariants:** at least one admin in prod via seed; non-admin receives 404 (no leak).

### ArchivedEventBatch (TBD)
- **Responsibility:** Pointer to cold storage chunk (period, path, row count).

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
- Gráficos v1: Chartkick/Chart.js o CSS simple — ADR if new asset pipeline.

---

## Decisions log

- **2026-05-20 — NEW-TASK:** Sesión separada `task_user-analytics.md` (user confirmed).
- **2026-05-20 — A1–A25:** Ver tabla Agreed.
