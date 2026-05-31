# ADR-0008: Admin analytics and user event bitácora

**Status:** Accepted  
**Date:** 2026-05-31

## Context and problem statement

We need a dedicated internal telemetry and events tracking system (User analytics & admin bitácora) for operators/admins of Fitloop, without displaying any telemetry to end-users. This system must log user operations, conversion stages, and payments to feed an admin dashboard and CSV exports. It must strictly protect user PII and respect privacy boundaries (not storing geometries or raw file contents), and have automated mechanisms (governance contract + spec verifiers) to prevent reporting schema drift.

## Decision drivers

*   Internal operations visibility: Need to track user conversion, payments, and errors.
*   Zero-drift reporting: Avoid silent breakage in report/dashboard columns when payments or workshop events change.
*   PII and resource efficiency: Limit data retention to 6 months of hot database storage, anonymizing user rows without losing historical event timelines, and forbid storing geometry files.

## Considered options

1.  **Direct Postgres tables per event type** – Heavy database migrations and high maintenance.
2.  **External telemetry services (Amplitude, Mixpanel)** – Introducing external dependencies and potential tracking blockages.
3.  **Flat `user_events` database log with JSONB metadata (`properties`)** – Choice representing Rails standard conventions, fast queries, and flexible schema.

## Decision outcome

**Chosen option:** Option 3 (Flat `user_events` database log with JSONB metadata) combined with a 6-layer drift detection stack (A41):

*   **Ingestion Pipeline (`Analytics::TrackEvent`):** Critical events (payments, nest runs, deletions) run synchronously; low-priority actions (workspace setup, clicks) run asynchronously via `TrackEventJob` with a rate-limit of 300/hour.
*   **A41 Governance Stack:** Enforces contract match via `docs/core/ANALYTICS_AND_REPORTING_CONTRACT.md`, `config/analytics_event_catalog.yml`, and `SpecDocVerifier` checks.
*   **Geolocation:** Derives country codes using a local GeoLite2 MMDB database with a fallback to `CF-IPCountry` HTTP headers.
*   **UI Dashboard:** Internal `/admin/analytics` and `/admin/usuarios` paths gated behind `users.admin` boolean, utilizing importmap-pinned Chart.js v4.

### Positive consequences

*   Highly flexible event-tracking schema via JSONB.
*   Strong CI/test-time guarantees that event properties, event catalog, and sales CSV headers never drift.
*   Minimal impact on performance via async queue for low-priority events.

### Negative consequences

*   JSONB aggregates in SQL require operators (`->`, `->>`) which can be verbose.
*   Requires keeping MaxMind DB updated or relying on proxy headers.
