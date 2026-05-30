# ADR-0007: Production deploy on bare-metal Linux VM

**Status:** Accepted  
**Date:** 2026-05-30  
**REQ:** REQ-FIT-QA-001, REQ-FIT-ARCH-001  
**Supersedes (partial):** ONVO epic follow-up **D-ONVO-13** (Northflank/Docker staging scope split)

## Context and problem statement

Fitloop v1 requires Rails, PostgreSQL, Solid Queue, and a Python `nesting_engine` CLI on the **same host filesystem** (Active Storage blobs + temp work dirs). During the ONVO billing epic, a **Northflank + Docker** staging path was considered (billing-only container without Python nesting). The team chose **not** to use Northflank and **not** to rely on the stock `Dockerfile` for v1 production go-live.

## Decision drivers

- **D1:** `docs/DEPLOY.md` already defines the normative topology: single Linux host with Ruby + `.venv` + PostgreSQL.
- **D2:** Nesting jobs invoke Python subprocesses against Active Storage paths — co-location on one VM is simpler than a split container without shared volumes.
- **D3:** ONVO webhook testing in development uses **ngrok**; production uses the **public HTTPS domain** behind Cloudflare — no third-party PaaS staging required.
- **D4:** The repository `Dockerfile` (Rails + Thruster only) remains for optional future use; it is **not** the v1 production path.

## Considered options

1. **Northflank (Docker, billing-only staging)** — Rejected: not used; incomplete for nesting E2E.
2. **Docker/Kamal with extended image (Rails + Python nesting)** — Deferred: valid later; out of scope for v1 go-live.
3. **Bare-metal Linux VPS** — **Chosen:** matches DEPLOY.md, full product on one host.

## Decision outcome

**Chosen:** Production and pre-production hosts run Fitloop on a **Linux VM** (Ubuntu/Debian recommended) per `docs/DEPLOY.md`:

| Component | On host |
|-----------|---------|
| Rails 8 (Puma or Thruster) | HTTP, Active Storage, billing |
| PostgreSQL 14+ | `primary`, `cache`, `queue`, `cable` databases |
| Python 3.10–3.12 + repo-root `.venv` | `nesting_engine` / `pynest2d` |
| Solid Queue | `SOLID_QUEUE_IN_PUMA=1` or separate `bin/jobs` worker |
| Reverse proxy (Nginx/Caddy) | TLS termination → app port |
| Cloudflare (proxied DNS) | HTTPS edge + `CF-IPCountry` for billing geo |
| Persistent disk | `storage/` (Active Storage) |

**Not in scope (v1 go-live):**

- Northflank or other PaaS-specific runbooks
- Production nesting via the stock `Dockerfile` without Python layer
- Separate staging environment requirement (local + ngrok for ONVO test; production domain for live)

### ONVO webhooks by environment

| Environment | Webhook URL |
|-------------|-------------|
| Local dev (ONVO test) | `https://<ngrok-host>/webhooks/onvo` |
| Production (ONVO live) | `https://<production-domain>/webhooks/onvo` |

### Positive consequences

- One runbook (`docs/DEPLOY.md`) covers full DXF → nest → pay → download.
- No split staging where billing works but nesting does not.
- Aligns with `SYSTEM_ARCHITECTURE.md` §4 single-host model.

### Negative consequences

- Ops owns VM provisioning, PostgreSQL backups, and `storage/` persistence.
- Docker-based deploy tooling (Kamal) is not exercised until a future ADR extends the image.

## Validation

- Host smoke checks in `docs/DEPLOY.md` (pynest2d, `capabilities()`, golden nest).
- `docs/QA_MANUAL_CHECKLIST.md` — **Production VM go-live** section.
- Roadmap backlog item: **Production VM deploy (bare metal)** in `docs/ROADMAP.md`.

## More information

- Runbook: `docs/DEPLOY.md`
- Billing geo: `docs/DEPLOY.md` (Cloudflare + GeoLite2)
- ONVO: `docs/core/ADRs/0006-onvo-live-billing.md`
- Historical ONVO staging notes (superseded): `.agenticguild/completed_sessions/task_onvo-payments_2026-05-30.md` (D-ONVO-12..14)
