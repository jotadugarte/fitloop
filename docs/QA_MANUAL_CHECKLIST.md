# Fitloop — manual QA checklist (MVP v1)

**Requirement:** [REQ-FIT-QA-001](core/SPEC.md)  
Use after automated specs are green. Record date, tester, and environment.

## Environment

- [ ] PostgreSQL running; `bin/rails db:migrate` applied
- [ ] `.venv` active; `pip install -r nesting_engine/requirements.txt` done
- [ ] `bin/dev` or `bin/rails server` + Solid Queue worker running

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
