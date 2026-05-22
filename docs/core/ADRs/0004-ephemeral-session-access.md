# ADR-0004: Ephemeral session access (replaces PIN)

**Status:** Accepted  
**Date:** 2026-05-19  
**REQ:** REQ-FIT-AUTH-001

## Context and problem statement

MVP v1 introduced **saved projects** unlocked by a user **6-digit PIN** and an **admin master PIN** (`ProjectAccess`, `pin_digest`, PIN gate UI). Product direction (2026-05-19) is **session-scoped only**: one ephemeral `Project` per browser session, destroyed on home / workspace discard / purge. PINs add UX friction without a saved-project story; cross-session sharing and recovery are explicitly out of scope.

This ADR **supersedes** the access model described for **REQ-FIT-AUTH-001** in pre-2026-05-19 docs. Implementation removes PIN and saved-project code paths; **REQ-FIT-AUTH-001** is redefined as session-bound workspace access (see `docs/core/SPEC.md` update in the same change set).

## Decision drivers

- **D1:** No long-lived saved projects for end users — data is ephemeral until `Workspace.discard!` or `purge_all_ephemeral!`.
- **D2:** No PIN of any kind (user, admin UI, `pin_digest`, `verify_pin`, `fitloop.admin_pin` in deploy docs).
- **D3:** Possession of the session cookie + matching `session[:workspace_project_id]` is sufficient authorization.
- **D4:** Align live UX (setup form without PIN, `Workspace` create/bind) with architecture and tests.
- **D5:** Remove dead list-without-login + PIN gate UI (`projects#index` redirect-only).

## Considered options

1. **Keep PIN for “saved” rows, ephemeral without PIN** — Rejected: no saved projects; dual paths increase bugs (current `Workspace.resolve!` non-ephemeral branch).
2. **Replace PIN with opaque share token URL** — Rejected: out of scope; implies cross-session sharing.
3. **Session bind only (`Workspace`)** — **Chosen:** access control is implicit; no secret on the `Project` row.

## Decision outcome

**Chosen:** **Ephemeral session binding** via `Workspace` as the sole access gate for user-facing projects.

### Access model (REQ-FIT-AUTH-001)

| Concern | Rule |
|---------|------|
| **Create** | `Workspace.find_or_create!` / `create!` → `Project(ephemeral: true)`; `session[:workspace_project_id]` set via `Workspace.bind!`. |
| **Read / mutate** | Controllers resolve the project with `Workspace.resolve!(session, id)`. Return the project **only** when `session[:workspace_project_id]` matches `id` **and** the row is ephemeral and not discarded. |
| **Foreign ID** | Request for another ephemeral project ID without bind → `ActiveRecord::RecordNotFound` (or redirect to `start` with `workspace.expired` for HTML flows). |
| **Leave** | `HomeController` / explicit discard → `Workspace.discard!` (destroy project, cancel active nesting, clear session key). |
| **Abandoned** | `Workspace.purge_all_ephemeral!` removes orphan ephemeral rows (no session cookie). |

### Removed (legacy MVP)

- `projects.pin_digest`, `Project#pin=`, bcrypt validations, `scope :saved`
- `ProjectAccess`, `ProjectAccessGate`, `session[:project_access]`, `POST verify_pin`
- `pin_gate.html.erb`, PIN fields in forms, admin PIN in credentials / `DEPLOY.md`
- `Workspace.resolve!` branch that loads **non-ephemeral** `Project` by ID without session bind
- Saved-project `update` flow and list-without-login card UI (keep `GET /projects` → redirect to workspace start)

### Positive consequences

- Simpler mental model: one workspace per session, no secrets to remember or leak via digest
- Smaller attack surface (no PIN brute-force, no admin master PIN in app UI)
- Controllers and specs align with production UX path

### Negative consequences

- **No cross-device resume** without future product work (export/import, accounts, or share links — each needs its own ADR)
- **Session loss = data loss** for the in-flight project (by design)
- Existing DB rows with `ephemeral: false` / `pin_digest` require migration + optional purge in dev

## Implementation notes

- **Migration:** drop `pin_digest`; prefer `ephemeral` default `true` and eventual NOT NULL after cleanup.
- **Docs sweep (same task):** `SPEC.md` (W5, glossary, REQ-FIT-AUTH-001 detail), `SYSTEM_ARCHITECTURE.md`, `DATA_FLOW_MAP.md`, `TESTING_STRATEGY_MATRIX.md`, `SCHEMA_REFERENCE.md`, `docs/DEPLOY.md`, `docs/QA_MANUAL_CHECKLIST.md`, `docs/ROADMAP.md`.
- **Tests:** delete PIN/access specs; replace gate specs with workspace bind specs; factories ephemeral-only.

## Validation

- ADR accepted (this document).
- Follow-on steps in `task_remove-pin.md`: `workspace_spec`, `workspace_access_spec`, model migration, controller simplification, doc verifier + full regression.

## More information

- Archived session log: `.agenticguild/completed_sessions/task_remove-pin_2026-05-20.md` (decisions D1–D5)
- Prior PIN behavior: git history / ADR-0004 supersedes REQ-FIT-AUTH-001 PIN bullets in specs predating 2026-05-19
