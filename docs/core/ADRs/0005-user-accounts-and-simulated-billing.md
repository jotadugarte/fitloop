# ADR-0005: User accounts and simulated billing

**Status:** Accepted  
**Date:** 2026-05-20  
**REQ:** REQ-FIT-AUTH-002, REQ-FIT-BILL-001, REQ-FIT-BILL-002, REQ-FIT-BILL-003

## Context and problem statement

Fitloop v1 shipped **ephemeral workspace access only** (ADR-0004 / `REQ-FIT-AUTH-001`): one session-bound `Project` per browser tab, destroyed on discard or TTL. Product now requires **persistent user accounts** for login, email verification, and **simulated billing** before downloading nested DXF. Projects remain **ephemeral** — accounts do not own saved projects.

## Decision drivers

- **D1:** Login/register always visible; anonymous users may nest and preview; **paywall only on nested DXF download**.
- **D2:** OAuth (Google, Facebook, Apple) + email/password via **Devise** + **OmniAuth**; providers optional per ENV.
- **D3:** Billing v1 is **simulated** (success/fail buttons); USD card + CRC SINPE Móvil; prices in `config/billing.yml` with hot-reload.
- **D4:** Plans 1 / 2 / 4 months; **50 downloads per calendar month** within the subscription window; overage = single download at **50%** list price.
- **D5:** Single-purchase downloads retain `nested_dxf` for **24 hours** on the user (not on ephemeral `Project`) — `retained_nested_dxf` on grant/delivery row.
- **D6:** Multi-tab: `session[:workspaces]` hash maps `tab_id` → `project_id`; Stimulus emits `tab_id` per tab.

## Considered options

1. **Auth0 / external IdP only** — Rejected: adds SaaS dependency; Devise+OmniAuth is sufficient for v1.
2. **Persist projects per user** — Rejected: contradicts ephemeral workshop model; only billing artifacts persist.
3. **Guest checkout** — Rejected: guest must register before paying (D40).

## Decision outcome

**Chosen:** Orthogonal layers — `User` (persistent) + `Workspace` (ephemeral, extended) + billing domain (`Subscription`, `Purchase`, `Payment`, `DownloadGrant`).

### Access model (extends ADR-0004)

| Concern | Rule |
|---------|------|
| **Workspace bind** | `session[:workspaces][tab_id] = project_id`; `Workspace.bind!(session, project, tab_id:)` / `resolve!(session, project_id, tab_id:)`. |
| **TTL** | On tab close only (not Turbo in-app navigation), cookie `fitloop_workspace_tab_left_at`; **>120s** after closing the tab without logout → expire with clear message; **≤120s** → same project. No idle expiry while the browser tab stays open. |
| **Auth mid-flow** | Login/register **re-binds** the in-flight ephemeral `Project` (D18). |
| **Logout** | `Workspace.discard!` for tab + user sign-out; warn if active project. |
| **Download** | Nested DXF only; strict authorization via `DownloadGrant` / active plan quota; **signed URL** (~15 min). |

### Billing (simulated v1)

- **Paywall:** `nested.dxf` download only; preview/JSON free; remove orphan DXF download button.
- **Single purchase:** one grant per `NestingRun`; copy blob to `retained_nested_dxf` on success; `retained_until = paid_at + 24.hours`.
- **Plan:** `starts_at` at payment instant; `ends_at` = end of natural day N months later in `users.time_zone`; one active plan; extension stacks from current `ends_at`.
- **Suspended:** `users.suspended_at` blocks pay and download.

### Positive consequences

- Clear separation: workshop data ephemeral, billing data durable
- Doc verifier + REQ traceability before implementation
- Stripe-ready `Payment` records without changing entitlement model

### Negative consequences

- Session shape change (`:workspaces` hash) requires migration of all bind sites
- Apple/Google OAuth needs per-environment callback URLs
- Legal copy for terms/plans deferred (FU-LEGAL-001/002)

## Implementation notes

- **Stack:** Devise (+ `:confirmable`, password ≥12), OmniAuth providers as configured.
- **Routes (es):** `/iniciar-sesion`, `/crear-cuenta`, `/mi-cuenta`, `/mis-pagos`, `/planes`.
- **Config:** `config/billing.yml` — commented Spanish keys; `Billing::Pricing` reload on mtime.
- **Tests:** `test/spec/auth_billing_spec_doc_test.rb`, then model/request/system specs per `task_auth-billing.md`.

## Validation

- ADR accepted (this document).
- `AuthBillingSpecDocVerifier` green with SPEC detail sections for AUTH-002 and BILL-001..003.

## More information

- Requirements: `docs/core/SPEC.md` (REQ-FIT-AUTH-002, REQ-FIT-BILL-001..003 detail sections)
- Extends: `docs/core/ADRs/0004-ephemeral-session-access.md` (does not supersede)
