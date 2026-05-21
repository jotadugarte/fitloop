# Task: Auth + billing (simulated) — discovery

**Created:** 2026-05-20  
**Status:** Spec locked — handoff to `start-task` (2026-05-20, D54/D21/D49)  
**Owner intent:** Cuentas de usuario (OAuth + email) siempre accesibles; uso anónimo del flujo actual; paywall al descargar DXF anidado; pago por archivo o plan 1/2/4 meses; pagos simulados en v1; proyectos siguen efímeros aunque haya login.

**Phasing (user):** Fase A = identidad/login/registro. Fase B = cobros simulados + planes.

---

## Context anchors

- Hoy: `REQ-FIT-AUTH-001` = solo `Workspace` + `session[:workspace_project_id]` (ADR-0004). **No existe modelo `User`.**
- Proyectos: siempre `ephemeral: true`; destruidos en `Workspace.discard!` / cierre de sesión de workspace.
- Descarga anidada: flujo existente post-nest (ver `REQ-FIT-UI-003`).

---

## Agreed (from user, 2026-05-20)

| # | Decision |
|---|----------|
| D1 | Login/registro visible en todo momento (header o equivalente). |
| D2 | Flujo sin cuenta: Empezar → subir → anidar → al pulsar **Descargar DXF anidado** → pantalla de cobro o login/plan. |
| D3 | Proveedores: Google, Facebook, Apple, email/contraseña manual. |
| D4 | Planes: **1, 2 y 4 meses** (no 3) con precios distintos; vigencia desde instante de pago. |
| D5 | Rutas de pago: (a) pago único por archivo, (b) suscripción por plan. Usuario logueado sin plan puede elegir cualquiera. |
| D6 | Proyectos **no** persisten por usuario; al salir/cerrar sesión se borra el trabajo en curso (mismo modelo efímero). |
| D7 | Cobros **simulados** primero; integración real (Stripe/etc.) después. |
| D8 | Implementar en dos partes: auth primero, pagos después. |
| D9 | **Registro** por dos vías equivalentes: (1) OAuth Google / Facebook / Apple — un clic crea cuenta o inicia sesión; (2) email + contraseña sin OAuth. Misma pantalla de registro/login. |
| D10 | **Verificación email:** enviar link de confirmación; `email_confirmed_at` obligatorio antes de **pagar** o **activar plan**. OAuth: confirmar email del proveedor o reutilizar flujo de link si el proveedor no garantiza verificación. |
| D11 | **Colisión de email:** si el email ya existe con otro método → pantalla “¿Fusionar en una sola cuenta?” (opt-in); no fusionar en silencio. |
| D12 | **Sin vincular proveedores** en “Mi cuenta” en v1; OAuth solo acelera login/registro. Colisión cubierta por D11. |
| D13 | **Contraseña (email):** mínimo **12** caracteres; recuperación **“Olvidé mi contraseña”** por email en v1. |
| D14 | **Nombre obligatorio** en registro (saludos UI + facturación futura). |
| D15 | **Borrar cuenta:** permitido en v1; confirmación fuerte (multi-paso); si hay **plan activo**, advertencia explícita de pérdida de beneficio. |
| D16 | **Términos y privacidad:** checkbox obligatorio al registrarse (email y OAuth). **Follow-up:** redactar/revisar textos legales y versión almacenada (`terms_accepted_at` + versión). |
| D17 | **Sin verificación de edad** en v1. |
| D18 | **B1:** login/registro con proyecto en curso → **mantener** el mismo `Project` (re-bind tras auth). |
| D19 | **B2:** logout usuario → `Workspace.discard!` (como salir del taller) + advertencia si hay proyecto activo. |
| D20 | **B3:** sin logout, ausencia **>2 min** desde última actividad → proyecto expirado + mensaje claro; **≤2 min** → recupera el mismo proyecto. |
| D21 | **B4:** multi-pestaña = proyectos efímeros **independientes**; sin plan → paywall **por cada** “Descargar DXF” en cada pestaña; con plan activo → descarga según plan. **Sesión Rails:** `session[:workspaces] = { tab_id => project_id }` (hash por pestaña); `tab_id` UUID en `sessionStorage` vía Stimulus — evita mezclar Turbo Streams entre pestañas. |
| D22 | **B5:** sin email verificado → toda la app excepto descargar, pagar y activar plan. |
| D23 | **C1 — Paywall:** solo **Descargar DXF anidado**; preview/JSON gratis. **Eliminar** botón de descarga de DXF huérfanos (evitar ambigüedad de cobro). |
| D24 | **C2 — Re-nest:** cada descarga exitosa tras un nuevo nest = **nuevo cobro** (o plan activo). |
| D25 | **C3 — Partial / huérfanos sin resolver:** se cobra **igual** al descargar anidado; responsabilidad del usuario decidir cuándo descargar. |
| D26 | **C4 — Precio:** fijo global por descarga en v1; modelo preparado para precio **dinámico** después (láminas, piezas, etc.). |
| D27 | **Cupo de plan:** **50 descargas / mes** en cada mes del periodo (1m→50, 2m→50+50, 4m→50×4 máx. 200); contador **reinicia por mes** dentro del ciclo (no un solo pool de 200). |
| D34 | **Cupo agotado en el mes:** puede **descarga suelta** al **50%** del precio normal de descarga; copy + **términos/planes** deben documentarlo (FU-LEGAL-001 / definición de planes). |
| D28 | **Un plan activo** a la vez; compra adicional del **mismo u otro tier** → extiende `ends_at` desde el **fin** del plan vigente (no reinicia desde hoy). |
| D29 | **Vigencia:** `starts_at` = instante del pago; `ends_at` = **fin del día natural** N meses después en `users.time_zone` (23:59:59 del día ancla). |
| D30 | **Vencimiento:** bloqueo **inmediato** en la siguiente descarga; **sin grace period**. |
| D31 | **Renovación:** manual cuando el plan ya venció (“comprar plan otra vez”); sin auto-cobro en v1 simulado. |
| D32 | **Sin upgrade/prórroga** a mitad de ciclo; el ciclo actual debe **terminar** antes de tratar compra como nuevo ciclo (extensión D28 es caso distinto: añadir tiempo al `ends_at`). |
| D33 | **Descarga con plan activo + cupo OK:** descarga directa con mensaje breve tipo “Incluido en tu plan” (copy amable, i18n). |
| D35 | **E1 — Moneda:** tarjeta → **USD**; SINPE Móvil → **CRC (colones)** solamente. |
| D36 | **E2 — Precios configurables:** settings/admin para precio descarga suelta + planes **1 / 2 / 4 meses** (tiers fijos, montos editables). |
| D37 | **E3 — Simulación v1:** checkout demo con “Tarjeta (USD)” y “SINPE Móvil (CRC)”; botones **Pago exitoso** / **Pago fallido** + indicador entorno demo (QA). |
| D38 | **E4 — Mis pagos:** historial, plan activo (vence, cupo mes actual usado/restante), descargas sueltas pagadas por run/fecha. |
| D39 | **E5 — Post-pago:** descarga suelta → **auto-descarga** (+ “Descargar ahora” respaldo). Plan activo → descarga directa sin paso extra post-compra. |
| D40 | **E6 — Invitado:** todo excepto descargar; al descargar → **registro/login obligatorio** antes de pagar descarga o plan (sin guest checkout). |
| D41 | **G1 — Rutas cuenta (es, alineado con `/empezar`):** `/iniciar-sesion` (login), `/crear-cuenta` (registro), `/mi-cuenta` (perfil + enlace a Mis pagos), `/mis-pagos`, `/planes` (precios/checkout plan). Header: “Iniciar sesión” / “Crear cuenta”. |
| D42 | **G2 — Paywall UX:** al pulsar Descargar → pantalla clara “Se requiere pago o plan” con opciones (pago esta descarga / ver planes / iniciar sesión); sin sorpresa. |
| D43 | **G3 — Post-compra plan:** redirect de vuelta al **proyecto** (`project#show`), no solo Mis pagos. |
| D44 | **H1 — Descarga sin pago:** el endpoint de descarga **rechaza** siempre sin grant/plan/cupo; no es rate limit — es autorización estricta (reintentos no ayudan). |
| D45 | **H2 — URLs firmadas:** **sí** — token de descarga con caducidad (ej. 15 min) por `NestingRun` + usuario. |
| D46 | **H3 — Bloqueo cuenta:** **sí** — `users.suspended_at`; suspendidos no pagan ni descargan; admin v1 vía consola. |
| D47 | **I1 — Gobernanza:** **sí** — ADR-0005 + `REQ-FIT-AUTH-002`, `REQ-FIT-BILL-001..003` en SPEC. |
| D48 | **I2 — Auth stack:** **Devise + OmniAuth** (Google, Facebook, Apple). |
| D49 | **F1 — Timezone plan:** `users.time_zone` obligatorio antes de comprar plan; `ends_at` = fin del día natural en esa zona. **Captura automática** en registro y checkout de plan vía JS: `Intl.DateTimeFormat().resolvedOptions().timeZone` → campo oculto / endpoint que persiste en `users.time_zone` (usuario puede corregir después en Mi cuenta). |
| D50 | **F2 — Re-descarga con plan:** gratis mientras grant de plan + cupo OK + **proyecto efímero aún vivo** en workspace; si expiró sesión/TTL/logout → **no** re-descarga (debe re-anidar). Mis pagos = historial informativo para planes. |
| D54 | **F2b — Retención 24h (solo pago suelta):** si `Purchase` exitoso + `DownloadGrant` para un `NestingRun`, copiar/blindar el `nested_dxf` (Active Storage) en almacenamiento **ligado al usuario** (no al `Project` efímero) accesible desde `/mis-pagos` **≥24 h** desde el pago, **ignorando** TTL 2 min del workspace. Descarga desde Mis pagos con URL firmada. **No aplica** a descargas incluidas en plan. |
| D55 | **F2b — Copy pago suelta:** tras checkout exitoso y en paywall de descarga suelta, mensaje i18n: el archivo quedará disponible en **Mis pagos** por **24 horas** aunque cierre el taller o pierda la sesión. |
| D56 | **F2b — Purga:** al vencer `retained_until` (24 h), job o lazy purge del blob retenido; registro en Mis pagos puede quedar como historial sin botón de descarga. |
| D51 | **F3 — Métodos de pago:** planes y sueltas — USD tarjeta y CRC SINPE. |
| D52 | **F4 — OAuth:** orden Google → Facebook → Apple → email; proveedores habilitados según credenciales (no todos obligatorios). |
| D53 | **F5 — Precios (opción C):** v1 = archivo **`config/billing.yml`** comentado en español (abrir → editar valores → guardar → app recarga sola). v1.1+ = pantalla admin web opcional. |

---

## Open questions (blocking)

### A. Identidad y registro
- [x] Cerrado (D9–D17).
- [ ] **Follow-up (no bloquea Fase A técnica):** contenido y hosting de Términos / Política de privacidad; versión legal.

### B. Sesión workspace vs sesión usuario
- [x] Cerrado (D18–D22).
- [x] **Multi-pestaña + TTL 2 min:** `session[:workspaces]` hash + `tab_id` Stimulus + `last_activity_at` (D21, D20).
- [x] **Retención post-pago suelta 24 h:** blob en grant/usuario, no en proyecto (D54–D56).

### C. Paywall — alcance
- [x] Cerrado (D23–D26). UX: quitar descarga huérfanos.

### D. Planes y entitlements
- [x] Cerrado (D27–D34).

### E. Pago único, moneda, simulación, Mis pagos
- [x] Cerrado (D35–D40).

### F. Simulación de pagos
- [x] Cubierto por D37 (botones éxito/fallo + métodos demo).

### G. UX y i18n
- [x] Cerrado (D41–D43).

### H. Seguridad y abuso
- [x] Cerrado (D44–D46).

### I. Arquitectura / gobernanza
- [x] Cerrado (D47–D48): ADR-0005 + REQs; Devise + OmniAuth.

### Final polish
- [x] **F1 (D49):** Fin de día natural del plan en la **zona horaria del usuario** al suscribirse (`users.time_zone`, capturada en registro/checkout).
- [x] **F2 (D50, D54):** Plan: re-descarga solo con proyecto vivo. **Pago suelta:** re-descarga desde proyecto **o** desde Mis pagos hasta 24 h (blob retenido). Escenario 2:30 AM + SINPE + caída de red → mitigado para sueltas.
- [x] **F3 (D51):** Planes y descarga suelta: **Tarjeta USD** y **SINPE CRC**.
- [x] **F4 (D52):** OAuth **opcionales** (no obligatorio configurar los 3); orden UI e implementación: **Google → Facebook → Apple → email**. Puede lanzarse con solo los configurados.
- [x] **F5 (D53):** `config/billing.yml` amigable + hot-reload.

---

## Domain Model

_Approved 2026-05-20 (start-task step 3.0)._

### User
- **Responsibility:** Identidad persistente; no dueño de `Project` rows en v1.
- **Invariants:** email único (case-insensitive); `email_confirmed_at` presente antes de billing; `name` presente; `time_zone` presente antes de comprar plan; `terms_accepted_at` + `terms_version` al crear cuenta; contraseña ≥12 chars si auth por email; `suspended_at` nil para operar.
- **Value objects:** `EmailAddress`, `UserId`, `DisplayName`, `TermsVersion`, `TimeZone`.

### Subscription (plan)
- **Responsibility:** Derecho a descargar bajo reglas del plan durante `[starts_at, ends_at]`.
- **Invariants:** `ends_at > starts_at`; un plan activo por usuario; cupo 50 descargas por mes natural del ciclo; contador mensual reinicia; overage = pago suelta al 50% del precio lista.
- **Value objects:** `PlanTier` (1m|2m|4m), `MoneyAmount`, `SubscriptionId`, `DownloadQuota` (50/mes en tier 1m — TBD otros).

### Purchase (one-off)
- **Responsibility:** Desbloquea **una** descarga de `nested.dxf` ligada a un `NestingRun` concreto (cada re-nest exitoso = nueva compra si no hay plan).
- **Invariants:** idempotente por intento de checkout; 1 grant ↔ 1 run ↔ 1 descarga; precio v1 = constante configurable (`single_download_price`); al `succeeded` dispara retención de blob (D54).

### Payment (simulated)
- **Responsibility:** Registro de intento/éxito/fallo; puente a proveedor futuro.
- **Invariants:** estado terminal `succeeded` | `failed` | `cancelled`.

### Entitlement / DownloadGrant
- **Responsibility:** Resolver “¿puede descargar ahora?” sin recalcular pagos en cada request.
- **Invariants:** 1 grant activo por (`user_id`, `nesting_run_id`); re-descargas del mismo run permitidas con el mismo grant; URL firmada expira (ej. 15 min por intento); no sustituye verificación de `suspended_at` / cupo plan.
- **Single-purchase extension (D54):** `kind: single_purchase` incluye `retained_nested_dxf` (Active Storage en el grant o tabla `DeliveredDownload`) + `retained_until` = `paid_at + 24.hours`; descarga autorizada si `Time.current <= retained_until` aunque `Project` ya no exista.
- **Plan grant:** sin blob retenido; autorización solo con proyecto vivo + cupo.

### DeliveredDownload (nombre TBD en implementación)
- **Responsibility:** Copia durable del `nested_dxf` del run pagado, desacoplada del `Project` efímero.
- **Invariants:** creado solo en `Purchase` suelta exitosa; blob copiado desde `Project#nested_dxf` en el momento del pago (antes de posible `discard!`); `nesting_run_id` + metadatos (fecha, monto) para `/mis-pagos`; purga tras `retained_until`.
- **Value objects:** `RetentionWindow` (24h desde pago), `NestingRunId`, `SignedDownloadToken`.

---

## Risks

| Risk | Mitigation (TBD) |
|------|------------------|
| Conflicto ADR-0004 (solo session bind) vs cuentas | ADR nuevo; separar `Workspace` (efímero) de `User` (persistente) |
| Usuario paga suelta y pierde proyecto (TTL 2 min, baño, red) | **D54:** blob retenido 24 h en Mis pagos; copy D55; copia en checkout success |
| Usuario con plan pierde proyecto | Sin retención (D50); debe re-anidar; Mis pagos solo historial |
| `Project#destroy` borra `nested_dxf` en proyecto | Copiar blob a grant/`DeliveredDownload` en transacción post-pago **antes** de responder auto-download |
| Multi-pestaña rompe bind 1:1 actual de `Workspace` | `session[:workspaces]` hash (D21); specs Turbo + dos tabs |
| OAuth en WSL/dev (Apple/Google callbacks) | URLs de redirect por entorno |
| Alcance creep en Fase A | Fase A solo identidad; sin cobro hasta spec Fase B cerrada |

---

## User scenario (D54 — “2:30 AM”)

Estudiante paga descarga suelta (SINPE/tarjeta simulado). Pago `succeeded`, pero pierde foco >2 min (baño, red). Al volver: workspace expirado, proyecto destruido. **Sin D54:** pagó y no puede descargar → reclamos. **Con D54:** en `/mis-pagos` ve la compra y descarga el mismo `nested_dxf` retenido hasta 24 h. Con **plan activo**, el comportamiento sigue efímero: sin re-nest no hay archivo.

## Scratchpad

- **Blob hoy vive en `Project#nested_dxf`**, no en `NestingRun` (DATA_FLOW_MAP). Retención = **copia** al pagar, no confiar en proyecto post-`discard!`.
- `ActiveStorage::Blob` puede compartirse vía `attach` desde blob existente o `download`+re-upload según política de purga.
- Apple Sign In requiere cuenta desarrollador + dominio verificado.
- Facebook/Google: políticas de datos y app review si se publica.
- `Workspace.discard!` ya cancela nesting activo — alinear con logout usuario.
- **Multi-tab:** `Workspace::SESSION_KEY` → `:workspaces` Hash; `bind!(session, project, tab_id:)` / `resolve!(session, project_id, tab_id:)`; Stimulus `workspace_tab_controller` emite `tab_id` en headers o params de heartbeat.
- **Timezone JS:** `timezone_capture_controller` en registro + checkout plan; fallback `America/Costa_Rica` solo si `resolvedOptions().timeZone` vacío (documentar en ADR).
- **B3 copy:** mensaje explícito (“perdiste el proyecto anterior”) es más honesto que desaparecer sin aviso — acordado.
- **Auth gems:** “Auth0” = SaaS externo (no es la gema típica Rails). **Authentication Zero** = generador Rails 8 auth sin Devise. **Devise** + **omniauth-*` = clásico OAuth. Fitloop kill list no prohíbe ninguno; ADR debe fijar uno.

---

## Decisions log

- **2026-05-20 — D9:** Registro/login vía OAuth (Google, Facebook, Apple) o email+contraseña; rutas paralelas en la misma UX de cuenta.
- **2026-05-20 — D10–D17:** Verificación email pre-billing; fusión opt-in por colisión de email; sin link de proveedores post-registro; password ≥12 + reset por email; nombre obligatorio; delete cuenta con confirmación fuerte; términos checkbox (textos TBD); sin edad.
- **2026-05-20 — D18–D22:** Mantener proyecto al auth; logout = discard + warn; TTL 2 min + mensaje al expirar; multi-tab proyectos independientes + paywall por descarga sin plan; app usable sin email verificado excepto download/billing.
- **2026-05-20 — D23–D26:** Paywall solo nested DXF; quitar descarga huérfanos; cobro por cada descarga post-re-nest; partial/orphans mismo precio; precio fijo v1 + extensible dinámico.
- **2026-05-20 — D27–D33:** Planes 1/2/4 meses; 50 desc/mes (tier 1m); un plan activo; extensión desde `ends_at`; inicio en instante de pago; sin grace; renovación post-vencimiento manual; sin upgrade mid-cycle; mensaje “incluido en plan”.
- **2026-05-20 — D29 (fin), D27 (cupos), D34:** Fin día natural; 50/mes × meses del periodo con contadores mensuales; overage descarga suelta al 50% + legal/planes.
- **2026-05-20 — D35–D40:** USD tarjeta / CRC SINPE; precios configurables; simulación éxito/fallo; Mis pagos; auto-descarga solo pago suelta; invitado debe registrarse al descargar.
- **2026-05-20 — D41–D44:** Rutas `/iniciar-sesion`, `/crear-cuenta`, etc.; paywall explícito; post-plan → proyecto; descarga sin grant = 403 siempre.
- **2026-05-20 — D45–D48:** URLs firmadas; `suspended_at`; ADR-0005 + REQs aprobados; Devise + OmniAuth.
- **2026-05-20 — D49–D52:** TZ usuario; re-descarga solo con proyecto vivo; ambos métodos pago; OAuth ordenado y opcional por credenciales.
- **2026-05-20 — D53:** Precios en `config/billing.yml` comentado; hot-reload; admin web después.
- **2026-05-20 — Seed prices:** ver sección **Seed pricing** (USD 2 / CRC 1000 suelta; planes 6/3000, 10/5000, 16/8000 CRC).
- **2026-05-20 — D54–D56:** Retención cloud 24 h solo pago suelta; planes efímeros; copy Mis pagos; purge post-ventana.
- **2026-05-20 — D21 (sesión), D49 (JS TZ):** `session[:workspaces]`; captura automática timezone navegador en registro/checkout plan.

## ADR-0005 + REQs (aprobado D47)

### ADR-0005: Cuentas de usuario + billing simulado
- **Mantiene** ADR-0004 / `REQ-FIT-AUTH-001`: `Workspace` + proyectos efímeros + tab-scoped bind + TTL 2 min.
- **Añade** capa `User` (persistente) ortogonal al workspace: login no implica guardar proyectos.
- **Billing simulado** con entitlements por `NestingRun`; planes 1/2/4m; cupo 50/mes; USD/CRC; **retención 24 h** del DXF solo en compra suelta (D54).
- **Workspace session:** `session[:workspaces]` hash por `tab_id` (D21).
- **Supersede** nada de ADR-0004; lo **extiende**.

### REQs propuestos (SPEC.md)
| ID | Alcance |
|----|---------|
| **REQ-FIT-AUTH-001** | Sin cambio semántico: acceso efímero por sesión/tab. |
| **REQ-FIT-AUTH-002** | Registro/login OAuth+email, verificación email, fusión opt-in, términos, borrar cuenta, rutas D41. |
| **REQ-FIT-BILL-001** | Paywall solo nested DXF; precios configurables; simulación pago; USD/CRC. |
| **REQ-FIT-BILL-002** | Planes 1/2/4m, cupo 50/mes, overage 50%, extensión desde `ends_at`, Mis pagos D38. |
| **REQ-FIT-BILL-003** | Grants por descarga + autorización en download; URLs firmadas; **retención 24 h** del `nested_dxf` en pagos sueltos (D54). |

## Follow-ups (producto / legal)

| ID | Topic | Notes |
|----|--------|-------|
| FU-LEGAL-001 | Términos de servicio y Política de privacidad | Redacción, idioma (es/en), URL pública, versionado y re-aceptación si cambian términos materialmente. No bloquea scaffold Fase A (placeholder + checkbox). |
| FU-LEGAL-002 | Planes y overage 50% | Documentar en términos y en copy de planes: 50 descargas/mes; descarga suelta al 50% del precio cuando el cupo mensual del plan está agotado. |
| FU-ADMIN-001 | Configuración de precios | **`config/billing.yml`** con comentarios por variable; `Billing::Pricing` recarga si cambia `mtime` (sin redeploy en dev; en prod guardar archivo + recarga automática al siguiente request). Admin UI diferida. |

## Seed pricing (`config/billing.yml` — ejemplos simulados acordados)

```yaml
single_download_usd: 2.00
single_download_sinpe_crc: 1000
plan_quota_overage_percent: 50
plan_1_month_card_usd: 6
plan_1_month_sinpe_crc: 3000
plan_2_months_card_usd: 10
plan_2_months_sinpe_crc: 5000
plan_4_months_card_usd: 16
plan_4_months_sinpe_crc: 8000
```

_Overage descarga suelta con cupo agotado: 50% → USD 1.00 / CRC 500 (derivado de seeds)._

---

## Implementation plan

<task_session>
  <metadata>
    <task_name>auth-billing</task_name>
    <type>Feature</type>
    <req_id>REQ-FIT-AUTH-002, REQ-FIT-BILL-001, REQ-FIT-BILL-002, REQ-FIT-BILL-003</req_id>
    <roadmap_item>Product &amp; platform — Auth + simulated billing</roadmap_item>
    <phasing>Fase A (auth) → Fase B (billing + workspace tab/TTL)</phasing>
  </metadata>

  <implementation_plan>
    <!-- P0 — Governance & anchors -->
    <step id="1" status="complete">Write failing architecture/doc tests or spec verifier stubs for new REQ-FIT-AUTH-002 and REQ-FIT-BILL-001..003 presence in docs/core/SPEC.md (extend existing doc verifier pattern if present).</step>
    <step id="2" status="complete">Add docs/core/ADRs/0005-user-accounts-and-simulated-billing.md (extends ADR-0004; `session[:workspaces]` hash; 24h retained nested_dxf for single purchase D54; billing.yml; Devise+OmniAuth; no project persistence per user).</step>
    <step id="3" status="complete">Update docs/core/SPEC.md (REQ-FIT-AUTH-002 detail, REQ-FIT-BILL-001..003), DATA_FLOW_MAP.md, SCHEMA_REFERENCE.md, docs/ROADMAP.md pending items P6 Auth / P7 Billing.</step>

    <!-- P1 — Fase A: Auth (Devise + OmniAuth) -->
    <step id="4" status="complete">Write failing model spec User [REQ-FIT-AUTH-002]: email unique, name required, password min 12, terms_accepted_at+version, time_zone, email_confirmed_at gate, suspended_at.</step>
    <step id="5" status="complete">Add gems (devise, omniauth-google-oauth2, omniauth-facebook, omniauth-apple); User migration; mount Devise routes under /iniciar-sesion /crear-cuenta (Spanish path names per D41).</step>
    <step id="6" status="complete">Write failing request spec: registration email+password requires name, terms checkbox, sends confirmation; unconfirmed cannot access checkout routes.</step>
    <step id="7" status="complete">Implement Devise :confirmable (or custom mailer) for email verification link; i18n en/es for auth flash and forms.</step>
    <step id="8" status="complete">Write failing request spec: password reset flow (forgot → email → reset ≥12 chars).</step>
    <step id="9" status="complete">Implement password recovery; header links “Iniciar sesión” / “Crear cuenta” on all layouts; logged-in menu Mi cuenta / Mis pagos / Cerrar sesión.</step>
    <step id="10" status="complete">Write failing OmniAuth spec: Google provider (conditional on credentials); ordered buttons Google → Facebook → Apple → email on login/register pages.</step>
    <step id="11" status="complete">Implement OmniAuth callbacks; capture name, email; Stimulus `timezone_capture_controller` sets `users.time_zone` from `Intl.DateTimeFormat().resolvedOptions().timeZone` on register (D49); trusted-provider email marks confirmed when policy allows; register Facebook/Apple similarly when ENV set.</step>
    <step id="12" status="complete">Write failing spec: email collision → merge opt-in screen (no silent merge); declining leaves user on error path.</step>
    <step id="13" status="complete">Implement Accounts::Merge opt-in service; no post-login provider linking UI (D12).</step>
    <step id="14" status="complete">Write failing spec: login/register mid-workflow keeps Workspace project bind (D18); return_to project#show.</step>
    <step id="15" status="complete">Implement auth return_to; Stimulus `workspace_tab_controller`: UUID per tab in sessionStorage; send `tab_id` on workspace requests for `session[:workspaces]` bind (D21).</step>
    <step id="16" status="complete">Write failing spec: logout runs Workspace.discard! with confirm when project active (D19).</step>
    <step id="17" status="complete">Implement logout + discard; /mi-cuenta profile; delete account multi-step confirm with active-plan warning (D15).</step>
    <step id="18" status="complete">Placeholder pages /terminos and /privacidad + checkbox links; FU-LEGAL-001 copy TBD.</step>

    <!-- P2 — Workspace: multi-tab + 2 min TTL (REQ-FIT-AUTH-001 extension per ADR-0005) -->
    <step id="19" status="complete">Write failing Workspace spec [REQ-FIT-AUTH-001]: `session[:workspaces] = { tab_id => project_id }`; bind/resolve by tab_id; independent project per tab; last_activity_at TTL 120s expires project with flash (D20–D21); Turbo requests include tab_id so streams do not cross tabs.</step>
    <step id="20" status="complete">Refactor Workspace: replace `SESSION_KEY` single id with `:workspaces` hash; `bind!(session, project, tab_id:)`, `resolve!(session, project_id, tab_id:)`, `discard!(session, tab_id:)`; Project#touch_activity!; heartbeat ping per tab.</step>
    <step id="21" status="complete">Write failing system spec: two tabs → two projects; closing tab &gt;2min shows lost-project message on return.</step>

    <!-- P3 — Billing config & domain -->
    <step id="22" status="complete">Add config/billing.yml with Spanish comments and seed pricing (D53); write failing Billing::Pricing spec: loads YAML, hot-reload on mtime, overage 50% math.</step>
    <step id="23" status="complete">Implement Billing::Pricing (≤60 lines, assertions on positive amounts); used by checkout and /planes display.</step>
    <step id="24" status="complete">Write failing migrations/models specs: Payment, Subscription (tier 1|2|4m), DownloadGrant (`kind`, `retained_until`, `has_one_attached :retained_nested_dxf` for single purchase), PlanMonthlyUsage (50/month) [REQ-FIT-BILL-001..003].</step>
    <step id="25" status="complete">Implement models + services: Billing::Entitlement, Billing::PlanPeriod (ends_at end-of-day in user.time_zone), Billing::QuotaCounter, Billing::RetainNestedDxf (copy blob on single purchase success, D54).</step>

    <!-- P4 — Fase B: Paywall & simulated checkout -->
    <step id="26" status="pending">Write failing request spec: nested DXF download without grant/plan → redirect paywall D42; preview still allowed; email unconfirmed blocked (D22).</step>
    <step id="27" status="pending">Remove orphan DXF download button from UI (D23); keep manual path only.</step>
    <step id="28" status="pending">Implement paywall page: options pay this run / planes / iniciar-sesion; guest must register before pay (D40).</step>
    <step id="29" status="pending">Write failing checkout spec: simulate card USD and SINPE CRC success/fail buttons (D37); creates Payment + DownloadGrant on success.</step>
    <step id="30" status="pending">Implement simulated checkout; on single purchase success: Billing::RetainNestedDxf before response, auto-download (+ Descargar ahora fallback D39), i18n copy D55 (24 h en Mis pagos); signed expiring download URL (D45); timezone_capture on plan checkout (D49).</step>
    <step id="31" status="pending">Write failing spec: plan purchase extends ends_at from current end (D28); calendar-month slices 50 quota; overage 50% price (D34); suspended user blocked (D46).</step>
    <step id="32" status="pending">Implement /planes + plan checkout; post-purchase redirect to project#show (D43); plan-active download shows “Incluido en tu plan” (D33).</step>
    <step id="33" status="pending">Write failing spec: plan re-download requires live project (D50); single purchase re-download from project OR /mis-pagos while `retained_until` (D54); expired retention → 403 with copy; workspace TTL does not purge retained blob.</step>
    <step id="34" status="pending">Implement /mis-pagos: payments list, active plan, quota, per-run rows with “Descargar” while retained (single only); purge job post-24h (D56).</step>
    <step id="35" status="pending">Write failing spec: checkout copies nested_dxf even if subsequent Workspace.discard! (simulate TTL); Mis pagos download works without session project bind (D54).</step>
    <step id="37" status="pending">Write failing system spec: anonymous → nest → pay suelta → discard workspace → download from Mis pagos (2:30 AM scenario); plan user loses project → cannot download without re-nest.</step>
    <step id="36" status="pending">i18n parity en/es (+ es_panic): auth, billing, paywall, `billing.single_download.retention_24h` (D55); update docs/QA_MANUAL_CHECKLIST.md; REQ-tagged regression.</step>
  </implementation_plan>

  <working_notes>
    OAuth optional per ENV (D52). Seeds in Seed pricing section. Fase B must not ship before Fase A auth gates checkout.
    D54 supersedes prior F2 wording for single purchases only; plan downloads stay ephemeral (D50).
    ADR-0005 step 2 must mention session[:workspaces] hash and DeliveredDownload/retained attachment.
  </working_notes>
</task_session>
