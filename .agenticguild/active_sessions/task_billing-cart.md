# Task: Billing cart UX (single-item) + MEIC pricing display

**Created:** 2026-05-27  
**Status:** Execution planning (refactor checkout flow ordering + Hotwire dynamics)
**Related:** `REQ-FIT-BILL-001` / `REQ-FIT-BILL-002`. ONVO re-explore later (after cart).

---

## Agreed decisions (full)

| # | Topic | Decision |
|---|--------|----------|
| D1 | **Alcance v1** | Carrito + MEIC UX + IVA; pago **simulado**; checkout lee carrito. |
| D2 | **IVA** | 13% sumado; **solo en checkout** (Q-IVA **B**). Carrito: subtotal lista + tip SINPE, sin IVA. Base imponible = neto tras descuento SINPE (si aplica) antes de IVA. |
| D3–D5 | Moneda dual, IP default, redondeo | CR→CRC/SINPE; fuera→USD/card; selector manual; CRC entero, USD 2 dec. |
| D6–D8 | Carrito | Reemplazo con confirmación; persiste DB; invitado añade, checkout con cuenta. |
| D9–D11 | Paywall | Cupo plan→descarga directa; overage 50% en lista; sin run→solo planes. |
| D12 | `/planes` | 301 → `/carrito` si ítem; si no → `/taller/descarga-pago`. |
| D13 | Post-pago | Igual que hoy (mis-pagos / taller). |
| D15 | Login merge | **Carrito del usuario** gana. |
| D16 | Geo | `CF-IPCountry` + GeoLite2 fallback. |
| D17 | Snapshot | Al añadir; refresh si cambia moneda. |
| D18 | Planes | 3 tiers; extensión desde `ends_at`; badge plan activo. |
| D20 | **Payment snapshot** | Nombre, email, producto, list_price, discount_amount, subtotal, tax, total, method, currency — **succeeded y failed** (D24). |
| D21 | Carrito plan | Fecha vencimiento **proyectada** (referencia). |
| D22 | **Descuento MEIC** | `list_price` = precio **tarjeta** (oficial). `discount_amount` = promoción SINPE (list − sinpe) cuando método SINPE; **adicional** línea overage 50% en descarga suelta cuando aplique (ver Q-OVERAGE). |
| D23 | Admin UI | **Fuera de scope** — ítem en `docs/ROADMAP.md` backlog “Admin ventas”. |
| D24 | Pagos fallidos | **Sí** — mismo snapshot financiero en `failed`. |

---

## MEIC pricing UX (D25 — owner spec 2026-05-27)

### A) Paywall `/taller/descarga-pago` (catálogo)

- **Protagonista:** precio SINPE (CRC) grande + copy “precio especial con SINPE Móvil”.
- **Referencia:** precio tarjeta más pequeño o tachado (“precio regular con tarjeta”).
- Aplica a descarga suelta (si hay run) y a los 3 planes.
- **USD (extranjero):** solo precio tarjeta/USD (sin SINPE); sin copy MEIC SINPE.

### B) Carrito `/carrito` (resumen)

- **Subtotal siempre = precio lista tarjeta** (snapshot en moneda del selector).
- **No** aplicar descuento SINPE aquí (evita sensación de subida de precio en checkout).
- Copy destacado: “💡 Ahorra ₡X pagando con SINPE Móvil en el siguiente paso.”
- Plan: mostrar **vencimiento proyectado** (D21).
- IVA en carrito: ver Q-IVA (¿sobre lista o solo en checkout?).

### C) Checkout `/checkout` (método de pago)

Desglose **dinámico** (Stimulus/Turbo) al elegir método:

**Tarjeta:**
```
Subtotal:     ₡5,000  (lista)
IVA 13%:      ₡650
Total:        ₡5,650
```

**SINPE (promoción):**
```
Subtotal:           ₡5,000
Descuento SINPE:    -₡500
Subtotal neto:      ₡4,500   (o omitir línea si subtotal neto = subtotal − descuento)
IVA 13%:            ₡585     (sobre neto — confirmar)
Total:              ₡5,085
```

- Copy: “🔥 Promoción aplicada” en SINPE; **nunca** “recargo por tarjeta”.
- Simular pago persiste snapshot con líneas reales cobradas.

### Pricing source

- `billing.yml`: mantener pares **card (lista)** + **sinpe** por producto; `Billing::Pricing.list_for(product)` / `.sinpe_for(product)`.
- Overage 50%: lista = mitad del precio oficial; SINPE = mitad del sinpe (D34) — **coincide** con tabla owner (₡600/₡500).

### Canonical CRC prices (D26 — owner 2026-05-27)

| Producto | Precio oficial (tarjeta) CRC | Ahorra (SINPE) | Precio final SINPE CRC |
|----------|------------------------------|----------------|-------------------------|
| Descarga única | 1,200 | 200 | 1,000 |
| Plan 1 mes | 3,250 | 250 | 3,000 |
| Plan 2 meses | 5,300 | 300 | 5,000 |
| Plan 4 meses | 8,400 | 400 | 8,000 |
| Descarga overage | 600 | 100 | 500 |

**Verificación:** oficial − ahorra = SINPE en todos los casos. Overage = 50% de descarga normal (1200→600, 1000→500).

**Gap vs `billing.yml` hoy:** solo hay `*_sinpe_crc` para planes; tarjeta en planes es **USD** (`plan_*_card_usd`). Falta `*_official_crc` (lista tarjeta en colones) para MEIC en CR. Overage hoy se **calcula** con `plan_quota_overage_percent: 50` — alinear keys explícitas o mantener cálculo (mismo resultado con tabla nueva).

**USD:** owner no entregó tabla USD en este mensaje — pendiente (Q-USD).

### Canonical USD prices (D27 — owner 2026-05-27)

Fixed USD price ladder (edit in config later; no FX in v1 simulated).

| Producto | Precio oficial (tarjeta) USD | Ahorra (SINPE) | Precio final SINPE USD |
|----------|------------------------------|----------------|-------------------------|
| Descarga única | 2.50 | 0.50 | 2.00 |
| Descarga overage | 1.25 | 0.25 | 1.00 |
| Plan 1 mes | 7.00 | 0.50 | 6.50 |
| Plan 2 meses | 11.50 | 1.00 | 10.50 |
| Plan 4 meses | 18.00 | 1.00 | 17.00 |

**Verificación:** oficial − ahorra = SINPE en todos los casos. Overage = 50% de descarga normal (2.50→1.25, 2.00→1.00).

### Overages: amounts, not percent (D28 — owner 2026-05-27)

Stop relying on `plan_quota_overage_percent` for pricing display and checkout math. Use explicit overage prices from tables:

- CRC overage: 600 / 500
- USD overage: 1.25 / 1.00

---

## Architecture (unchanged core)

```
/taller/descarga-pago → POST /carrito → GET /carrito → GET /checkout → POST /checkout/simular
```

- `Billing::CartTotals` — list subtotal for cart page; full breakdown for checkout by `payment_method`.
- `Billing::PlanExpiryPreview` — projected `ends_at`.
- Extend `payments` columns for admin snapshot (all statuses).

---

## Domain Model

### `Cart`

- `kind`, `nesting_run_id` | `tier_months`
- Snapshot: `list_price_*`, `sinpe_price_*`, `currency_mode`, `overage` boolean
- `guest_token` | `user_id`

### `Payment` (extended)

Immutable at attempt time: `purchaser_name`, `purchaser_email`, `product_description`, `list_price`, `discount_amount`, `subtotal`, `tax_amount`, `total_amount` (+ existing `amount`, `status`, `payment_method`, `currency`)

---

## Open questions (blocking SPEC)

| ID | Question | Status |
|----|----------|--------|
| Q-IVA | IVA solo en checkout | **Closed — B** |
| Q-OVERAGE | Patrón list/sinpe sobre montos overage | **Closed — sí** (tabla ₡600/₡500) |
| Q-USD | Tabla USD fija | **Closed — D27** |
| Q-YAML | ¿`billing.yml` con pares `official_crc` + `sinpe_crc` por producto (+ USD aparte) y descuento **calculado** (`official − sinpe`)? | **Open — recommend sí** |
| Q-CARD-CR | Usuario CR paga **tarjeta**: ¿cobro/simulación en **CRC oficial** (₡3,250) aunque hoy el enum diga `card_usd`? ¿Renombrar a `card` + `currency` en snapshot? | **Open** |
| Q-CURRENCY-ONVO | ONVO cobra por moneda elegida en carrito | **Closed — ONVO acepta USD y CRC; cobrar según selección** |
| Q-SINPE-USD | ¿Mostramos opción SINPE cuando el país es fuera de CR? | **Closed — NO (A)** |

---

## Follow-ups (out of scope)

- `docs/ROADMAP.md` → **Admin ventas / reporte de pagos**
- ONVO gateway (re-explore)
- FU-LEGAL: copy MEIC final

---

## Decision log

| Date | ID | Decision |
|------|-----|----------|
| 2026-05-27 | D1–D21 | Discovery rounds 1–3 |
| 2026-05-27 | D22–D25 | MEIC list/SINPE discount; admin UI→roadmap; failed payments snapshot; 3-screen UX |
| 2026-05-27 | D26 | Tabla CRC oficial/SINPE/ahorro; Q-IVA B; overage 50% verificado |
| 2026-05-27 | D27–D28 | Tabla USD; overage por montos (no %) |
| 2026-05-27 | D29 | ONVO cobra en USD o CRC según selección; SINPE solo disponible para país CR |

---

<implementation_plan>
  <meta>
    <task_slug>billing-cart</task_slug>
    <branch_name_suggestion>feat/billing-cart</branch_name_suggestion>
    <roadmap_item>Billing cart UX (single-item) + MEIC pricing display</roadmap_item>
    <classification>Refactor</classification>
    <req_ids>
      <req>REQ-FIT-BILL-001</req>
      <req>REQ-FIT-BILL-002</req>
      <req>REQ-FIT-BILL-003</req>
    </req_ids>
    <constraints>
      <constraint>Rails-only billing math (no Python billing). Conform to docs/core/SYSTEM_ARCHITECTURE.md kill list.</constraint>
      <constraint>Hotwire/Stimulus; no SPA frameworks.</constraint>
      <constraint>Cart supports exactly one item; replace requires confirmation.</constraint>
      <constraint>IVA 13% calculated and shown only at checkout; cart shows list subtotal + SINPE tip.</constraint>
      <constraint>Payment snapshots stored for succeeded and failed.</constraint>
    </constraints>
  </meta>

  <phase id="P0" name="Baseline + discovery verification">
    <step status="complete">Run existing Rails test suite for billing/auth to ensure green baseline.</step>
    <step status="complete">Confirm current `/taller/descarga-pago`, `/planes`, `/checkout` behavior manually.</step>
  </phase>

  <phase id="P1" name="Pricing config & APIs">
    <step status="complete">Write failing unit/spec tests for `Billing::Pricing` new keys: official+sinpe for CRC and USD, including explicit overage amounts (no percent).</step>
    <step status="complete">Update `config/billing.yml` structure to be easy to change: per-product official/sinpe in both currencies + explicit overage entries.</step>
    <step status="complete">Update `Billing::Pricing` to expose a clean API (e.g. `price(product:, currency:, tier_months:, overage:, kind:)`) and to validate positivity.</step>
    <step status="complete">Remove reliance on `plan_quota_overage_percent` for display + checkout math (keep key only if needed for backwards compat; otherwise deprecate).</step>
  </phase>

  <phase id="P2" name="Geo default + manual selector">
    <step status="complete">Write request/unit tests for `Billing::GeoPaymentDefaults.from_request` using `CF-IPCountry` when present; fallback to GeoLite2; allow env override in development.</step>
    <step status="complete">Add manual selector on paywall/cart to switch currency/method (CRC/SINPE default for CR; USD/card default outside CR). Selecting overrides IP default.</step>
    <step status="complete">Ensure SINPE is not offered when country != CR (unless explicitly overridden by owner later).</step>
  </phase>

  <phase id="P3" name="Cart domain (DB + merge behavior)">
    <step status="complete">Write failing request/service specs for single-item cart invariants, including replace-confirm flow.</step>
    <step status="complete">Add `Cart` model & migration supporting guest + user carts (guest_token, user_id, kind, nesting_run_id/tier_months, snapshot prices in chosen currency, overage flag).</step>
    <step status="complete">Implement merge-on-login rule: user cart wins; guest cart discarded when both exist.</step>
    <step status="complete">Add `Billing::CartTotals` and `Billing::PlanExpiryPreview` services (projected ends_at shown for plan cart line).</step>
  </phase>

  <phase id="P4" name="Routes + controllers + views">
    <step status="complete">Introduce `/carrito` (GET review; POST add; PATCH replace-confirm; DELETE clear). Add i18n copy for cart, replace confirmation, SINPE promo hints.</step>
    <step status="complete">Refactor `/taller/descarga-pago` view to show: download (if downloadable run) + 3 plans inline, each with “Añadir al carrito”. Remove “ver planes”.</step>
    <step status="complete">Redirect `/planes` permanently to `/carrito` when cart has an item; else to `/taller/descarga-pago`.</step>
    <step status="complete">Update `/checkout` to read from `current_cart` instead of query `nesting_run_id`. Enforce auth gate: guests must sign in/create account to proceed.</step>
    <step status="complete">Implement dynamic checkout breakdown: list subtotal, SINPE discount line (only when SINPE), IVA line, total line; computed server-side with lightweight Stimulus update for method toggle.</step>
  </phase>

  <phase id="P5" name="Payment recording snapshots (admin reporting-ready)">
    <step status="complete">Write failing model/service specs asserting snapshot fields persisted for both succeeded and failed payments (name/email/product/list/discount/subtotal/tax/total/currency/method).</step>
    <step status="complete">Add migration to extend `payments` with immutable snapshot columns (do not rely on current user profile for reporting).</step>
    <step status="complete">Update `Billing::SimulateSingleDownload` and `Billing::SimulatePlanPurchase` (or their callers) to populate snapshot fields from the cart attempt and user at pay time.</step>
  </phase>

  <phase id="P6" name="Edge cases + regression tests">
    <step status="complete">Add request specs for: cupo plan download bypass; no nesting_run hides download option; overage pricing displayed; replace-confirm; redirect `/planes`; cart persistence across logout/login. (Done: paywall plan-quota bypass spec, paywall no-run spec, checkout overage pricing display spec, cart replace-confirm spec, `/planes` redirect spec, cart persistence+merge-on-login spec)</step>
    <step status="complete">Ensure tests are tagged with appropriate `[REQ-FIT-BILL-*]` in root `RSpec.describe` where applicable.</step>
  </phase>

  <phase id="P7" name="Polish + docs">
    <step status="complete">Update relevant i18n keys (`billing.paywall.*`, new `billing.cart.*`, checkout MEIC promo copy) and ensure locale parity (`es_panic` mirror) if keys added. (Done: added `billing.cart.title`/`add_to_cart`, `billing.checkout.breakdown.*`, and `billing.paywall.selector.*` in `en.yml`/`es.yml` + mirrored selector/cart/breakdown keys to `es_panic.yml`; removed view defaults/hardcoded copy.)</step>
    <step status="complete">Update `docs/QA_MANUAL_CHECKLIST.md` with cart flow checks.</step>
    <step status="complete">Confirm roadmap item added for Admin ventas UI (already appended). (Done: `docs/ROADMAP.md` backlog item “Admin ventas / reporte de pagos” references payment snapshots + `task_billing-cart.md`.)</step>
  </phase>

  <phase id="P8" name="Checkout flow refactor (method-first, dynamic receipt, single CTA)">
    <step id="P8.1" status="complete">Run targeted request specs for checkout/paywall/cart to confirm baseline stays green.</step>
    <step id="P8.2" status="complete">Write/adjust request specs asserting checkout vertical order and dynamics: method selection precedes breakdown; breakdown updates when method toggles; single “Procesar pago” CTA at bottom. Keep REQ tags under REQ-FIT-BILL-001/002.</step>
    <step id="P8.3" status="pending">Refactor `CheckoutController` + `checkout/show.html.erb` to: render method selector first (as large selectable cards), update breakdown via Turbo Frame/Stream on selection, and move to a single submit action. Preserve existing pricing rules (SINPE promo vs card official; IVA only when applicable).</step>
    <step id="P8.4" status="pending">Add i18n keys for new labels (“Ahorra ₡X”, “Procesar pago”, etc.) with `es_panic` parity; update CSS for the new card selector + receipt layout.</step>
    <step id="P8.5" status="pending">Run the focused spec set again and fix any regressions.</step>
  </phase>
</implementation_plan>
