# Changelog

All notable user-facing changes to Fitloop are documented here.

## Unreleased

### Added

- **Admin foundation:** Added the `admin` boolean attribute on `User`, automated promotion of admin email lists via boot initializer (`FITLOOP_ADMIN_EMAILS`), layout for admin dashboard, and a secure stealth access gate at `/admin/*` returning 404 for unauthorized requests (`REQ-FIT-ADMIN-001`).
- **Unified Mi taller funnel:** EMPEZAR lands on `/taller` with contextual **setup mode** (láminas → nesting params → DXF; preview hidden until first nest) vs **taller mode** after first successful nest (`REQ-FIT-UI-001`, `REQ-FIT-UI-003`).
- **Workshop autosave:** sheet inventory, debounced nesting parameters, and DXF layer selection persist without explicit Save/Apply buttons in setup mode.
- **ONVO live billing:** card (CRC/USD) and SINPE Móvil checkout when `BILLING_GATEWAY=onvo`; Payment Intents, embedded card form with 3DS return, SINPE transfer instructions, processing poll, and authoritative webhook fulfillment (`REQ-FIT-BILL-001`, ADR-0006).
- **SINPE pending checkout lock:** 15-minute workshop lock while SINPE payment is pending; manual “Cancelar intento” releases lock without marking payment failed; late webhook still grants download (`REQ-FIT-BILL-001`).
- **SINPE pre-retention:** nested DXF copied at SINPE checkout start (not downloadable until payment succeeds); staging blob purged on failed webhook (`REQ-FIT-BILL-003`).
- **Purchase reference:** 12-digit display reference on single-download payments (Mis pagos, checkout processing, download rows).
- **Mis pagos ONVO UX:** pending SINPE rows with cancel/retry; payment method in history; superseded attempts in historial only; compact download rows with richer metadata.
- **Billing production geo:** Cloudflare `CF-IPCountry` required in production; GeoLite2 Country MMDB fallback; throttled audit logs (`REQ-FIT-BILL-001`).
- **MEIC pricing UX:** paywall shows SINPE price prominently with card reference in Costa Rica; checkout breakdown shows list subtotal, optional SINPE discount, and IVA 13% (CR only) (`REQ-FIT-BILL-001`).
- **Method-first checkout:** choose payment method first, then see a dynamic receipt and a single “Procesar pago” action (`REQ-FIT-BILL-001`).
- **Geo-aware billing defaults:** country from `CF-IPCountry` / GeoLite2 with manual CRC/USD override on the paywall (`REQ-FIT-BILL-001`).
- **Payment snapshots:** purchaser and financial breakdown persisted on `Payment` for both succeeded and failed simulated attempts (`REQ-FIT-BILL-001`).
- User accounts: email/password sign-up and sign-in, email verification, OAuth (Google, Facebook, Apple when configured), account edit, password reset, and account deletion (`REQ-FIT-AUTH-002`).
- Simulated billing: paywall on nested DXF download only; single-purchase checkout (USD card / CRC SINPE); subscription plans (1, 2, or 4 months) with monthly download quota; **Mis pagos** for plan status and retained downloads within 24h (`REQ-FIT-BILL-001`..`003`).
- Workshop multi-tab support: independent ephemeral projects per browser tab with tab-close expiry rules (`REQ-FIT-AUTH-001`, ADR-0005).
- Nesting progress bar with phased labels (queued through writing outputs), live percent from CLI `progress.json`, and cancel in the progress panel (`REQ-FIT-JOB-001`).
- Auto-split orphan resolution: split proposals, derived pieces, manual CAD path, and re-nest with updated pieces (`REQ-FIT-SPLIT-001`).
- Composite DXF layers: primary/auxiliary roles, clipped decorations in preview, layer-preserved nested output (`REQ-FIT-DXF-002`).
- **Modo Arquitecto en Pánico** (`:es_panic`) joke locale with EN/ES + panic switcher and full key parity with Spanish (`REQ-FIT-UI-005`).

- **Admin ventas / reporte de pagos:** `/admin/ventas` with filters, CRC/USD tables, Hacienda declaration summary, XLSX export, and `cabys_code` on payments (`REQ-FIT-ADMIN-001`).
- **Formulario 150 (IVA) export:** `GET /admin/ventas/exportar-formulario-150` — XLSX with «Soporte ventas» + «Formulario 150» (`SUMIFS` casillas Sección I); `paid_at` date filter; defaults to succeeded payments when status omitted (`REQ-FIT-ADMIN-001`).
- **Admin analytics & user bitácora:** `user_events` pipeline, `Analytics::TrackEvent` instrumentation across workshop/billing/auth, `/admin/analytics` KPI dashboard with conversion funnel and CSV export, `/admin/usuarios` search and per-user event timeline (`REQ-FIT-ANALYTICS-001`, ADR-0008).

### Changed

- **Parámetros iniciales removed:** `/projects/new` and monolithic «Continuar» step eliminated; ephemeral funnel is Inicio → EMPEZAR → `/taller`.
- **Mi taller panels:** setup mode opens sheet inventory and DXF detail; taller mode keeps panels collapsed by default; uploading DXF after a nest preserves the detail panel open.
- **Billing internals:** services use typed value objects at boundaries (no checkout API or JSON shape change).
- **Nesting internals:** workshop/nesting services use `Nesting::*` value objects at boundaries (`KerfMm`, `MarginMm`, `JobParameters`, `PieceKey`, etc.); `config.json` keys and HTTP shapes unchanged; invalid kerf/margin rejected before save (`REQ-FIT-NEST-002`, `REQ-FIT-DOM-001`).
- **Mis pagos:** late SINPE fulfillments after manual abandon appear in payment history again.
- **Checkout:** method-first ONVO checkout replaces simulated buttons when gateway is live; card 3DS cancel restores checkout with saved card draft (CVV not persisted); SINPE instructions step is transfer-only (correct data via Mis pagos cancel + new checkout).
- **Workshop during SINPE pending:** DXF upload, layer changes, and sheet inventory blocked server-side for active SINPE lock (`BlocksWorkshopDuringPendingPayment`).
- Paywall catalog at `/taller/descarga-pago` with inline plans and “Añadir al carrito”; checkout reads from the signed-in user’s cart.
- `/planes` redirects to checkout when the user already has a cart line.
- Overage prices use explicit amounts from `config/billing.yml` (not runtime percentage).
- Workshop **Mi taller** (`/taller`): sheet inventory and source DXF detail panels stay collapsed by default.
- Nested DXF download requires sign-in, confirmed email, and payment or active plan (preview and nesting progress remain free).
- Ephemeral workspace access without project PIN (ADR-0004).
- Locale switcher uses translated `aria-label` for the EN/ES group in all locales.

### Removed

- `/projects/new` setup page, `finish_ephemeral_setup`, and dead `/taller/edit` routes.
- Project PIN gate and related UI.
