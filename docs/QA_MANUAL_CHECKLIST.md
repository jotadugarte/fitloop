# Fitloop — manual QA checklist (MVP v1)

**Requirement:** [REQ-FIT-QA-001](core/SPEC.md)  
Use after automated specs are green. Record date, tester, and environment.

## Environment

- [ ] PostgreSQL running; `bin/rails db:migrate` applied
- [ ] `.venv` active; `pip install -r nesting_engine/requirements.txt` done
- [ ] `bin/dev` or `bin/rails server` + Solid Queue worker running
- [ ] **ONVO QA only:** `.env` has `BILLING_GATEWAY=onvo`, `ONVO_MODE=test`, `ONVO_SECRET_KEY`, `ONVO_PUBLISHABLE_KEY`, `ONVO_WEBHOOK_SECRET` (see [DEPLOY.md](DEPLOY.md) and [ADR-0006](core/ADRs/0006-onvo-live-billing.md))

## Workspace & access

- [ ] `GET /` shows Fitloop home and logo
- [ ] `GET /projects` redirects to workspace start (`/empezar`) — no saved-project list
- [ ] `GET /empezar` creates an ephemeral workspace and shows setup (no PIN field)
- [ ] Complete setup (title, sheet stock, DXF, layers) → project show page loads
- [ ] Opening another project URL without session bind redirects to start with expired message
- [ ] Returning home discards the workspace project (session cleared)

## DXF inputs

- [ ] Upload one or more DXFs; layer checklist shows union of layer names
- [ ] Pre-flight blocks nest when no layers selected (i18n error)
- [ ] Pre-flight blocks nest when zero extractable pieces on selected layers

## Nesting job

- [ ] Start nesting → progress updates; completes with `completed` or `partial` as expected
- [ ] Golden sample (`spec/fixtures/golden/sample_piece.dxf`, layer `PIECES`, sheet ≥ 200×100 mm) → **completed**, download link present
- [ ] Oversized piece on tiny sheet → **partial**, orphan listed in report, download still offered
- [ ] Cancel during processing stops job (when applicable)
- [ ] Re-nest creates new run; history lists prior runs; download reflects latest result

## Outputs

- [ ] Download nested DXF opens in CAD viewer; sheets offset on +X
- [ ] SVG preview sheet count matches `placements.json`
- [ ] Locales `en` / `es` / `es_panic` show translated UI strings (spot-check billing + auth nav)

## Auth & accounts [REQ-FIT-AUTH-002]

- [ ] Header shows **Iniciar sesión** / **Crear cuenta** when logged out (Spanish routes)
- [ ] Register with name, terms checkbox, password ≥12 chars; confirmation email sent (or stub in dev)
- [ ] Unconfirmed user can browse workshop but `GET /checkout` and `GET /planes` redirect to `/confirmacion-pendiente`
- [ ] Login mid-workflow returns to the same ephemeral project (`session[:workspaces]` tab bind)
- [ ] Logout with active project shows confirm; discard clears workshop session
- [ ] `/mi-cuenta` profile loads; link to **Mis pagos** works

## Billing (simulated) [REQ-FIT-BILL-001..003]

Requires `BILLING_GATEWAY=simulate` (default dev). Demo **Pago exitoso** / **Pago fallido** buttons must be visible on checkout.

- [ ] Nested DXF download without grant/plan → paywall `/projects/:id/descarga-pago` with links to checkout, planes, login
- [ ] Preview (`placements.json`, SVG) remains free without payment
- [ ] `GET /checkout?nesting_run_id=…` shows demo badge and **Pago exitoso** / **Pago fallido** for Tarjeta (USD) and SINPE (CRC)
- [ ] Paywall hides SINPE option when `CF-IPCountry != CR` (only Card is offered)
- [ ] Paywall with **no downloadable run** shows plans inline and does not show single-download CTAs
- [ ] Paywall with **plan quota** shows “Descargar con tu plan” CTA and hides pay-this-download CTA
- [ ] Checkout hides SINPE when `CF-IPCountry != CR`
- [ ] Checkout breakdown shows Subtotal, IVA, Total; SINPE shows “Descuento SINPE”
- [ ] Checkout renders explicit overage prices hint (“Con cupo de plan agotado (50%)”)
- [ ] Guest adds to cart, then signs in: cart persists and merges to the user (guest cart removed)
- [ ] Successful single purchase auto-downloads nested DXF; flash mentions 24 h in Mis pagos
- [ ] After closing workshop (>2 min idle or logout discard), `GET /mis-pagos` lists the purchase with **Descargar** while within 24 h
- [ ] `GET /mis-pagos/descargas/:id` downloads retained DXF without workshop session bind
- [ ] After `retained_until` passes, download returns 403 with retention-expired copy (no blob)
- [ ] `GET /planes` shows tiers 1 / 2 / 4 months; simulated purchase redirects back to project show
- [ ] Plan active + quota: project show shows “Incluido en tu plan”; download works while project bound
- [ ] Plan download blocked after workshop TTL or discard (must re-nest)
- [ ] Suspended user (`users.suspended_at`) cannot complete checkout or download

## Billing (ONVO live, test mode) [REQ-FIT-BILL-001]

Requires `BILLING_GATEWAY=onvo`, `ONVO_MODE=test`, and `onvo_test_*` keys. Checkout must **not** show simulate success/fail buttons; use **Procesar pago** and the ONVO SDK / SINPE form instead. Fulfillment is **webhook-first** — do not expect download until `payment-intent.succeeded` (processing poll is UX only).

Reference: [ADR-0006](core/ADRs/0006-onvo-live-billing.md), ONVO test methods in `onvo/docs-completa-onvo.txt` (*Pruebas*).

### Webhook (ngrok or staging)

- [ ] Tunnel running (`ngrok http 3000` or fixed Northflank URL)
- [ ] ONVO test dashboard webhook URL = `https://<host>/webhooks/onvo` with secret matching `ONVO_WEBHOOK_SECRET`
- [ ] Rails restarted after ENV changes; ngrok inspector `http://127.0.0.1:4040` shows `payment-intent.succeeded` / `failed` deliveries
- [ ] See [DEPLOY.md — ONVO webhooks in local development](DEPLOY.md#onvo-webhooks-in-local-development)

### Checkout — card (CRC / USD)

- [ ] `GET /checkout` → **Procesar pago** creates pending `Payment` + intent (no grant yet)
- [ ] ONVO SDK loads (`sdk.onvopay.com`); card panel visible for `card_*` methods
- [ ] **Approved:** Visa `4242424242424242` (any future expiry, any CVV) → redirect `/checkout/procesando/:id` → success within ~60s poll → download / Mis pagos
- [ ] **3DS challenge:** `4000000000003220` → complete auth → browser may hit `/checkout/retorno?payment_intent_id=…` → processing page → success after webhook
- [ ] **Declined:** `4000000000000002` → `Payment` `failed`; financial snapshot unchanged; no `DownloadGrant`

### Checkout — SINPE Móvil (CRC, Costa Rica)

- [ ] SINPE visible when geo is CR; form collects cédula + teléfono móvil del transferente
- [ ] After confirm: instructions show destination **+506 70196686** and exact breakdown total
- [ ] **Success (fast):** móvil `+50688888888` — no real transfer needed in test mode; ~15s to `succeeded`
- [ ] **Delayed:** `+50688884444` — may exceed 60s processing UI; verify webhook still fulfills (reload Mis pagos)
- [ ] **No transfer simulated:** `+50688889521` — stays pending after poll timeout
- [ ] Full SINPE scenario table: [QA_ONVO_SINPE.md](QA_ONVO_SINPE.md)

### Processing screen & failures

- [ ] `/checkout/procesando/:id` polls `GET /checkout/pagos/:id/estado` every ~2.5s (max ~60s)
- [ ] On `succeeded`, redirect to Mis pagos (or workshop per product rules); nested DXF downloadable
- [ ] On long pending, “confirmando…” copy shown; user can check Mis pagos later after webhook
- [ ] `payment-intent.failed` webhook marks payment failed without wiping snapshot fields

## Security & ops

- [ ] No PIN or admin-unlock UI in the app
- [ ] No nesting math errors surfaced as 500 without flash/message

## Sign-off

| Field | Value |
|-------|--------|
| Date | |
| Tester | |
| Commit / branch | |
| Notes | |
