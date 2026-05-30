# Task: ONVO SINPE — bloqueo de taller con ventana (no eterno)

**Status:** Spec locked — handoff to `start-task`  
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
| 5 | Pre-retención DXF (SINPE) | **Sí, v1.** Al `StartOnvoCheckout` con `sinpe_crc`: `find_or_initialize` `DownloadGrant` + copiar blob; **`retained_until` nil** hasta fulfill (relajar validación `presence` en single_purchase staging). Fila Mis pagos: **no** Descargar mientras el pago del run no esté `succeeded`. `FulfillPayment`: `retained_until = paid_at + 24h`. |
| 6 | Webhook `failed` + pre-retención | **Sí purgar.** En `FailPayment` (o rama failed del webhook): si grant tiene `retained_nested_dxf` pero **sin** `retention_active?` (nunca hubo fulfill), `purge_retained_blob!`. Pago queda `failed`; sin DXF huérfano en storage. |

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
- Solo `sinpe_crc` + `pending` + sin grant **descargable** + lock no liberado + dentro de ventana + no superseded → `checkout_lock_active?`  
  (grant con `retained_nested_dxf` por pre-retención **no** cuenta como “fulfilled” para lock ni para `downloadable?`)
- Tarjeta pending (edge) → **no** workshop lock
- Pre-retención: grant puede tener blob antes de `succeeded`; `retained_until` **nil** hasta fulfill → `retention_active?` es **false** → no Descargar
- Webhook failed: purgar blob de pre-retención (decisión #6)

**Value objects / branded:**

- `WorkshopLockWindow` — minutes from `billing.yml` `onvo_pending_checkout.workshop_lock_minutes` (default 15)
- `CheckoutLockReason` — enum for release/supersede audit

### Billing::PendingCheckoutPolicy (or Onvo::PendingCheckoutPolicy)

Reads config; answers `lock_expires_at(payment)`, `lock_active?(payment)`.

### Services

- `PendingCheckoutLock` — refactor `active?` to use `checkout_lock_active?`
- `ReleasePendingCheckoutLock` — manual abandon
- `SupersedePendingCheckout` — from `StartOnvoCheckout` before new pending
- `StartOnvoCheckout` — call supersede for same user+run; SINPE → `Billing::PreRetainNestedDxf` (new) after pending payment created
- `PreRetainNestedDxf` — grant + copy blob; no `retained_until` until fulfill

---

## Fulfillment UX (cancel / late webhook) — 2026-05-28

### ¿Puede descargar el anidado que intentó pagar?

**Sí**, si ONVO confirma (`payment-intent.succeeded`) y `FulfillPayment` corre con éxito:

1. `Payment` → `succeeded`
2. `DownloadGrant` para ese `nesting_run_id`
3. `RetainNestedDxf` copia `project.nested_dxf` → `grant.retained_nested_dxf` (24 h en Mis pagos, REQ-FIT-BILL-003 D54)

**No depende** de que el bloqueo de taller siga activo ni de que el usuario no haya pulsado “Cancelar intento”. `checkout_abandoned_at` solo libera el taller.

### ¿Guardamos el DXF durante pending?

**v1: sí (SINPE only).** `PreRetainNestedDxf` al iniciar checkout; fulfill solo activa ventana 24h y confirma pago. Re-nest no borra lo que el usuario intentó pagar.

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

## Closed (v1)

- Pending SINPE expirado en `SinglePurchaseRows` → **Sí** (“Sin confirmar” + CTAs).
- Segundo checkout SINPE con lock activo → **bloquear** (aviso + link Mis pagos).
- Pre-retención SINPE → **Sí** (decisión #5).
- Notificación pago → poll + Mis pagos; **sin** email/push v1.
- ONVO cancel API → **v2** (supersede opcional).

---

---

## UX rule (plain language) — pre-retención vs descarga

Hoy **“podés descargar”** = `DownloadGrant` con `retained_until` en el futuro (`retention_active?`).

Con pre-retención copiamos el DXF **antes** de que ONVO confirme el pago. Eso **no** es “ya pagaste”:

| Estado del pago | Blob en grant | `retained_until` | ¿Botón Descargar? | ¿Bloquea taller? (SINPE) |
|-----------------|---------------|------------------|-------------------|---------------------------|
| `pending` (confirmando) | sí (copia guardada) | `nil` | **No** | Sí, si &lt;15 min y lock activo |
| `succeeded` | sí | `paid_at + 24h` | **Sí** | No |
| `failed` | purgado | — | No | No |

**Por qué importa:** sin `retained_until`, `downloadable?` ya es false. `PendingCheckoutLock` hoy deja de bloquear si `grant.retention_active?` — con pre-retención **no** habrá `retention_active?` hasta fulfill, así que el lock sigue gobernado por el pago pending (correcto).

`SinglePurchaseRows`: la fila visible durante pending es la del **pago** (“Confirmando…” / “Sin confirmar”), no una fila de descarga lista.

---

## Scratchpad

- ONVO has `POST /v1/payment-intents/{id}/cancel` — defer to v2 for supersede-only.
- Current `superseded_by_successful_checkout?` stays; new `superseded_at` is for pending→pending replacement.
- `SinglePurchaseRows#active_pending_payments` today filters by lock active only — will need rows for expired pending too.

---

<implementation_plan>
  <meta>
    <task_slug>onvo-sinpe-pending-lock</task_slug>
    <branch_name_suggestion>feat/onvo-sinpe-pending-lock</branch_name_suggestion>
    <classification>Feature</classification>
    <req_ids>
      <req>REQ-FIT-BILL-001</req>
      <req>REQ-FIT-BILL-003</req>
    </req_ids>
    <constraints>
      <constraint>SINPE-only workshop lock (15 min default); card pending never blocks workshop.</constraint>
      <constraint>Workshop lock ≠ payment status; timeout/abandon does not mark payment failed.</constraint>
      <constraint>Webhook authoritative: FulfillPayment / FailPayment unchanged contract; late succeeded after abandon still grants.</constraint>
      <constraint>Pre-retention at SINPE checkout start; retained_until only on fulfill; purge staging blob on FailPayment.</constraint>
      <constraint>CheckoutBreakdown SSOT; no payment logic in Python; Rails billing only (SYSTEM_ARCHITECTURE §10).</constraint>
      <constraint>Lock release lazy on read; optional persist checkout_lock_released_at on first expired read.</constraint>
      <constraint>Cancel intent v1 local only; no ONVO cancel API until v2.</constraint>
      <constraint>i18n es + en + es_panic parity; AuthBillingSpecDocVerifier / locale_key_parity_spec.</constraint>
      <constraint>Service specs: RSpec.describe ClassName, "[REQ-ID]" constant.</constraint>
    </constraints>
    <manual_qa>docs/QA_ONVO_SINPE.md, docs/QA_MANUAL_CHECKLIST.md</manual_qa>
  </meta>

  <phase id="P0" name="Anchors &amp; configuration">
    <step id="0.1" status="complete">Write failing spec (or extend `auth_billing_spec_doc_test` / billing doc verifier) asserting REQ-FIT-BILL-001 documents: SINPE workshop lock window, abandon without fail, late webhook fulfill, pre-retention, failed webhook purge.</step>
    <step id="0.2" status="complete">Update `docs/core/SPEC.md` REQ-FIT-BILL-001 detail with pending-checkout lock rules (reference decision log in task file).</step>
    <step id="0.3" status="complete">Add `config/billing.yml` key `onvo_pending_checkout.workshop_lock_minutes: 15`; implement `Billing::PendingCheckoutPolicy` (read config, `lock_expires_at`, `lock_active?`).</step>
    <step id="0.4" status="complete">Add i18n keys under `billing.checkout.pending_lock.*`, `billing.mis_pagos.pending_*`, `billing.mis_pagos.superseded`, abandon confirm copy — `es.yml`, `en.yml`, `es_panic.yml`; run/fix `spec/i18n/locale_key_parity_spec.rb`.</step>
    <step id="0.5" status="complete">Update `docs/QA_ONVO_SINPE.md` (88889521 → 15 min workshop unlock) and `docs/QA_MANUAL_CHECKLIST.md` (timeout, manual cancel, late webhook, failed purge).</step>
  </phase>

  <phase id="P1" name="Persistence &amp; Payment model">
    <step id="1.1" status="complete">Write failing model spec: `Payment#checkout_lock_active?` true only for `sinpe_crc` pending within window; false for card; false after timeout lazy release; false when superseded/abandoned.</step>
    <step id="1.2" status="complete">Migration: add `checkout_lock_released_at`, `checkout_abandoned_at`, `superseded_at` (optional `checkout_lock_reason`) to `payments`.</step>
    <step id="1.3" status="complete">Implement `Payment` methods: `checkout_lock_active?`, `checkout_lock_expired?`, `awaiting_gateway_confirmation?`, `superseded?`; delegate window to `PendingCheckoutPolicy`.</step>
    <step id="1.4" status="complete">Write failing model spec: `DownloadGrant` allows `retained_until` nil for single_purchase staging (pre-retention); still requires `retained_until` after fulfill path.</step>
    <step id="1.5" status="complete">Relax `DownloadGrant` validation: `retained_until` required only when `retention_committed?` or when `retention_active?` would be true — document invariant in model comment.</step>
  </phase>

  <phase id="P2" name="Lock services">
    <step id="2.1" status="complete">Write failing `pending_checkout_lock_spec`: active &lt;15 min SINPE; inactive &gt;15 min; inactive after abandon; inactive card pending; inactive when superseded; late webhook grant does not re-lock.</step>
    <step id="2.2" status="complete">Refactor `Billing::PendingCheckoutLock#active?` to use `payment.checkout_lock_active?` (not raw pending); lazy-persist `checkout_lock_released_at` on timeout via `ReleasePendingCheckoutLock` or policy helper.</step>
    <step id="2.3" status="complete">Write failing `release_pending_checkout_lock_spec`: manual abandon sets `checkout_abandoned_at` + `checkout_lock_released_at`; does not change `status`.</step>
    <step id="2.4" status="complete">Implement `Billing::ReleasePendingCheckoutLock`.</step>
    <step id="2.5" status="complete">Write failing `supersede_pending_checkout_spec`: marks older pending same run `superseded_at` + releases lock.</step>
    <step id="2.6" status="complete">Implement `Billing::SupersedePendingCheckout`; wire into `Billing::StartOnvoCheckout` before `create_pending_payment!`.</step>
  </phase>

  <phase id="P3" name="Pre-retention &amp; fulfillment">
    <step id="3.1">Write failing `pre_retain_nested_dxf_spec`: SINPE start copies blob; `retained_until` nil; raises if nested_dxf missing.</step>
    <step id="3.2">Implement `Billing::PreRetainNestedDxf`; call from `StartOnvoCheckout` when `payment_method == sinpe_crc` after pending payment created.</step>
    <step id="3.3">Write failing `fulfill_payment_spec`: late succeed after abandon still grants; sets `retained_until`; skips re-copy if blob present.</step>
    <step id="3.4">Adjust `FulfillPayment` / `RetainNestedDxf` for staging grant (set `retained_until` on fulfill; copy only if blob missing).</step>
    <step id="3.5">Write failing `fail_payment_spec`: failed webhook purges pre-retained blob (no `retention_active?`); does not purge fulfilled grant.</step>
    <step id="3.6">Implement purge in `Billing::FailPayment` for staging grants tied to payment's `nesting_run_id`.</step>
    <step id="3.7">Write failing webhook/request spec: abandoned payment + late `payment-intent.succeeded` → grant + download.</step>
  </phase>

  <phase id="P4" name="HTTP &amp; checkout guard">
    <step id="4.1">Write failing request spec: `POST /checkout/pagos/:id/liberar` releases lock (owner only); payment stays pending.</step>
    <step id="4.2">Add route + `CheckoutController#release_pending_lock` → `ReleasePendingCheckoutLock`.</step>
    <step id="4.3">Write failing request spec: duplicate SINPE checkout blocked while `checkout_lock_active?`; allowed after timeout/abandon.</step>
    <step id="4.4">Guard `StartOnvoCheckout` / checkout pay action when lock active (flash + redirect Mis pagos).</step>
    <step id="4.5">Write failing request specs: workshop mutations blocked during active SINPE lock; allowed after 15 min travel; allowed after POST liberar.</step>
  </phase>

  <phase id="P5" name="Status poll API">
    <step id="5.1">Write failing `payment_status_response_spec`: JSON includes `checkout_lock_active`, `checkout_lock_expired`, `release_pending_url`, `retry_checkout_url`.</step>
    <step id="5.2">Extend `Billing::PaymentStatusResponse` and `checkout_payment_status` route auth.</step>
    <step id="5.3">Write failing request spec: Mis pagos sets `pending_payment_status_url` when `awaiting_gateway_confirmation?` even if lock expired.</step>
    <step id="5.4">Update `MisPagosController` + `mis_pagos_pending_sync_controller.js` to poll until succeeded/failed and reload on lock expired.</step>
  </phase>

  <phase id="P6" name="Mis pagos &amp; workshop UI">
    <step id="6.1">Write failing `single_purchase_rows_spec`: rows for lock-active pending, expired pending with CTAs, excludes superseded; grant row only when `retention_active?`.</step>
    <step id="6.2">Refactor `Billing::MisPagos::SinglePurchaseRows` for pending states; payment history shows superseded label.</step>
    <step id="6.3">Update `_single_purchase_row.html.erb`, `_pending_payment_lock_banner.html.erb`, `checkout/processing.html.erb`, Mis pagos section title locale.</step>
    <step id="6.4">CSS modifiers `--pending-awaiting` vs `--pending-unconfirmed`; no false Descargar button.</step>
  </phase>

  <phase id="P7" name="Regression">
    <step id="7.1">Run billing-related specs (`pending_checkout_lock`, checkout, mis_pagos, webhook, fulfill/fail); fix regressions.</step>
    <step id="7.2">Tag new/modified root request `RSpec.describe` with `[REQ-FIT-BILL-001]` where applicable.</step>
  </phase>
</implementation_plan>
