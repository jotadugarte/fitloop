# ONVO SINPE Móvil — manual QA (test mode)

**Requirements:** [REQ-FIT-BILL-001](core/SPEC.md), [ADR-0006](core/ADRs/0006-onvo-live-billing.md)  
**ONVO source (local mirror):** `onvo/docs-completa-onvo.txt` → section *Pruebas* → *SINPE Móvil* ([docs.onvopay.com/payments/testing#sinpe-móvil](https://docs.onvopay.com/payments/testing#sinpe-móvil))

Use with `BILLING_GATEWAY=onvo`, `ONVO_MODE=test`, and `onvo_test_*` API keys. Test payment methods **do not work** with `onvo_live_*` keys.

## Prerequisites

- [ ] `bin/rails db:migrate` applied; app + Solid Queue running
- [ ] `.env`: `BILLING_GATEWAY=onvo`, `ONVO_MODE=test`, `ONVO_SECRET_KEY`, `ONVO_PUBLISHABLE_KEY`, `ONVO_WEBHOOK_SECRET`
- [ ] Webhook reachable: ngrok → `POST /webhooks/onvo` registered in ONVO test dashboard (see [DEPLOY.md](DEPLOY.md#onvo-webhooks-in-local-development))
- [ ] Logged-in, **confirmed** user; completed nest with paywalled download (or plan cart)
- [ ] Checkout country **CR** so SINPE (CRC) is offered

## Fitloop flow (SINPE)

1. `GET /checkout` → choose **SINPE Móvil (CRC)** → **Procesar pago** (`POST /checkout/pagar`).
2. Fill **cédula** (`sinpe_identification`) and **teléfono móvil del transferente** (`sinpe_mobile_number`) — this becomes ONVO `mobile_number` (see `Billing::Onvo::ConfirmSinpePayment`).
3. Submit SINPE confirm → instructions show destination **+506 70196686** and exact amount from `CheckoutBreakdown`. The checkout **stays on this screen** until you click **“Ya hice la transferencia, continuar”**.
4. After **Continue**, app opens **`/checkout/procesando/:id`** (poll ~2.5s, max 60s). **Do not** grant download until `payment-intent.succeeded` webhook (or poll shows `succeeded`).
5. In **test mode**, ONVO simulates the transfer from the **mobile number** you enter — **no real SINPE transfer** to ONVO’s number is required (you may click Continue immediately after reading instructions).

## ONVO test numbers (SINPE Móvil)

Enter the **Número** in Fitloop’s *teléfono móvil del transferente*. Use any plausible **cédula** unless you are testing SINPE PIN (not used in Fitloop v1).

| Escenario | Número (E.164) | Comportamiento ONVO (test) | Qué verificar en Fitloop |
| --- | --- | --- | --- |
| Exitoso | `+50688888888` | Transferencia simulada correcta ~**15 s** después de confirmar la intención | Processing → éxito; `Payment` `succeeded`; `DownloadGrant` (single) o plan activo; flash / Mis pagos |
| Exitoso con retraso | `+50688884444` | Transferencia correcta ~**6 min** después | Processing puede hacer **timeout 60 s** en UI; webhook tardío debe completar fulfillment; recargar Mis pagos si hace falta |
| Fallido | `+50688889521` | **No** simula transferencia; la intención **no cambia de estado** | Tras timeout, copy “confirmando…”; `Payment` sigue `pending`; sin grant; reintentar con número exitoso |
| Parcial | `+50688883333` | Simula **50%** y luego el **50%** restante | Observar estados intermedios vía webhook/poll; no marcar éxito hasta `succeeded` total |

**Formato en el formulario:** Fitloop normaliza a E.164 (`+506…`). Acepta `88888888` o `+50688888888` si el campo lo permite.

## Webhook & failure

- [ ] `payment-intent.succeeded` → fulfillment idempotente (segunda entrega no duplica grant).
- [ ] Forzar fallo vía tarjeta `4000000000000002` o webhook `payment-intent.failed` en sandbox — `Payment` `failed`, snapshot financiero intacto (ver spec `webhooks/onvo_spec`).

## Sign-off (SINPE slice)

| Field | Value |
|-------|--------|
| Date | |
| Tester | |
| `ONVO_MODE` | test |
| Webhook URL | |
| Número probado | |
| Resultado | |

**Next:** full ONVO QA (tarjeta 3DS, ngrok, processing) → `docs/QA_MANUAL_CHECKLIST.md` (task P10.2).
