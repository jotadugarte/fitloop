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

_Pendiente — se insertará `<implementation_plan>` cuando el usuario confirme spec completa (explore-task step 1.2 → finalize)._
