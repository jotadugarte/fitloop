# Task: remove-pin (ephemeral-only access)

**Roadmap:** Eliminar todo rastro del uso de PIN en la app (`docs/ROADMAP.md` Pending)

**Classification:** Refactor (remove legacy auth + saved-project path)

**Status:** Spec locked — handoff to `start-task`

---

## Decision log

| ID | Decision | Source | Date |
|----|----------|--------|------|
| D1 | **No saved projects.** Fitloop is session-scoped: one ephemeral `Project` per browser session, destroyed on `Workspace.discard!` / home / session expiry. No long-lived “saved” projects for end users. | Product owner | 2026-05-19 |
| D2 | **No PIN of any kind** (user 6-digit, admin master, gate UI, `pin_digest`). Access control is implicit: only the session-bound workspace project is reachable. | D1 | 2026-05-19 |
| D3 | **Replace REQ-FIT-AUTH-001** via ADR: document ephemeral session binding as the access model (not PIN). Update `SPEC.md`, `SYSTEM_ARCHITECTURE.md`, `DATA_FLOW_MAP.md`, `TESTING_STRATEGY_MATRIX.md`, `DEPLOY.md` (remove admin PIN credentials). | Roadmap + D1–D2 | 2026-05-19 |
| D4 | **Remove saved-project code path** in the same task: `ephemeral: false`, PIN form branch, non-ephemeral `Workspace.resolve!`, related specs. | Product owner | 2026-05-19 |
| D5 | **Remove dead `projects#index` UI** (index view, `_project_card`, orphaned i18n); keep `GET /projects` → redirect to `start` or equivalent. | Product owner (Option A) | 2026-05-19 |

---

## Codebase reality check (2026-05-19)

**Already aligned with D1 in the live UX path:**

- `Workspace` creates `Project(ephemeral: true)`; `HomeController` calls `discard!` + `purge_all_ephemeral!`.
- Setup uses `_setup_form.html.erb` — **no PIN field** (`ephemeral_workspace_spec` asserts this).
- `finish_ephemeral_setup` keeps project ephemeral; binds session; no PIN.

**Legacy / dead paths still in repo (to remove with this task):**

| Area | What to remove or simplify |
|------|----------------------------|
| `Project` | `pin_digest`, `pin=`, bcrypt, `authenticate_pin`, `valid_pin_format?`, `scope :saved`, PIN validations |
| `ProjectAccess` service | Entire file |
| `ProjectAccessGate` | Gate render, `verify_pin`, `session[:project_access]` (if only used for PIN) |
| Routes | `post :verify_pin` |
| Views | `pin_gate.html.erb`, PIN field in `_form.html.erb`, `edit` branch for non-ephemeral |
| `ProjectsController` | `verify_pin`, `pin_gate_request?`, saved-project `update` branch, redundant `grant_project_access!` / gate checks on ephemeral |
| `Workspace.resolve!` | Branch that loads non-ephemeral project by ID without session bind |
| DB | Migration: drop `pin_digest` |
| Credentials / deploy | `fitloop.admin_pin` references |
| i18n | PIN / access gate strings (`en`/`es`) |
| Specs | `project_pin_spec`, `project_access_spec`, `project_access_gate_spec`, `unlock_project_for_spec!`, factories defaulting `ephemeral: false` + `pin:` |
| Docs | PIN mentions in architecture header, W5, REQ-FIT-AUTH-001 detail |

**Note:** `projects#index` view exists but controller **redirects to `start_project_path`** — list-without-login + PIN gate was MVP design; product is now workspace-only. Index/card UI may be removable or left for a separate cleanup (confirm in finalize).

---

## Domain model

### Workspace (session aggregate)

- **Responsibility:** Own the single ephemeral project ID in `session[:workspace_project_id]`; create, bind, discard, purge abandoned ephemerals.
- **Invariants:**
  - At most one bound ephemeral project per session.
  - `resolve!(session, id)` only returns a project if `id` matches session bind **and** `project.ephemeral?`.
  - Discarding destroys the project row and cancels active nesting.

### Project (ephemeral persistence)

- **Responsibility:** Hold in-session DXF inputs, sheet stock, layers, nesting state until destroyed.
- **Invariants:**
  - All user-facing projects have `ephemeral: true` (consider DB default + NOT NULL after cleanup).
  - No `pin_digest`; no access secret on the row.
  - Title/sheet stocks required only when completing setup (existing ephemeral validations).

### Access (no domain service)

- **Model:** Possession of session cookie + matching `workspace_project_id` is sufficient to read/write the workspace project.
- **Non-goals:** Cross-session sharing, PIN recovery, admin override via app UI.

---

## Risks (execution)

- **`session[:project_access]`:** Remove with gate; access = `Workspace.resolve!` only.
- **Existing DB rows:** Migration drops `pin_digest`; data migration or `Workspace.purge_all!` in dev for legacy `ephemeral: false` rows.
- **Specs:** Large sweep — factory defaults to ephemeral-only; delete `unlock_project_for_spec!`.

---

## Baseline (2026-05-19, start-task step 3.1)

| Suite | Command | Result |
|-------|---------|--------|
| Rails | `bundle exec rspec` | **203 examples, 17 failures** (~1m 25s) |
| Engine | `.venv/bin/pytest nesting_engine/tests -q -m "not slow"` | **121 passed**, 1 deselected (~1m 43s) |

**RSpec failures (all):** `ephemeral_workspace_spec:19` (422 on setup), `nesting_start_workspace_spec:8`, `project_orphan_dxf_download_spec` (×3), `project_preview_spec` (×3, 302 pin-gate redirect), `project_nesting_parameters_spec` (×2), `project_layers_spec:74`, `nesting_renest_after_sheet_edit_spec:8`, `project_pin_spec:21`, `sheet_inventory_priority_spec` system (×4).

**Hypothesis:** Most request failures look like missing workspace bind / PIN gate redirect (`302`) or setup `422`; system specs may need a display/browser. Engine suite is green. Baseline is **not** fully green — confirm whether to fix env/pre-existing reds before step 2, or proceed with removal TDD accepting transient reds.

---

## Implementation plan

<implementation_plan>

<step id="1" status="complete">
**Test:** Run existing suites to establish green baseline: `bundle exec rspec` and `pytest nesting_engine/tests` (exclude slow if needed). Record pass counts in session note.
</step>

<step id="2" status="complete">
**Test:** N/A (documentation gate). **Implement:** Add `docs/core/ADRs/0004-ephemeral-session-access.md` (Accepted) — replaces PIN model: one ephemeral `Project` per session via `Workspace`; no saved projects; no `pin_digest`; access by session bind only. Tags `[REQ-FIT-AUTH-001]`.
</step>

<step id="3" status="complete">
**Test:** Rewrite `spec/services/workspace_spec.rb` — `resolve!` returns project only when `session[:workspace_project_id]` matches and project is ephemeral; unknown ID or non-bound ephemeral → `RecordNotFound`; remove examples for `ephemeral: false` by ID. Tag `[REQ-FIT-AUTH-001]`.
**Implement:** Simplify `Workspace.resolve!` (drop non-ephemeral public lookup branch).
</step>

<step id="4" status="complete">
**Test:** Replace `spec/requests/project_access_gate_spec.rb` with `spec/requests/workspace_access_spec.rb` — GET `project_path` without session bind → redirect to `start` with `workspace.expired` (or 404); bound session → show without pin-gate markup. Remove `verify_pin` examples. Tags `[REQ-FIT-AUTH-001]`, `[REQ-FIT-UI-003]`.
**Implement:** Delete `ProjectAccess`, `ProjectAccessGate` (or replace with thin `WorkspaceAccess` that only checks bind), `verify_pin` action/route, `pin_gate.html.erb`; remove `session[:project_access]` usage; simplify `ProjectsController` show/nested_dxf/nesting_sync (no gate renders).
</step>

<step id="5" status="complete">
**Test:** `spec/models/project_spec.rb` (or migrate from `project_pin_spec`) — ephemeral project has no PIN validations; `pin_digest` absent from schema after migration. Tag `[REQ-FIT-DOM-001]`, `[REQ-FIT-AUTH-001]`.
**Implement:** Migration `remove_pin_digest_from_projects`; remove PIN methods/validations/`scope :saved` from `Project`; default `ephemeral: true` if not already; delete `spec/models/project_pin_spec.rb`, `spec/services/project_access_spec.rb`.
</step>

<step id="6" status="pending">
**Test:** `spec/requests/ephemeral_workspace_spec.rb` — unchanged green; add assertion foreign `project_path(other_ephemeral_id)` fails without bind. Tag `[REQ-FIT-AUTH-001]`.
**Implement:** Controllers: drop redundant `grant_project_access!` / `require_project_access!` callbacks; use `SetsWorkspaceProject` + bind check only; remove saved-project `update` branch and `project_params :pin`.
</step>

<step id="7" status="pending">
**Test:** Adjust `spec/requests/i18n_views_spec.rb` and `spec/requests/ui_design_spec.rb` — no PIN strings; `projects_path` still redirects to start. Tags `[REQ-FIT-UI-003]`, `[REQ-FIT-UI-005]`.
**Implement:** Delete `app/views/projects/index.html.erb`, `_project_card.html.erb`, `_form.html.erb` (if unused), `edit` non-ephemeral branch; remove `projects.index.*` and `projects.access.*` / `activerecord.attributes.project.pin` i18n keys; keep `projects#index` as redirect-only.
</step>

<step id="8" status="pending">
**Test:** Update `spec/support/project_spec_factory.rb` — `create_project_for_spec!` always ephemeral, no `pin:` kwarg; remove `spec/support/project_access_helper.rb` and all `unlock_project_for_spec!` call sites (grep-driven sweep). Tags `[REQ-FIT-QA-001]`.
**Implement:** Factory + system/request specs use `bind_workspace_session!` only.
</step>

<step id="9" status="pending">
**Test:** `lib/spec_doc_verifier.rb` / architecture doc test still pass after doc edits. Tags `[REQ-FIT-ARCH-001]`, `[REQ-FIT-AUTH-001]`.
**Implement:** Update `docs/core/SPEC.md` (W5, Project fields, REQ-FIT-AUTH-001 detail), `SYSTEM_ARCHITECTURE.md` (stack blurb, secrets §4), `DATA_FLOW_MAP.md` (access flow), `TESTING_STRATEGY_MATRIX.md`, `SCHEMA_REFERENCE.md`, `docs/DEPLOY.md`, `docs/QA_MANUAL_CHECKLIST.md`; mark roadmap item in `docs/ROADMAP.md` when shipped.
</step>

<step id="10" status="pending">
**Test:** Full regression — `bundle exec rspec`, `pytest nesting_engine/tests`, tag slow system spec `golden_nesting_e2e` if feasible. Tags `[REQ-FIT-QA-001]`.
**Implement:** Fix any stragglers; grep repo for `pin_digest`, `verify_pin`, `ProjectAccess`, `pin_gate`, `admin_pin` — zero hits outside ADR/history.
</step>

</implementation_plan>
