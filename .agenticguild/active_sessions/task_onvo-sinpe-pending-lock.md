# Task: ONVO SINPE — bloqueo de taller con ventana (no eterno)

**Status:** Discovery in progress (explore-task Phase 1)  
**REQ:** REQ-FIT-BILL-001 (extend detail)  
**Related:** `task_onvo-payments.md` (gateway base locked); this task is a **follow-on UX/domain** slice on top of live ONVO.

---

## Problem

SINPE Móvil puede quedar en `Payment.pending` mucho tiempo (webhook tardío o nunca). Hoy `Billing::PendingCheckoutLock#active?` bloquea el taller mientras exista cualquier pending sin grant — efectivamente **eterno**.

Tarjeta: aprobación/rechazo inmediatos en práctica — **no** necesita ventana de bloqueo de taller.

---

## Decision log (2026-05-28)

| # | Topic | Decision |
|---|--------|----------|
| 1 | ¿15 min para tarjeta? | **No.** Ventana de bloqueo de taller solo para `payment_method: sinpe_crc`. Tarjeta no activa `checkout_lock_active?` (pending tarjeta no bloquea re-anidar). |
| 2 | “Cancelar intento” vs ONVO | **v1: solo local** — `ReleasePendingCheckoutLock` + `checkout_abandoned_at`; **no** `FailPayment`; **no** llamar ONVO cancel en v1. Copy fuerte: si ya transferiste, no canceles. **v2 opcional:** ONVO `POST /v1/payment-intents/{id}/cancel` solo en `SupersedePendingCheckout` (intent viejo reemplazado, usuario no pulsó cancel) — evaluar con sandbox. |
| 3 | Persistir `checkout_lock_released_at` | **Lazy on read** — calcular expiración con `created_at + workshop_lock_minutes`; primera consulta tras expirar puede persistir timestamp (auditoría). Sin job/cron en v1. |
| 4 | Pagos `superseded` en UI | **Dos secciones distintas en Mis pagos:** (a) **Descargas sueltas** — filas accionables (grant, confirmando, sin confirmar + CTAs); **excluir** superseded. (b) **Historial de pagos** — **incluir** superseded con etiqueta “Reemplazado” / “Intento reemplazado”. |

---

## Domain model

### Payment (extend)

**Responsibility:** Registro inmutable de intento de cobro; webhook autoritativo para terminal state.

**New columns (planned):**

- `checkout_lock_released_at` — taller desbloqueado (timeout, abandon, supersede)
- `checkout_abandoned_at` — usuario pulsó “Cancelar intento”
- `superseded_at` — otro checkout del mismo `nesting_run_id` lo reemplazó
- Optional: `checkout_lock_reason` (`timeout` \| `user_abandoned` \| `superseded`)

**Invariants:**

- Expirar bloqueo de taller **no** cambia `status` a `failed`
- Webhook `succeeded` → `FulfillPayment` aunque lock liberado o `checkout_abandoned_at` set
- Solo `sinpe_crc` + `pending` + sin grant + lock no liberado + dentro de ventana + no superseded → `checkout_lock_active?`
- Tarjeta pending (edge) → **no** workshop lock

**Value objects / branded:**

- `WorkshopLockWindow` — minutes from `billing.yml` `onvo_pending_checkout.workshop_lock_minutes` (default 15)
- `CheckoutLockReason` — enum for release/supersede audit

### Billing::PendingCheckoutPolicy (or Onvo::PendingCheckoutPolicy)

Reads config; answers `lock_expires_at(payment)`, `lock_active?(payment)`.

### Services

- `PendingCheckoutLock` — refactor `active?` to use `checkout_lock_active?`
- `ReleasePendingCheckoutLock` — manual abandon
- `SupersedePendingCheckout` — from `StartOnvoCheckout` before new pending
- `StartOnvoCheckout` — call supersede for same user+run

---

## Fulfillment UX (cancel / late webhook) — 2026-05-28

### ¿Puede descargar el anidado que intentó pagar?

**Sí**, si ONVO confirma (`payment-intent.succeeded`) y `FulfillPayment` corre con éxito:

1. `Payment` → `succeeded`
2. `DownloadGrant` para ese `nesting_run_id`
3. `RetainNestedDxf` copia `project.nested_dxf` → `grant.retained_nested_dxf` (24 h en Mis pagos, REQ-FIT-BILL-003 D54)

**No depende** de que el bloqueo de taller siga activo ni de que el usuario no haya pulsado “Cancelar intento”. `checkout_abandoned_at` solo libera el taller.

### ¿Guardamos el DXF durante pending?

**Hoy: no.** El snapshot ocurre **solo en fulfill** (`RetainNestedDxf` al webhook).

**Riesgo si re-anidó tras cancelar/timeout:** `nested_dxf` vive en `Project`; un re-nest puede **sobrescribir** el blob antes del webhook. El grant queda ligado al `nesting_run_id` del pago, pero la copia sería la del proyecto **actual** (posible DXF equivocado) o falla si ya no hay attachment.

**Recomendación v1.1 (documentar en SPEC / plan):** al iniciar checkout SINPE (`StartOnvoCheckout`), **pre-retener** copia en `DownloadGrant` (o attachment staging en `Payment`) del `nested_dxf` del run pagado — sin marcar pago succeeded. En fulfill: refrescar `retained_until` / re-copiar si hace falta. Alternativa mínima: en fulfill, si `project` ya tiene otro `nesting_run` más reciente que el del pago → no sobrescribir; fila Mis pagos “Pago confirmado — volvé a anidar para descargar” (peor UX).

### ¿Cómo se entera el usuario?

**Canales existentes (mantener + extender):**

| Canal | Comportamiento |
|-------|----------------|
| Poll `GET /checkout/pagos/:id/estado` | `PaymentStatusResponse` → si `succeeded` + grant → `redirect_url` a `/mis-pagos?payment_succeeded=1&auto_download=:grant_id` |
| `checkout/processing` | Poll ~60 s; luego copy + link Mis pagos |
| `mis_pagos` + Stimulus `mis-pagos-pending-sync` | Poll mientras hay pending **con lock activo** hoy — **ampliar** a `awaiting_gateway_confirmation?` (pending sin grant aunque lock expirado/abandonado) para redirect + auto-download |
| Flash | `billing.checkout.success_retention` al llegar con `payment_succeeded` |
| Auto-download | `auto-download` controller dispara descarga del grant |

**No hay email/push en v1.** Usuario debe abrir Mis pagos (o dejar pestaña con poll) o volver después del webhook.

**Copy nuevo (plan):** fila pasa a “Pago confirmado — Descargar”; opcional toast/email fuera de scope v1.

## Open questions (none blocking v1 if decision log stands)

- ¿Incluir pending SINPE expirado en `SinglePurchaseRows` aunque lock inactivo? → **Sí** (estado “Sin confirmar” + reintentar/cancelar).
- ¿Bloquear segundo checkout mientras lock activo? → **Sí** (solo ventana SINPE activa); permitir tras expirar/abandon/supersede.
- ¿Pre-retención DXF al start SINPE checkout? → **Recomendado** en plan (evita late-webhook + re-nest); no existe hoy.

---

## Implementation outline (draft — not locked)

Phases 0–7 per user roadmap (SPEC, migration, services, routes, UI, specs, QA). Adjusted: **SINPE-only lock** in `Payment#checkout_lock_active?` and `PendingCheckoutLock`.

---

## Scratchpad

- ONVO has `POST /v1/payment-intents/{id}/cancel` — defer to v2 for supersede-only.
- Current `superseded_by_successful_checkout?` stays; new `superseded_at` is for pending→pending replacement.
- `SinglePurchaseRows#active_pending_payments` today filters by lock active only — will need rows for expired pending too.
