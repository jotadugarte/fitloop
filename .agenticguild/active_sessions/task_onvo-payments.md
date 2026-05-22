# Task: ONVO payments + MEIC pricing (CRC-primary)

**Created:** 2026-05-21  
**Status:** Discovery in progress  
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

---

## Multimoneda — propuesta arquitectónica (D2/D3)

**Principio:** CRC es la **fuente de verdad comercial**; USD es **instrumento de cobro** para tarjeta, no segunda etiqueta de precio.

```
billing.yml (CRC)
  official_crc  → UI "precio oficial" + base para overage tarjeta
  sinpe_crc     → UI precio destacado SINPE + cargo SINPE

Daily FX snapshot (ExchangeRate o config)
  rate_crc_per_usd  effective_on: Date.current

Checkout tarjeta:
  usd = round_up(official_crc / rate, 2 decimales)  # política redondeo TBD
  ONVO SDK charge(usd)
  Payment stores crc + usd + fx metadata

Checkout SINPE:
  charge(sinpe_crc) en CRC
  sin conversión en UI
```

**Tipo de cambio del día — opciones (elegir en discovery):**

| Opción | Pros | Contras |
|--------|------|---------|
| A. Tabla `exchange_rates` + job diario (BCCR u otra fuente) | Automático, auditable | Dependencia API; definir compra vs venta |
| B. `config/exchange_rate.yml` editado manualmente | Simple v1 | Riesgo olvido actualizar |
| C. ONVO devuelve FX al crear intent | Menos código Fitloop | Acopla lógica de display a proveedor |

**UI copy (tarjeta, sin segundo precio):** subtítulo opcional i18n: “El cargo en tarjeta se procesa en dólares al tipo de cambio vigente hoy.” — sin mostrar monto USD en pantalla salvo post-intent en recibo/Mis pagos si ONVO lo exige.

**Migración desde seeds actuales:** reemplazar claves `*_usd` + `*_sinpe_crc` duales por pares `*_official_crc` + `*_sinpe_crc` (o `*_card_crc` / `*_sinpe_crc`) por producto.

---

## Pregunta 3 — explicación (simulación vs ONVO)

**Qué significaba:** Hoy el checkout tiene botones **“Pago exitoso” / “Pago fallido”** que no mueven dinero real. Al integrar ONVO hay que decidir si esos botones:

| Modo | Comportamiento |
|------|----------------|
| **Solo ONVO** | En todos los entornos con API key configurada → único flujo real/sandbox ONVO. Sin botones simular. |
| **Híbrido dev** | Si `ONVO_API_KEY` está vacío (dev local sin cuenta) → fallback a simulación actual; si hay key → ONVO. |

**Recomendación pendiente de confirmación:** Híbrido dev (no bloquea QA local) + solo ONVO en staging/producción.

---

## Open questions

### A. ONVO técnico
- [ ] Documentación API: crear intent, webhooks, estados, SDK frontend.
- [ ] SINPE: ¿polling vs webhook? timeout UX; campos exactos cédula/teléfono.
- [ ] Sandbox: estructura credenciales (public/secret); entorno demo badge vs producción.

### B. FX
- [ ] Fuente del tipo de cambio diario (A/B/C arriba).
- [ ] Compra vs venta; redondeo USD (ceil vs banker's).
- [ ] ¿Mostrar USD solo en recibo/email/Mis pagos post-pago?

### C. Simulación (pregunta 3)
- [ ] Confirmar: híbrido dev vs solo ONVO everywhere.

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

## Domain Model (draft)

### ExchangeRate (o equivalente)
- **Responsibility:** Snapshot diario CRC↔USD para convertir cargo tarjeta.
- **Invariants:** una tasa activa por `effective_on`; `rate > 0`; no usar tasa de día futuro.
- **Value objects:** `FxRate`, `EffectiveDate`, `MoneyAmount(crc|usd)`.

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
| FX desactualizado | Job + alerta si tasa >24h; fallback bloquear tarjeta si no hay tasa |
| SINPE no valida a tiempo | Timeout + copy; no crear grant hasta webhook/confirmación ONVO |
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

---

## Follow-ups

| ID | Topic |
|----|--------|
| FU-LEGAL-003 | Copy MEIC: descuento promocional SINPE vs precio oficial tarjeta |
| FU-ONVO-001 | Cuenta sandbox + API keys |
| FU-OPS-001 | Obligado Tributario Hacienda (bloqueante ONVO prod) |
| FU-OPS-002 | Payouts quincenal/mensual en portal ONVO |

---

## Implementation plan

_Pendiente — se insertará `<implementation_plan>` cuando el usuario confirme spec completa (explore-task step 1.2 → finalize)._
