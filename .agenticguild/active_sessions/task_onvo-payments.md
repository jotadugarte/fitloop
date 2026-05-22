# Task: ONVO payments + MEIC pricing (CRC-primary)

**Created:** 2026-05-21  
**Status:** Spec locked — handoff to `start-task` (2026-05-21)  
**Extends:** `task_auth-billing.md` (P7 simulated billing shipped); replaces simulated checkout with ONVO when credentials + legal gates are met.

**Owner intent:** Pasarela ONVO (SINPE automatizado + SDK tarjetas); precio lista oficial (tarjeta) + descuento promocional SINPE (MEIC); UI que ancle ahorro en SINPE; multimoneda con **colones como precio único visible** y USD solo como cargo backend de tarjeta al tipo de cambio del día.

---

## Context anchors

- **Hoy:** `Billing::SimulateSingleDownload` / `SimulatePlanPurchase`; `Payment` enum `card_usd` | `sinpe_crc`; precios duales en `config/billing.yml` (USD + CRC separados).
- **ADR-0005:** Billing simulado; “Stripe-ready `Payment` records”.
- **SPEC:** REQ-FIT-BILL-001..003; explícito “no real payment provider in v1”.
- **Bloqueantes externos (user):** Obligado Tributario (Hacienda) para activar ONVO; sandbox API keys; payouts quincenales/mensuales.

---

## Agreed (2026-05-21)

| # | Decision |
|---|----------|
| D1 | **Sesión nueva** `task_onvo-payments.md` (no extender el plan de implementación cerrado de auth-billing). |
| D2 | **Moneda visible:** solo **colones (CRC)** en checkout, `/planes`, paywall y Mis pagos. El usuario **no** ve dos precios (ej. ₡3,250 y $6 juntos). |
| D3 | **Multimoneda backend:** precios canónicos en **CRC** (`billing.yml`). Pago con **tarjeta** → ONVO cobra en **USD** calculado al **tipo de cambio del día** (snapshot diario); persistir en `Payment`: `amount_crc`, `amount_usd`, `fx_rate`, `fx_date`. |
| D4 | **Modelo MEIC:** “Precio oficial” (más alto) = tarjeta; “Descuento promocional” = SINPE. **No** recargo por tarjeta (ilegal MEIC). Copy legal = **FU-LEGAL-003** (follow-up). |
| D5 | **Tabla de precios (CRC)** — calibrada comisiones tarjeta 3.90% + ₡0.35, SINPE 1.50%, retención IVA 0.777%: |

| Producto | Precio oficial (tarjeta) | Ahorro SINPE | Precio final SINPE |
|----------|--------------------------|--------------|-------------------|
| Descarga única | ₡1,200 | ₡200 | ₡1,000 |
| Plan 1 mes | ₡3,250 | ₡250 | ₡3,000 |
| Plan 2 meses | ₡5,300 | ₡300 | ₡5,000 |
| Plan 4 meses | ₡8,400 | ₡400 | ₡8,000 |

| D6 | **Overage 50%** (cupo mensual agotado): **misma regla** — mitad del precio oficial (tarjeta) y mitad del precio final SINPE por tier/descarga (no un solo número genérico desacoplado). |
| D7 | **UX checkout:** SINPE seleccionado por defecto; badge verde con ahorro (ej. “Ahorra ₡250 pagando con SINPE”); precio oficial tachado/opaco; precio SINPE destacado. |
| D8 | **SINPE ONVO:** validación automatizada vía API; asociar pago cruzando **cédula + teléfono** ingresados en checkout (detalle de polling/webhook TBD en discovery). |
| D9 | **Tarjetas:** procesamiento estándar vía **SDK ONVO** (local + internacional). |
| D10 | **Operativo:** payouts ONVO quincenales o mensuales (diluir costo fijo ₡3 por retiro). |
| D11 | **FX en tiempo real:** consumir API gratuita del **BCCR** (webservice `wsindicadoreseconomicos`; indicador **318 venta** para convertir CRC→USD al cobrar tarjeta). **Hacienda** solo como fuente alternativa/documentada si aporta el mismo dato; BCCR es primaria. Suscripción/token BCCR vía portal oficial del BCCR. |
| D12 | **Dev híbrido:** sin credenciales ONVO → checkout simulado actual; con `ONVO_*` configurado → flujo ONVO. **Staging/producción:** solo ONVO (sin botones simular). |
| D13 | **SINPE UX:** pantalla de espera con **polling** (“confirma tu SINPE Móvil”) hasta `succeeded` / timeout; webhook ONVO como confirmación autoritativa; **no** crear `DownloadGrant` hasta confirmación. |
| D14 | **Blindaje de margen:** precios comerciales **fijos en CRC** (`billing.yml`, tabla D5). El **monto USD** enviado a ONVO se **recalcula** con la tasa BCCR vigente (`usd = official_crc / rate_venta`) para que el equivalente en dólares siga alineado con la ganancia neta calibrada; Fitloop no muestra USD en checkout — solo pasa el monto final a ONVO. |
| D15 | **Frecuencia BCCR:** el indicador de referencia del BCCR es **diario** (no tick en vivo). Fitloop: **(1)** job programado **1×/día hábil** ~06:00 `America/Costa_Rica`; **(2)** refresh **perezoso** en el primer checkout con tarjeta del día si aún no hay tasa para `Date.current`; **(3)** como máximo **1 reintento** en checkout si la tasa tiene >12h; **(4)** **nunca** llamar al BCCR en cada request/polling de UI. Checkout y ONVO leen solo **cache** (`exchange_rates`). |

---

## Multimoneda — arquitectura acordada (D2/D3/D11/D14)

**Principio:** CRC es la **fuente de verdad comercial**; USD es **instrumento de cobro** para tarjeta, no segunda etiqueta de precio.

```
billing.yml (CRC)
  official_crc  → UI "precio oficial" + base para overage tarjeta
  sinpe_crc     → UI precio destacado SINPE + cargo SINPE

Billing::FxRate.fetch (BCCR → ExchangeRate cache)
  indicador 318 (venta), fetched_at, effective_on
  fallback: última tasa válida; si >24h sin dato → bloquear tarjeta + aviso

Checkout tarjeta:
  usd = Billing::CardChargeUsd.from_crc(official_crc, rate)  # redondeo TBD (ceil 2 dec)
  ONVO SDK / API charge(usd)   # Fitloop pasa monto final; ONVO no calcula FX
  Payment: amount_crc_official, amount_usd_charged, fx_rate, fx_source: bccr, bccr_fetched_at

Checkout SINPE:
  charge(sinpe_crc) en CRC — sin FX
  polling UI hasta ONVO confirma
```

**BCCR (D11/D15):** `https://gee.bccr.fi.cr/Indicadores/Suscripciones/WS/wsindicadoreseconomicos.asmx` — operación `ObtenerIndicadoresEconomicos`; requiere email + token de suscripción gratuita ([documentación BCCR](https://www.bccr.fi.cr/indicadores-economicos/Paginas/APIs.aspx)). **No es Forex en vivo:** el BCCR publica el tipo de cambio de referencia **por día hábil**; varias consultas el mismo día suelen devolver el mismo valor.

| Cuándo | Qué hace Fitloop |
|--------|------------------|
| **06:00 CR** (job) | `Billing::FxRate.refresh!` → persiste `ExchangeRate` para hoy |
| **Primer pago tarjeta del día** | Si no hay fila para `Date.current`, un refresh perezoso (1 llamada) |
| **Tasa >12h** al cobrar tarjeta | Un reintento opcional antes de fallar |
| **Cada checkout / polling SINPE** | **No** llama al BCCR — solo lee DB |
| **Sin tasa del día** tras ventana matutina | Bloquear método tarjeta; SINPE en ₡ sigue |

“Tiempo real” en producto = **siempre la tasa oficial del día en cache**, no polling subminuto al BCCR.

**UI copy (tarjeta):** i18n sin monto USD: “El cargo en tarjeta se procesa en dólares al tipo de cambio del Banco Central de hoy.” USD visible solo en Mis pagos / recibo post-pago si aplica.

**Migración desde seeds actuales:** reemplazar claves `*_usd` + `*_sinpe_crc` duales por pares `*_official_crc` + `*_sinpe_crc` (o `*_card_crc` / `*_sinpe_crc`) por producto.

---

## Dev / staging (D12)

| Entorno | Checkout |
|---------|----------|
| **development** | `ONVO_API_KEY` blank → `checkout#simulate` (actual). Key presente → ONVO sandbox. |
| **staging / production** | Solo ONVO; quitar badge “demo simulate”. |

---

## Open questions

### A. ONVO técnico
- [ ] Documentación API: crear intent, webhooks, estados, SDK frontend.
- [ ] SINPE: timeout polling (ej. 10 min); validación formato cédula/teléfono CR.
- [ ] Sandbox: estructura credenciales (public/secret); entorno demo badge vs producción.

### B. FX (cerrado salvo detalle)
- [x] Fuente: **BCCR** (D11).
- [ ] Redondeo USD (ceil 2 dec vs otra política).
- [x] Frecuencia BCCR: **D15** (1×/día + lazy + máx 1 retry).
- [x] USD en UI checkout: **no** (D2); post-pago Mis pagos: **sí** si útil.

### D. Dominio / SPEC
- [ ] ADR-0006 (propuesto): ONVO + MEIC pricing; supersedes “simulated only” en ADR-0005 para checkout.
- [ ] REQ-FIT-BILL-004 o ampliar BILL-001: ONVO, FX diario, pricing CRC oficial/descuento.
- [ ] Refactor `Payment#payment_method` → `card` | `sinpe` con `currency_charged` usd|crc.

### E. Legal
- [ ] **FU-LEGAL-003:** textos MEIC — descuento por método de pago, no recargo tarjeta; planes y overage.

### F. Roadmap / ops
- [ ] Item backlog: ONVO integration (depends: Obligado Tributario, sandbox keys).
- [ ] Payouts quincenal/mensual (config ONVO portal, no código Fitloop salvo docs).

---

## Domain Model

_Approved 2026-05-21 (spec lock)._

### ExchangeRate + Billing::FxRate
- **Responsibility:** Cache de tasa BCCR (indicador 318 venta); servicio `Billing::FxRate.fetch` para checkout tarjeta.
- **Invariants:** `rate > 0`; `source == bccr`; no cobrar tarjeta si tasa ausente/obsoleta (>24h sin refresh); una fila canónica por `effective_on` (última fetch gana).
- **Value objects:** `FxRate`, `BccrIndicatorCode`, `EffectiveDate`, `MoneyAmount(crc|usd)`.

### Payment (extend)
- **Invariants:** `succeeded` implica `provider_reference` ONVO; montos CRC siempre presentes; USD solo si `payment_method == card`.
- **Value objects:** `OnvoPaymentId`, `OfficialPriceCrc`, `ChargedAmount`, `FxSnapshot`.

### CheckoutSession / OnvoIntent (TBD nombre)
- **Responsibility:** Puente estado pendiente SINPE (cédula/teléfono) o intent tarjeta SDK.
- **Invariants:** expira; un intent activo por `(user, purchasable)`; idempotente en retry.

_Entities `Subscription`, `DownloadGrant`, `Purchase` sin cambio semántico vs auth-billing._

---

## Risks

| Risk | Mitigation |
|------|------------|
| MEIC mal redactado | FU-LEGAL-003 antes de prod; revisión abogado |
| FX desactualizado / BCCR caído | Job Solid Queue + alerta; bloquear tarjeta si no hay tasa <24h; SINPE sigue en CRC |
| SINPE no valida a tiempo | Polling timeout + copy; grant solo tras webhook/estado ONVO terminal ok (D13) |
| BCCR token expirado | Credenciales en Rails credentials; monitor en job |
| Doble precio en UI viola D2 | Spec UI: un monto CRC visible; USD solo backend/recibo |
| Bloqueo Hacienda | Roadmap explícito; dev con simulate fallback |

---

## Scratchpad

- Comisiones user: tarjeta 3.90% + ₡0.35; SINPE 1.50%; IVA retención 0.777% — tabla D5 ya incorpora equidad neta.
- `Billing::Pricing` hoy: métodos separados USD/CRC → refactor a `official_crc` / `sinpe_crc` + `card_charge_usd(official_crc, rate)`.
- Overage D6 ejemplo descarga: oficial ₡1,200 → tarjeta overage ₡600; SINPE overage ₡500 (mitad de ₡1,000).
- auth-billing D35 (USD tarjeta / CRC SINPE) **evoluciona** a D2/D3 — no contradice, precisa capa FX.

---

## Decisions log

- **2026-05-21 — D1:** Sesión `task_onvo-payments.md`.
- **2026-05-21 — D2/D3:** UI solo CRC; tarjeta cobra USD al FX del día; persistir ambos montos en Payment.
- **2026-05-21 — D4/D5:** Modelo MEIC + tabla precios CRC acordada.
- **2026-05-21 — D6:** Overage 50% con misma regla oficial/SINPE.
- **2026-05-21 — D7–D10:** UX SINPE-first; ONVO SINPE+SDK; payouts; legal FU-LEGAL-003 follow-up.
- **2026-05-21 — D11–D14:** FX BCCR tiempo real; USD dinámico para ONVO; CRC fijos en yaml; dev híbrido; SINPE polling.
- **2026-05-21 — D15:** BCCR 1×/día hábil + lazy primer checkout tarjeta; sin llamadas por request.

---

## Follow-ups

| ID | Topic |
|----|--------|
| FU-LEGAL-003 | Copy MEIC: descuento promocional SINPE vs precio oficial tarjeta |
| FU-ONVO-001 | Cuenta sandbox + API keys |
| FU-OPS-001 | Obligado Tributario Hacienda (bloqueante ONVO prod) |
| FU-OPS-002 | Payouts quincenal/mensual en portal ONVO |
| FU-BCCR-001 | Suscripción gratuita webservice BCCR (email + token en credentials) |

---

## Implementation plan

<task_session>
  <metadata>
    <task_name>onvo-payments</task_name>
    <type>Feature</type>
    <req_id>REQ-FIT-BILL-004 (new); extends REQ-FIT-BILL-001..003</req_id>
    <roadmap_item>Product &amp; platform — ONVO payments + BCCR FX + MEIC pricing</roadmap_item>
    <phasing>P0 Governance → P1 Pricing CRC → P2 BCCR FX → P3 Payment domain → P4 ONVO core → P5 Checkout UX → P6 Card → P7 SINPE → P8 Planes → P9 Env gates → P10 QA/docs</phasing>
    <external_blockers>FU-OPS-001 Obligado Tributario (ONVO prod); FU-ONVO-001 sandbox keys; FU-BCCR-001 BCCR token; FU-LEGAL-003 MEIC copy (prod copy gate)</external_blockers>
  </metadata>

  <implementation_plan>
    <!-- P0 — Governance & anchors -->
    <step id="1" status="pending">Write failing doc verifier test for REQ-FIT-BILL-004 in docs/core/SPEC.md and ADR-0006 presence (extend `AuthBillingSpecDocVerifier` or add `OnvoBillingSpecDocVerifier`).</step>
    <step id="2" status="pending">Add docs/core/ADRs/0006-onvo-payments-bccr-fx-meic-pricing.md (extends ADR-0005; ONVO provider; CRC official/sinpe pairs; BCCR D15; dev hybrid D12; MEIC D4; no dual currency in UI D2).</step>
    <step id="3" status="pending">Update docs/core/SPEC.md: REQ-FIT-BILL-004 detail; amend REQ-FIT-BILL-001 (ONVO replaces simulate in staging/prod); note BILL-002/003 unchanged entitlements; DATA_FLOW_MAP + SCHEMA_REFERENCE (`exchange_rates`, `payments` FX/ONVO columns); docs/ROADMAP.md backlog item with Depends on FU-OPS-001/FU-ONVO-001.</step>

    <!-- P1 — CRC pricing (MEIC table D5) -->
    <step id="4" status="pending">Write failing `Billing::Pricing` spec [REQ-FIT-BILL-004]: YAML keys `*_official_crc` + `*_sinpe_crc` per product; seed values match D5 table; overage 50% halves official and sinpe amounts (D6).</step>
    <step id="5" status="pending">Migrate `config/billing.yml` (Spanish comments); implement `Billing::Pricing` refactor; update all callers (checkout, planes, simulate services) to use CRC pairs; remove legacy `*_usd` keys.</step>
    <step id="6" status="pending">Write failing request spec: checkout/planes HTML shows only ₡ prices; official struck-through + SINPE prominent; savings badge text (D7); no USD amount in checkout body (D2).</step>

    <!-- P2 — BCCR FX cache (D11, D14, D15) -->
    <step id="7" status="pending">Write failing `Billing::FxRate` spec with WebMock BCCR SOAP fixture: parses indicator 318 venta; persists `ExchangeRate` for `Date.current`; idempotent same-day refresh.</step>
    <step id="8" status="pending">Add `exchange_rates` migration + model; `Billing::BccrClient` (≤60 lines); `Billing::FxRate.refresh!` / `.current`; credentials `bccr.email`, `bccr.token`.</step>
    <step id="9" status="pending">Write failing `Billing::CardChargeUsd` spec: `usd = ceil2(official_crc / rate)`; rejects missing/stale rate (&gt;24h); documents round-up policy in ADR.</step>
    <step id="10" status="pending">Implement `CardChargeUsd`; Solid Queue `Billing::RefreshFxRateJob` cron ~06:00 `America/Costa_Rica`; lazy refresh on first card checkout of day (D15); max one retry if &gt;12h stale.</step>

    <!-- P3 — Payment / ONVO intent domain -->
    <step id="11" status="pending">Write failing Payment spec: columns `provider`, `provider_payment_id`, `amount_official_crc`, `amount_charged_usd`, `fx_rate`, `fx_effective_on`, `fx_source`; enum `payment_method` `card` | `sinpe` (migration from `card_usd`/`sinpe_crc`).</step>
    <step id="12" status="pending">Add `onvo_payment_intents` (or `payment_intents`) migration: `user_id`, `purpose`, `nesting_run_id`/`plan_tier`, `status`, `payment_method`, `idempotency_key`, `cedula`, `telefono`, `expires_at`, JSON `metadata`.</step>
    <step id="13" status="pending">Implement models; `Billing::PaymentGateway.onvo_enabled?` from ENV; keep simulate path when disabled (D12).</step>

    <!-- P4 — ONVO client (sandbox-first) -->
    <step id="14" status="pending">Write failing `Billing::Onvo::Client` spec with VCR/WebMock sandbox stubs: create card charge intent (USD amount from step 9); create SINPE validation (cedula+telefono); fetch payment status.</step>
    <step id="15" status="pending">Implement `Billing::Onvo::Client`, `CreateCardIntent`, `CreateSinpePayment`, `SyncPaymentStatus` services (≤60 lines each, assertions); read API keys from credentials.</step>
    <step id="16" status="pending">Write failing webhook request spec `POST /webhooks/onvo`: signature verify; terminal status updates intent + Payment; idempotent duplicate events.</step>
    <step id="17" status="pending">Implement `Webhooks::OnvoController`; route outside locale scope; no grant/subscription side effects until `succeeded` (D13).</step>

    <!-- P5 — Checkout UX + routing -->
    <step id="18" status="pending">Write failing system/request spec: SINPE selected by default; switching method updates displayed ₡; green savings badge; card subtitle mentions BCCR FX without USD figure (D2, D7).</step>
    <step id="19" status="pending">Refactor checkout/planes views + Stimulus `checkout_method_controller`: MEIC price anchor layout; hide simulate buttons when `onvo_enabled?`; block card method if no FX for today.</step>

    <!-- P6 — Card checkout ONVO -->
    <step id="20" status="pending">Write failing request spec: card checkout creates ONVO intent with computed USD; SDK/token endpoint returns client secret; success webhook creates Payment + DownloadGrant + retention (D54).</step>
    <step id="21" status="pending">Implement `CheckoutController` card flow (`create_intent`, `confirm`); mount ONVO JS SDK on checkout; staging/prod require ONVO (no simulate).</step>

    <!-- P7 — SINPE checkout ONVO + polling -->
    <step id="22" status="pending">Write failing request spec: SINPE form requires valid CR cédula + teléfono; posts create pending intent; polling endpoint returns pending/succeeded/timeout; grant only on succeeded (D13).</step>
    <step id="23" status="pending">Implement SINPE flow + `checkout/sinpe_waiting` Turbo/Stimulus poll (interval modest, e.g. 3s, max 10 min); i18n waiting copy; failure/timeout paths.</step>

    <!-- P8 — Plan purchases ONVO -->
    <step id="24" status="pending">Write failing planes checkout spec: plan tiers charge correct official/sinpe CRC; card uses FX USD; extends subscription from `ends_at` (D28); overage still 50% official/sinpe (D6).</step>
    <step id="25" status="pending">Implement `PlanesController` ONVO paths mirroring checkout; redirect `project#show` on success (D43).</step>

    <!-- P9 — Dev hybrid + regression -->
    <step id="26" status="pending">Write failing spec: development without `ONVO_API_KEY` still uses `checkout#simulate`; with key uses ONVO routes; production config raises if ONVO missing (D12).</step>
    <step id="27" status="pending">Wire `Rails.application.config.x.billing.gateway`; deprecate direct simulate in staging; update `Billing::Simulate*` to use new Pricing CRC keys.</step>
    <step id="28" status="pending">Write failing spec: `/mis-pagos` shows charged USD + FX metadata for card payments only; SINPE rows CRC-only.</step>
    <step id="29" status="pending">Update existing auth/billing request specs for new enums and prices; keep 2:30 AM retention scenario green.</step>

    <!-- P10 — i18n, QA, architecture test -->
    <step id="30" status="pending">i18n en/es (+ es_panic parity): checkout MEIC copy, SINPE waiting, FX unavailable, BCCR subtitle; placeholder FU-LEGAL-003 keys for MEIC discount wording.</step>
    <step id="31" status="pending">Update docs/QA_MANUAL_CHECKLIST.md (ONVO sandbox card/SINPE, webhook, BCCR job, hybrid dev); run full REQ-tagged billing regression.</step>
  </implementation_plan>

  <working_notes>
    ONVO API surface finalized against sandbox docs during step 14–15 (may adjust webhook field names).
    Do not call BCCR from polling loop (D15). ONVO receives final USD/CRC amounts only (D14).
    FU-LEGAL-003 blocks production marketing copy, not technical scaffold.
    FU-OPS-001 blocks ONVO production credentials only; sandbox unblocks steps 14–25.
    Payment method rename: data migration `card_usd` → `card`, `sinpe_crc` → `sinpe`.
  </working_notes>
</task_session>
