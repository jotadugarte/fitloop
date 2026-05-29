# ADR-0006: ONVO live billing gateway

**Status:** Accepted  
**Date:** 2026-05-28  
**REQ:** REQ-FIT-BILL-001, REQ-FIT-BILL-002, REQ-FIT-BILL-003  
**Supersedes (partial):** ADR-0005 simulated-only payment capture — simulated paths remain for `BILLING_GATEWAY=simulate` in development.

## Context and problem statement

Fitloop billing v1 shipped **simulated checkout** (ADR-0005): demo success/fail buttons and synchronous fulfillment. Product now requires **live payment collection** via **ONVO** for Costa Rica (CRC, SINPE Móvil + card) and international clients (USD, card only), while preserving MEIC pricing, cart snapshots, and `Billing::CheckoutBreakdown` as the amount SSOT.

ONVO documents two integration styles; Fitloop chooses **Payment Intents + embedded SDK** on `/checkout` (no hosted Checkout redirect, no ONVO Subscriptions API for plan auto-renewal). Plans remain **one-time intents** per purchase; Fitloop entitlement model is unchanged.

## Decision drivers

- **D1:** Webhook-first fulfillment — do not grant nested DXF or extend plans until ONVO confirms (`payment-intent.succeeded`).
- **D2:** Amounts from `Billing::CheckoutBreakdown` only; ONVO `payment-intent` `amount` in **minor units** (CRC/USD).
- **D3:** Regional policy unchanged: CR → CRC + SINPE|card; non-CR → USD + card only (`Billing::RegionalPolicy`).
- **D4:** Idempotent fulfillment via `Billing::FulfillPayment` / `Billing::FailPayment` (shared with simulate services).
- **D5:** UX poll 2–3s (max ~60s) on processing screen; webhook remains authoritative.
- **D6:** Secrets via ENV (consistent with OAuth); no committed keys.

## Considered options

1. **ONVO hosted Checkout (one-time link)** — Rejected: leaves Fitloop MEIC breakdown and method-first UX.
2. **ONVO Subscriptions API** — Rejected: Fitloop plans are prepaid terms + monthly quota, not card-on-file recurring.
3. **Stripe** — Out of scope; ONVO is the Costa Rica–aligned provider for v1 live billing.

## Decision outcome

**Chosen:** ONVO Payment Intents + `sdk.onvopay.com` embedded pay; SINPE via `mobile_number` payment method; server webhook at `POST /webhooks/onvo`.

### Gateway selection

| `BILLING_GATEWAY` | Behavior |
|-------------------|----------|
| `simulate` | ADR-0005 demo buttons; `Billing::SimulateSingleDownload` / `Billing::SimulatePlanPurchase` |
| `onvo` | Live ONVO intents; simulate UI hidden |

### Environment variables

| Variable | Purpose |
|----------|---------|
| `BILLING_GATEWAY` | `simulate` \| `onvo` |
| `ONVO_MODE` | `test` \| `live` |
| `ONVO_SECRET_KEY` | Server API (`onvo_test_secret_*` / live) |
| `ONVO_PUBLISHABLE_KEY` | Client SDK |
| `ONVO_WEBHOOK_SECRET` | Verify inbound webhook (`X-Webhook-Secret` header) |

Local: `.env` gitignored. Staging/production: host ENV (e.g. Northflank). Dev webhooks: HTTPS tunnel (ngrok) registering `…/webhooks/onvo`.

### Payment flow (normative)

1. User confirms checkout → `Payment` row `pending` with snapshot from `CheckoutBreakdown`.
2. Server `POST /v1/payment-intents` (metadata: internal `payment_id`).
3. Client `onvo.pay({ publicKey, paymentIntentId, paymentType: "one_time", … })` for card; SINPE collects cédula + móvil, confirms intent, shows transfer instructions.
4. ONVO sends webhook `payment-intent.succeeded` \| `payment-intent.failed` → `POST /webhooks/onvo`.
5. `Billing::Onvo::VerifyWebhook` + `Billing::Onvo::HandleWebhookEvent` → `Billing::FulfillPayment` or `Billing::FailPayment` (idempotent).
6. Client `onSuccess` / 3DS `GET /checkout/retorno` → processing view only (no client-side grant).

### Webhook contract

- **Route:** `POST /webhooks/onvo` (CSRF skipped).
- **Auth:** `X-Webhook-Secret` must match `ONVO_WEBHOOK_SECRET`.
- **Events (v1):** `payment-intent.succeeded`, `payment-intent.failed` (handle `payment-intent.deferred` as processing).
- **Idempotency:** duplicate events for an already terminal `Payment` return 200 without double grant.

### Positive consequences

- Aligns with ONVO best practice (confirm before digital delivery).
- Reuses cart, MEIC breakdown, retention, and quota models from ADR-0005.
- `simulate` preserved for CI and offline dev.

### Negative consequences

- Requires public HTTPS for webhook testing (staging/ngrok).
- SINPE UX complexity (identification fields, processing state).
- No refunds in v1.

## Implementation notes

- **Rails only** — no payment logic in Python (`nesting_engine`).
- **Reference:** `onvo/docs-completa-onvo.txt`, https://docs.onvopay.com
- **3DS return:** `/checkout/retorno`
- **Status poll:** `GET /checkout/pagos/:id/estado` (JSON from DB, not grant until `succeeded`)

## Validation

- `AuthBillingSpecDocVerifier` includes ADR-0006 and ONVO markers in `REQ-FIT-BILL-001 (detail)`.
- Request specs for webhook, checkout pay, and processing poll (implementation plan P3–P7).

## More information

- Extends: `docs/core/ADRs/0005-user-accounts-and-simulated-billing.md` (accounts, cart, grants — not superseded)
- Requirements: `docs/core/SPEC.md` (`REQ-FIT-BILL-001`..`003`)
- Session plan: `.agenticguild/active_sessions/task_onvo-payments.md`
