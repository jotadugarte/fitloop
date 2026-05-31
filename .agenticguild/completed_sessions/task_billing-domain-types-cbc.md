# Task: Billing domain types (CbC refactor)

**Roadmap:** Pending #0 (Pre-live)  
**REQ-IDs:** REQ-FIT-BILL-001, REQ-FIT-BILL-002, REQ-FIT-BILL-003  
**Classification:** Refactor (CbC / Design by Contract)  
**Depends on:** ONVO merged (PR #19) ✓  
**Blocks:** Admin foundation (#1), Admin ventas (#2)

**Started:** 2026-05-30  
**Skill:** explore-task

---

## Goal

Replace raw `Integer` / `String` / loose symbols in the billing **service layer** with validated value objects so invalid monetary, tier, and payment states are **unrepresentable** at compile-time boundaries (Ruby: fail-fast at construction). Preserve existing DB enums and HTTP/JSON shapes unless ADR/SPEC explicitly updated.

---

## Architect decisions (2026-05-30 — user Q&A)

### D-BILL-CBC-1 — Scope (Q1: “lo más seguro posible”)

**Decision:** **Defense-in-depth, boundary-first.**

| Layer | Role |
|-------|------|
| **DB / ActiveRecord** (`Payment`, `Cart`, `Subscription`) | Keep Rails `enum` columns unchanged. AR remains persistence + framework validations. |
| **Domain types** (`app/models/billing/*.rb`) | New pure-Ruby VOs: parse/validate once; no ActiveRecord dependency. |
| **Services** (`app/services/billing/**`) | **Must** accept/return VOs for domain concepts (not raw strings/ints). |
| **Controllers / jobs** | Thin adapters: parse params/session → VOs immediately; never pass raw `params[:tier_months]` into services. |
| **Views / helpers** | May call VO formatters (`.label`, `.format`) — no business rules in ERB. |

**Out of scope v1:** ActiveRecord custom types, DB migrations, changing API JSON field names.

**Rationale:** Maximum safety without risky schema churn. Invalid `tier_months: 3` dies at `TierMonths.parse`, not deep inside `Pricing.plan_price_triple`.

### D-BILL-CBC-2 — Migration strategy (Q2: “seguro y rápido”)

**Decision:** **Phased vertical slices**, green suite after each phase (not big-bang).

1. **Phase A — Core types + unit specs**  
   Introduce VOs + factories (`.parse`, `.from_record`, `.from_enum`) with full invariant tests. No call-site changes yet (types exist but optional).

2. **Phase B — Pricing + CheckoutBreakdown (SSOT)**  
   Wire `Billing::Pricing` and `Billing::CheckoutBreakdown` first — highest leverage, single amount truth before ONVO/simulate.

3. **Phase C — Checkout orchestration**  
   `StartOnvoCheckout`, `Simulate*`, `CartUpsert`, `CartTotals`, `Gateway`.

4. **Phase D — Fulfillment + entitlement**  
   `FulfillPayment`, `FailPayment`, `Entitlement`, Mis pagos row builders, lock policy.

5. **Phase E — Controllers + remaining edges**  
   Billing controllers, `PendingCart`, geo defaults; delete legacy `.to_i` / string compares in services.

Each phase: run full billing-related RSpec before merging slice. Deprecate shims only after all call sites migrated.

**Rationale:** Faster feedback than monolithic PR; SSOT first prevents amount bugs during later phases.

### D-BILL-CBC-3 — Where types live (Q3)

**Decision:** **`app/models/billing/`** namespace (e.g. `Billing::TierMonths`), mirroring existing `Billing::Onvo::MoneyMinorUnits` pattern but for **core** billing concepts not gateway-specific.

- Gateway-specific types stay under `Billing::Onvo::*`.
- Core money for MEIC/checkout: `Billing::Money` (major units + currency).
- ONVO API cents: keep `Billing::Onvo::MoneyMinorUnits.from_breakdown` — wraps `CheckoutBreakdown` hash produced by typed pipeline.

**Do not** conflate `Billing::Money` (display/checkout major) with `MoneyMinorUnits` (ONVO integer minor).

### D-BILL-CBC-4 — Testing (Q4: “todas las pruebas posibles”)

**Decision:** Three layers, all required:

1. **VO unit specs** (`spec/models/billing/*_spec.rb`) — every invariant, invalid input, round-trip `.from_record` / `.to_db`, equality.
2. **Existing service specs** — update to construct VOs; assert behavior unchanged (refactor safety net).
3. **Request / integration specs** — no change to scenarios; must stay green (proves boundary adapters work).

Add regression examples for known foot-guns: `tier_months` 0/3/99, CRC vs USD cent math, SINPE vs card method, overage flag + product kind.

### D-BILL-CBC-5 — Admin relationship (Q5 clarified)

**Not a separate deliverable.** Admin ventas (#2) will read `payments` snapshot columns. This refactor should ensure **types used to write those snapshots** (`Money`, `PaymentMethod`, `ProductKind`, `PurchaseReference`) are solid **now** so admin UI/CSV is mostly presentation — not a second refactor.

Priority types for admin-readiness: `Money`, `PaymentMethod`, `ProductKind`, `PurchaseReference` (already partially typed).

### D-BILL-CBC-6 — CountryCode in scope (2026-05-30)

**Decision:** Promote `Billing::CountryCode` from optional scratchpad to **required Phase A VO**. Geo drives currency, IVA, and payment-method availability; invalid country strings must fail at parse, not inside `RegionalPolicy`.

**Rationale:** High ROI, low cost; pairs naturally with `CheckoutContext`. Nesting/workshop CbC (`margin_mm`, `kerf_mm`, piece keys) remains a **separate roadmap item** (Pre-live #1) — not mixed into this task.

---

## Domain Model

### Billing::TierMonths

- **Responsibility:** Valid plan duration for purchase (1, 2, or 4 months).
- **Wraps:** `Integer` (canonical values only).
- **Invariants:** Must be exactly `1`, `2`, or `4`; immutable after construction.
- **Factories:** `.parse(raw)`, `.from_cart(cart)`, `.from_record(subscription)`.

### Billing::PaymentMethod

- **Responsibility:** Checkout/payment rail identifier aligned with `Payment.payment_method` enum.
- **Wraps:** `String` enum value (`card_usd` | `card_crc` | `sinpe_crc`).
- **Invariants:** Must be one of `CheckoutPaymentMethod::ALL`; SINPE only valid with CRC currency.
- **Replaces:** Raw string passing + `CheckoutPaymentMethod` module as sole authority (module becomes facade delegating to VO or merges into VO class methods).

### Billing::Currency

- **Responsibility:** Billing currency mode (`usd` | `crc`).
- **Wraps:** Symbol or string.
- **Invariants:** Must match payment method rules (USD ↔ card only in regional policy).

### Billing::CountryCode

- **Responsibility:** ISO 3166-1 alpha-2 billing country (geo → currency, IVA, available payment methods).
- **Wraps:** String (2 letters, uppercase canonical form).
- **Invariants:** Valid alpha-2 on parse (normalize case/whitespace); reject garbage; `.costa_rica?` is the regional pivot for CRC/SINPE/IVA (aligned with `RegionalPolicy::COSTA_RICA`).
- **Factories:** `.parse(raw)`, `.from_geo_defaults(geo_hash)` (reads `:country_code`), optional `nil` for unknown geo → policy defaults without invalid state.
- **Promoted 2026-05-30:** Required Phase A VO (was optional scratchpad item).

### Billing::BillingMethod

- **Responsibility:** Pricing axis (`:card` | `:sinpe`) — distinct from full `PaymentMethod`.
- **Wraps:** Symbol.
- **Invariants:** Used only inside `Pricing.price`; SINPE implies CRC.

### Billing::Money

- **Responsibility:** Major-unit monetary amount with currency (MEIC display, checkout breakdown, payment snapshot).
- **Wraps:** `BigDecimal` + `Billing::Currency`.
- **Invariants:** Amount ≥ 0; currency required; CRC amounts typically integer colones; USD may have cents; no mixed-currency arithmetic.
- **Factories:** `.from_cents(cents, currency)`, `.from_major(amount, currency)`, `.from_breakdown_field(hash, key)`.

### Billing::CentsAmount

- **Responsibility:** Integer minor/cent storage for cart snapshots (`list_price_cents`, `sinpe_price_cents`).
- **Wraps:** `Integer` + `Billing::Currency`.
- **Invariants:** Non-negative; USD cents = amount×100; CRC “cents” = whole colones stored as integer (match existing cart semantics).

### Billing::ProductKind

- **Responsibility:** What is being purchased (`single_download` | `plan`).
- **Wraps:** String/symbol aligned with `Cart.kind` / `Payment.purpose`.
- **Invariants:** Single download requires `nesting_run_id`; plan requires `TierMonths`.

### Billing::CheckoutContext

- **Responsibility:** Bundle passed to breakdown/checkout (currency + payment method + IVA flag + geo).
- **Wraps:** `Billing::Currency`, `Billing::PaymentMethod`, `Billing::CountryCode` (optional), `Boolean` iva_applicable.
- **Invariants:** IVA only when `country_code.costa_rica?`; currency/method compatibility enforced at construction (may derive from `CountryCode` + `RegionalPolicy`).

### Billing::PurchaseReference (existing — extend)

- **Responsibility:** 12-digit MEIC purchase reference.
- **Already exists:** `Billing::PurchaseReference` — ensure service boundaries use VO, not raw regex strings.

### Billing::Onvo::MoneyMinorUnits (existing — keep)

- **Responsibility:** ONVO Payment Intent integer amount.
- **Invariants:** Only USD/CRC; derived from finalized breakdown only.

### Entities unchanged (persistence)

- **Payment**, **Cart**, **Subscription**, **DownloadGrant** — AR models; gain `.tier_months_vo`-style helpers optional; services prefer VOs.

---

## Current primitives audit (hot spots)

| Location | Raw today | Target |
|----------|-----------|--------|
| `Pricing#plan_price_triple(tier_months)` | Integer | `TierMonths` |
| `Pricing#price(... payment_method: :card)` | Symbol | `BillingMethod` |
| `CheckoutBreakdown` billing_context Hash | `:currency`, `:payment_method` symbols | `CheckoutContext` |
| `RegionalPolicy#for_country`, `GeoPaymentDefaults` | String/nil country_code | `CountryCode.parse` at boundary |
| `Cart#tier_months`, `#currency_mode` | Integer/String enums | `TierMonths`, `Currency` |
| `StartOnvoCheckout` kwargs | raw strings/ints | VOs |
| `Simulate*` services | string payment_method | `PaymentMethod` |
| Controllers | `params[:tier_months].to_i` | parse at boundary |

---

## Risks

| Risk | Mitigation |
|------|------------|
| Large diff touches checkout | Phased slices; SSOT (breakdown) first |
| CRC “cents” naming confusion | Document in VO; single `CentsAmount` factory |
| Duplicate type with ONVO | Keep `Money` vs `MoneyMinorUnits` separate |
| Behavior drift | Service + request specs green each phase |
| Scope creep into AR rewrite | Explicit out-of-scope: no custom AR types |

---

## Open questions

_(closed 2026-05-30 — user approved spec)_

---

## Scratchpad

### Green baseline (2026-05-30 — start-task step 0.1)

**Command (corrected paths; `spec/requests/billing` is not a directory):**

```bash
BILLING_GATEWAY=simulate bundle exec rspec \
  spec/services/billing \
  spec/models/payment_spec.rb spec/models/cart_spec.rb \
  spec/requests/cart_spec.rb spec/requests/cart_persistence_login_spec.rb \
  spec/requests/billing_preferences_spec.rb spec/requests/paywall_billing_selection_spec.rb \
  spec/requests/checkout_from_cart_spec.rb spec/requests/checkout_simulate_spec.rb \
  spec/requests/checkout_method_first_flow_spec.rb spec/requests/checkout_geo_methods_spec.rb \
  spec/requests/checkout_plan_overage_spec.rb spec/requests/checkout_overage_pricing_display_spec.rb \
  spec/requests/checkout_plan_quota_priority_spec.rb spec/requests/checkout_retention_spec.rb \
  spec/requests/plan_checkout_spec.rb spec/requests/planes_cart_redirect_spec.rb \
  spec/requests/checkout_onvo_ui_spec.rb spec/requests/checkout_release_pending_lock_spec.rb \
  spec/requests/checkout_onvo_sinpe_spec.rb spec/requests/checkout_payment_status_spec.rb \
  spec/requests/checkout_onvo_pay_spec.rb spec/requests/checkout_onvo_card_spec.rb \
  spec/requests/checkout_duplicate_sinpe_lock_spec.rb spec/requests/checkout_three_ds_return_spec.rb
```

**Result:** 272 examples, 0 failures (seed 46060, ~11s).

**Note:** With default `.env` `BILLING_GATEWAY=onvo`, 14 simulate-only request specs fail (expected). Use `BILLING_GATEWAY=simulate` for refactor baseline and slice runs unless explicitly testing ONVO paths.

- `CheckoutPaymentMethod` module may become class methods on `PaymentMethod` VO to avoid two sources of truth.
- `Billing::CountryCode` promoted to required Phase A VO (2026-05-30).
- `QuotaCount` / `DownloadQuota` lower priority unless touched during plan services refactor.
- Nesting/workshop CbC (`margin_mm`, `kerf_mm`, piece keys) tracked separately — ROADMAP Pre-live #1; out of scope for this task.

---

<implementation_plan>
  <meta>
    <task_slug>billing-domain-types-cbc</task_slug>
    <branch_name_suggestion>refactor/billing-domain-types-cbc</branch_name_suggestion>
    <roadmap_item>Billing domain types (CbC refactor) — Pending #0</roadmap_item>
    <classification>Refactor</classification>
    <req_ids>
      <req>REQ-FIT-BILL-001</req>
      <req>REQ-FIT-BILL-002</req>
      <req>REQ-FIT-BILL-003</req>
    </req_ids>
    <constraints>
      <constraint>Rails-only billing; no payment logic in Python (SYSTEM_ARCHITECTURE §3 kill list).</constraint>
      <constraint>Service objects in `app/services/billing/`; domain VOs in `app/models/billing/`; no fat controllers.</constraint>
      <constraint>No DB migrations; keep `Payment`/`Cart` Rails enums at persistence boundary.</constraint>
      <constraint>No change to HTTP routes, JSON response keys, or ONVO webhook contract unless ADR/SPEC explicitly updated.</constraint>
      <constraint>`Billing::CheckoutBreakdown` remains amount SSOT; `Billing::Onvo::MoneyMinorUnits` unchanged except consuming typed breakdown output.</constraint>
      <constraint>Do not conflate `margin_mm`/`kerf_mm` (nesting) — billing only.</constraint>
      <constraint>CbC: every VO has pre/post assertions; functions ≤60 lines; cyclomatic complexity ≤10.</constraint>
      <constraint>Root `RSpec.describe` for new specs must include `[REQ-FIT-BILL-*]` constant(s).</constraint>
      <constraint>Update ADR-0005 addendum + SPEC only if documenting new `app/models/billing/` namespace (no behavioral change).</constraint>
    </constraints>
  </meta>

  <phase id="P0" name="Green baseline &amp; anchors">
    <step id="0.1" status="complete">Run existing tests to establish a green baseline: `bundle exec rspec spec/services/billing spec/requests/billing spec/models/payment_spec.rb spec/models/cart_spec.rb` (and any billing-tagged request specs). Record command + pass count in session scratchpad.</step>
    <step id="0.2" status="complete">Add ADR-0005 addendum (or short section in ADR-0005) documenting `app/models/billing/` value-object layer and boundary rule: services accept VOs, AR enums at persistence only.</step>
    <step id="0.3" status="complete">If SPEC mentions raw tier/payment types in implementation notes, add one paragraph under REQ-FIT-BILL-001 pointing to typed billing domain layer (no requirement ID change).</step>
  </phase>

  <phase id="P1" name="Phase A — Core value objects">
    <step id="1.1">Write failing unit specs for `Billing::TierMonths` — valid 1/2/4, reject 0/3/99/nil, `.to_i`, `.from_cart`, equality.</step>
    <step id="1.2">Implement `Billing::TierMonths` in `app/models/billing/tier_months.rb`.</step>
    <step id="1.3">Write failing unit specs for `Billing::Currency` — usd/crc only; compatibility helpers with payment method.</step>
    <step id="1.4">Implement `Billing::Currency`.</step>
    <step id="1.5">Write failing unit specs for `Billing::BillingMethod` — :card/:sinpe; sinpe requires crc.</step>
    <step id="1.6">Implement `Billing::BillingMethod`.</step>
    <step id="1.7">Write failing unit specs for `Billing::PaymentMethod` — card_usd/card_crc/sinpe_crc; `.card?`, `.sinpe?`, `.billing_method`, `.currency`, reject unknown; SINPE+USD invalid.</step>
    <step id="1.8">Implement `Billing::PaymentMethod`; refactor `Billing::CheckoutPaymentMethod` to delegate to VO (single source of truth).</step>
    <step id="1.9">Write failing unit specs for `Billing::CentsAmount` — CRC colones-as-integer vs USD cents; non-negative; `.to_major`.</step>
    <step id="1.10">Implement `Billing::CentsAmount`.</step>
    <step id="1.11">Write failing unit specs for `Billing::Money` — major units + currency; no mixed-currency add; `.from_cents`, comparison, formatting hook.</step>
    <step id="1.12">Implement `Billing::Money`.</step>
    <step id="1.13">Write failing unit specs for `Billing::ProductKind` — single_download/plan; pairing rules with run vs tier.</step>
    <step id="1.14">Implement `Billing::ProductKind`.</step>
    <step id="1.15">Write failing unit specs for `Billing::CountryCode` — ISO 3166-1 alpha-2; `.parse` normalizes case/whitespace; `.costa_rica?`; reject blank/garbage; nil/unknown geo path.</step>
    <step id="1.16">Implement `Billing::CountryCode` in `app/models/billing/country_code.rb`.</step>
    <step id="1.17">Write failing unit specs for `Billing::CheckoutContext` — bundles currency + payment_method + country_code + iva_applicable; enforces RegionalPolicy compatibility at construction.</step>
    <step id="1.18">Implement `Billing::CheckoutContext` with `.from_session(billing_context_hash)` adapter for gradual migration.</step>
    <step id="1.19">Run Phase A unit suite; all green before Phase B.</step>
  </phase>

  <phase id="P2" name="Phase B — Pricing &amp; CheckoutBreakdown (SSOT)">
    <step id="2.1">Write failing specs: `Billing::Pricing.plan_price_triple` accepts `TierMonths`; `price` accepts `BillingMethod` + `TierMonths`; invalid combos raise at boundary.</step>
    <step id="2.2">Refactor `Billing::Pricing` to typed args; keep `.parse` shims temporarily if needed for transitional call sites.</step>
    <step id="2.3">Write failing specs: `CheckoutBreakdown.for_cart/for_plan/for_single_download` accept `CheckoutContext` (or typed kwargs); output hash unchanged.</step>
    <step id="2.4">Refactor `Billing::CheckoutBreakdown`; internal math uses `Billing::Money` where applicable.</step>
    <step id="2.5">Run `spec/services/billing/pricing_spec.rb`, `checkout_breakdown_spec.rb`, and full billing service specs — green.</step>
  </phase>

  <phase id="P3" name="Phase C — Checkout orchestration">
    <step id="3.1">Write failing service specs (or extend existing): `CartUpsert`, `CartTotals` use `TierMonths`, `Currency`, `CentsAmount` at boundaries.</step>
    <step id="3.2">Refactor `Billing::CartUpsert`, `Billing::CartTotals`, `Billing::CartMergeOnLogin`, `Billing::PendingCart`.</step>
    <step id="3.3">Write failing specs: `StartOnvoCheckout`, `SimulateSingleDownload`, `SimulatePlanPurchase`, `Billing::Gateway` — typed payment_method/tier/context; behavior unchanged.</step>
    <step id="3.4">Refactor checkout orchestration services; ensure `Billing::Onvo::MoneyMinorUnits.from_breakdown` still receives equivalent breakdown hash.</step>
    <step id="3.5">Run checkout-related service + request specs — green.</step>
  </phase>

  <phase id="P4" name="Phase D — Fulfillment, entitlement, Mis pagos">
    <step id="4.1">Write failing specs: `FulfillPayment`, `FailPayment`, `Entitlement`, `MisPagos::SinglePurchaseRows` — snapshot fields written via typed `Money`/`PaymentMethod`/`ProductKind` where applicable.</step>
    <step id="4.2">Refactor fulfillment and entitlement services; extend `Billing::PurchaseReference` usage at boundaries if any raw strings remain.</step>
    <step id="4.3">Refactor lock policy services (`PendingCheckoutPolicy`, `PendingCheckoutLock`, etc.) to use `PaymentMethod` VO for sinpe/card checks.</step>
    <step id="4.4">Run fulfillment + mis_pagos specs — green.</step>
  </phase>

  <phase id="P5" name="Phase E — Controllers &amp; cleanup">
    <step id="5.1">Identify billing controllers (`CheckoutController`, cart/paywall controllers); write failing request specs if any param parsing regressions are possible (tier_months invalid → 422).</step>
    <step id="5.2">Refactor controllers: parse params → VOs at entry; pass VOs to services only.</step>
    <step id="5.3">Refactor remaining billing services (`GeoPaymentDefaults`, `RegionalPolicy`, `PaymentSelection`, `PlanPeriod`, `PlanDownloadAvailability`, etc.) to use `CountryCode` and other VOs at boundaries.</step>
    <step id="5.4">Remove transitional `.parse` shims and dead string compares; grep `app/services/billing` for `tier_months.to_i`, loose `payment_method` strings — zero hits for domain concepts.</step>
    <step id="5.5">Optional AR helpers: `Cart#tier_months_vo`, `Payment#payment_method_vo` for read paths only.</step>
  </phase>

  <phase id="P6" name="Regression &amp; roadmap">
    <step id="6.1">Run full billing test suite: all `spec/services/billing`, `spec/models/billing`, billing request specs, `test/spec/auth_billing_spec_doc_test.rb`.</step>
    <step id="6.2">Run `spec/i18n/locale_key_parity_spec.rb` if any billing copy helpers changed (unlikely).</step>
    <step id="6.3">Update `docs/ROADMAP.md`: mark Pending #0 complete when merged.</step>
    <step id="6.4">Archive session to `.agenticguild/completed_sessions/task_billing-domain-types-cbc_YYYY-MM-DD.md` via `finish-branch` skill.</step>
  </phase>
</implementation_plan>
