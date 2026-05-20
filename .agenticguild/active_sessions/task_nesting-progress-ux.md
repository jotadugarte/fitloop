# Task: Nesting progress / status bar UX

**REQ:** REQ-FIT-JOB-001 (enhancement)  
**Roadmap:** Pending — Nesting progress / status bar UX  
**Opened:** 2026-05-18  
**Status:** Spec locked (explore-task complete → start-task)  
**Classification:** Feature  
**Roadmap item:** Nesting progress / status bar UX

---

## Problem statement

During `processing`, the progress UI stays at coarse percentages (3% → 8% → 15%) for most of the run because `Nesting::CliRunner` blocks without updating `Project#progress_percent` / `progress_message`. Users lack phase context, cancel/ETA are easy to miss, and there is no time-remaining estimate.

---

## User decisions (2026-05-18)

| # | Topic | Decision |
|---|--------|----------|
| U1 | Phase labels | **6–7 labels**, Rails-orchestrated only — **do not change** `nesting_engine` placement algorithms or phase pipeline. |
| U2 | Percentage | **B — CLI progress** (locked 2026-05-18). Engine writes `output/progress.json`; Rails polls during `CliRunner` Open3 loop. Truthful % from weighted pipeline phases + piece counts where available. |
| U3 | Cancel / ETA placement | User reports they **do not see** them — root cause: **Cancel** lives in `projects/_show_actions` (above preview); **ETA overrun** only renders inside `_nesting_progress` when `eta_overrun` is true, but `estimated_finished_at` is set to **+30s** at enqueue and is **never refreshed** during the run. |
| U4 | Accessibility | **i18n text only** — no visual stepper; improve `en`/`es` copy and `aria-valuetext` on the progress bar. |
| U5 | Time remaining | User wants **estimated time left** — feasible in Rails from `started_at`, `nesting_time_limit_sec`, and (if ticking) elapsed fraction; not “real” unless engine reports fraction done. |

---

## Architecture decisions (draft)

### D1 — Phase model (7 user-facing labels)

**Rails-only (before/after CLI):**

| # | i18n key | When |
|---|----------|------|
| 1 | `nesting.phase.queued` | Enqueue (`StartsNesting`) |
| 2 | `nesting.phase.preparing` | `NestingJob` / pre-CLI materialize + config |
| 3 | `nesting.phase.starting` | Subprocess spawned, no `progress.json` yet |

**Engine-driven (from `progress.json` `phase_id`):**

| # | i18n key | `phase_id` |
|---|----------|------------|
| 4 | `nesting.phase.extracting` | `extracting` |
| 5 | `nesting.phase.placing` | `fill` |
| 6 | `nesting.phase.optimizing` | `optimizing` |
| 7 | `nesting.phase.finishing` | `consolidating` / `refining` / `writing_outputs` (Rails may map sub-ids to one friendly label or separate keys) |

Terminal messages unchanged: `nesting.completed`, `nesting.partial`, etc.

**Constraint:** UI % and label come from `progress.json` while CLI runs; Rails must not invent higher % than engine reports.

### D2 — Progress source (**locked: B — CLI `progress.json`**)

**File:** `{output_dir}/progress.json` (atomic write: write temp + rename).

**Schema (v1):**

```json
{
  "version": 1,
  "phase_id": "fill",
  "percent": 42,
  "pieces_total": 120,
  "pieces_placed": 48,
  "message_key": null
}
```

| Field | Type | Notes |
|-------|------|--------|
| `version` | int | `1` for forward compatibility |
| `phase_id` | string | Machine id — maps to Rails i18n (see D1 table) |
| `percent` | int 0–100 | **Authoritative** for bar fill; monotonic non-decreasing within a run |
| `pieces_total` | int? | Set after extract; used for ETA heuristic in Rails |
| `pieces_placed` | int? | Updated during fill/consolidate when cheap to compute |
| `message_key` | string? | Optional override; else Rails uses `nesting.phase.{phase_id}` |

**Python write points (no algorithm changes):**

| Order | `phase_id` | When | % band (target) |
|-------|------------|------|-----------------|
| 1 | `extracting` | After `load_pieces_from_config` | 5–12 |
| 2 | `fill` | During `_nest_across_stocks` (update on sheet/piece progress) | 12–55 |
| 3 | `optimizing` | `_intra_sheet_repack_search` (both passes) | 55–72 |
| 4 | `consolidating` | `_consolidate_sheets` | 72–82 |
| 5 | `refining` | Second intra + `_inter_sheet_local_search` | 82–92 |
| 6 | `writing_outputs` | `_write_outputs` | 92–99 |
| 7 | (terminal) | Rails only — `completed` / `partial` / `failed` | 100 |

New helper: `nesting_engine/progress_reporter.py` — `ProgressReporter(path)`, `report(phase_id, percent, **kwargs)`; throttled writes (e.g. ≥1s or ≥1% delta) to avoid disk churn.

**Rails:** `Nesting::CliRunner#run_cli!` reads `progress.json` each 0.2s loop iteration → `ProgressSync.call(project:, snapshot:)` → update `progress_percent`, `progress_message` (i18n from `phase_id`), `estimated_finished_at` (ETA from pieces + elapsed), broadcast.

**cli_mock.py:** Emit stub `progress.json` stepping through phases for tests.

**Docs:** `nesting_engine/README.md` § progress.json; `docs/core/SPEC.md` REQ-FIT-JOB-001 note (amendment in start-task).

### D3 — Visibility: co-locate controls in progress panel

- Render **Cancel** inside `projects/_nesting_progress` while `processing?` (duplicate or move from `_show_actions`; prefer **single source** in progress panel + keep actions bar in sync via broadcaster).
- Render **time remaining** (`nesting.time_remaining`, e.g. “About 4 min left”) and **ETA overrun** (`nesting.eta_overrun`) in the same panel.
- Set `estimated_finished_at` at start to a **realistic** value (e.g. `started_at + nesting_time_limit_sec` or heuristic from piece count if available without Python).
- During CLI, **persist progress ticks** so `nesting_sync` poll + Turbo broadcasts refresh bar, message, and ETA.

### D4 — ProgressBroadcaster while processing

Today `ProgressBroadcaster` skips `show_actions` when `processing?` — acceptable if cancel moves to progress partial. Ensure `nesting_sync` includes cancel target or expanded progress partial locals (`active_run`, `eta_overrun`, `time_remaining`).

### D5 — i18n / a11y

- All new strings in `config/locales/en.yml` and `es.yml`.
- `aria-valuetext` combines phase label + percent + optional time remaining (no separate stepper UI).

---

## Domain model

### Project (existing)

- **Responsibility:** Aggregate nesting UX state for the workspace.
- **Fields used:** `status`, `progress_percent`, `progress_message`, `estimated_finished_at`, `nesting_time_limit_sec`.
- **Invariants:**
  - While `status == processing`, `progress_percent` is 0–99 until terminal transition.
  - `progress_message` is always a localized string key resolution (stored resolved text today — keep pattern).
- **Value objects (conceptual):** `ProgressSnapshot(percent, message_key, eta_at, phase_id)` — may stay implicit in DB columns for v1.

### NestingRun (existing)

- **Responsibility:** Per-run cancel and timestamps.
- **Invariant:** At most one `processing` run per project during active job.
- **Cancel:** `cancel_requested_at` — button must target active run id.

---

## Current code anchors

- Progress ticks: `app/services/nesting/job_runner.rb` (5%, 15% only before CLI).
- CLI block: `app/services/nesting/cli_runner.rb` (`Open3` loop 0.2s, no progress callback).
- UI: `app/views/projects/_nesting_progress.html.erb`, cancel in `app/views/projects/_show_actions.html.erb`.
- Enqueue ETA: `app/controllers/concerns/starts_nesting.rb` (`estimated_finished_at: 30.seconds` — too short).
- Poll fallback: `app/javascript/controllers/nesting_progress_sync_controller.js` + `ProjectsController#nesting_sync`.

---

## ETA copy (locked default)

`nesting.time_remaining` → “About %{count} min left” / “Quedan unos %{count} min”; after `estimated_finished_at` → `nesting.eta_overrun`. Rails computes remaining from `pieces_placed` / `pieces_total`, elapsed time, and `nesting_time_limit_sec` ceiling.

---

## Implementation plan

<implementation_plan>

<step id="1" status="complete">
**Test:** Add `nesting_engine/tests/test_progress_reporter.py` — atomic write to temp path; monotonic `percent`; throttle skips writes within 1s unless percent delta ≥ 1; invalid phase ignored. Tag `[REQ-FIT-JOB-001]`.
**Pre:** `ProgressReporter.report(phase_id, percent, **kwargs)` validates `0 <= percent <= 100`.
**Post:** File on disk is valid JSON schema v1; corrupt partial never visible (rename).
**Implement:** `nesting_engine/progress_reporter.py`.
</step>

<step id="2" status="complete">
**Test:** Add `nesting_engine/tests/test_nest_progress.py` — run `run_from_config` with tiny fixture / mock pieces; assert `output/progress.json` exists, phases advance (`extracting` → `fill` → … → `writing_outputs`), final percent ≥ 95 before outputs. Tag `[REQ-FIT-JOB-001]`, `[REQ-FIT-NEST-002]`.
**Implement:** Wire `ProgressReporter` in `nest.py` (`run_from_config`) and phase hooks in `nest_libnest2d.py` (`nest_multi_bin`, `_nest_across_stocks` piece counts, `_run_post_fill_phases` boundaries). No placement algorithm changes.
</step>

<step id="3" status="complete">
**Test:** Extend `nesting_engine/tests/test_cli_mock.py` (or add) — mock CLI emits stepped `progress.json` for bridge tests. Tag `[REQ-FIT-CLI-001]`.
**Implement:** Update `nesting_engine/cli_mock.py` to write progress steps; document `progress.json` in `nesting_engine/README.md`.
</step>

<step id="4" status="complete">
**Test:** Add `spec/services/nesting/progress_snapshot_spec.rb` — parses `progress.json` from work dir; maps `phase_id` → i18n key; rejects regressing percent; handles missing file. Tag `[REQ-FIT-JOB-001]`.
**Pre:** `Nesting::ProgressSnapshot.from_hash` / `.read(path)`.
**Post:** Returns struct with `percent`, `message`, `pieces_total`, `pieces_placed`.
**Implement:** `app/services/nesting/progress_snapshot.rb`.
</step>

<step id="5" status="complete">
**Test:** Add `spec/services/nesting/progress_sync_spec.rb` — given snapshot, updates `project.progress_percent` / `progress_message`; computes `estimated_finished_at` from pieces ratio + elapsed; does not increase percent above snapshot; broadcasts when changed. Tag `[REQ-FIT-JOB-001]`.
**Implement:** `app/services/nesting/progress_sync.rb` + `Nesting::ProgressEta` helper (private or small class).
</step>

<step id="6">
**Test:** Extend `spec/services/nesting/cli_runner_spec.rb` — invoke stub that writes `progress.json` mid-run; expect `ProgressSync` (or project DB) updates during `run_cli!` loop. Tag `[REQ-FIT-CLI-001]`, `[REQ-FIT-JOB-001]`.
**Implement:** `CliRunner#run_cli!` polls `work_dir/output/progress.json` each iteration; call `ProgressSync`; respect `cancel_check`.
</step>

<step id="7">
**Test:** Extend `spec/services/nesting/job_runner_spec.rb` — pre-CLI phases use new i18n keys (`nesting.phase.preparing`, `nesting.phase.starting`); no duplicate stale 5%/15% only. Tag `[REQ-FIT-JOB-001]`.
**Implement:** Adjust `JobRunner` progress calls to align with D1; remove conflicting percent jumps.
</step>

<step id="8">
**Test:** Extend `spec/requests/nesting_runs_spec.rb` or `starts_nesting` concern spec — `estimated_finished_at` set to `started_at + nesting_time_limit_sec` (not 30s). Tag `[REQ-FIT-JOB-001]`.
**Implement:** `StartsNesting#start_nesting_for!` ETA baseline.
</step>

<step id="9">
**Test:** Add `spec/views/projects/nesting_progress_spec.rb` (or request spec) — processing template includes cancel button (`data-testid="cancel-nesting"`), time remaining copy, `aria-valuetext` with phase + percent. Tag `[REQ-FIT-JOB-001]`, `[REQ-FIT-UI-003]`.
**Implement:** `_nesting_progress.html.erb` — co-locate cancel (needs `active_run` local), `time_remaining` / `eta_overrun`; improve `aria-valuetext`. Remove duplicate cancel from `_show_actions` during `processing?` OR keep both in sync via broadcaster.
</step>

<step id="10">
**Test:** Extend `spec/services/nesting/progress_broadcaster_spec.rb` — processing broadcasts include progress partial with `active_run` and ETA locals. Tag `[REQ-FIT-JOB-001]`.
**Implement:** `ProgressBroadcaster`, `ProjectsController#nesting_progress_locals`, `nesting_sync_streams` — pass `active_run`, `time_remaining`, ensure poll path refreshes ETA.
</step>

<step id="11">
**Test:** Extend `spec/system/nesting_progress_spec.rb` — with cli_mock or stub progress file, assert phase message changes and percent increases during processing (not stuck at 15%). Tag `[REQ-FIT-JOB-001]`, `[REQ-FIT-QA-001]`.
**Implement:** Any Stimulus/sync tweaks if needed; do not assert golden coordinates.
</step>

<step id="12">
**Test:** Locale keys exist in `spec/i18n/nesting_phase_labels_spec.rb` (or i18n smoke) — all `nesting.phase.*` and `nesting.time_remaining` in `en` and `es`. Tag `[REQ-FIT-UI-003]`.
**Implement:** `config/locales/en.yml`, `config/locales/es.yml` — professional copy for queued, preparing, starting, extracting, placing, optimizing, consolidating, refining, writing_outputs.
</step>

<step id="13">
**Test:** Amend `docs/core/SPEC.md` REQ-FIT-JOB-001 bullet — CLI `progress.json`, live percent, ETA copy, cancel in progress panel. Tag `[REQ-FIT-JOB-001]`, `[REQ-FIT-SPEC-001]`.
**Implement:** SPEC + `nesting_engine/README.md` cross-link; mark `docs/ROADMAP.md` item done when shipped.
</step>

<step id="14">
**Test:** Run targeted `bundle exec rspec` (nesting services, system nesting_progress) + `pytest nesting_engine/tests/test_progress_reporter.py nesting_engine/tests/test_nest_progress.py -q`.
**Implement:** Fix regressions; no commit from agent unless user asks.
</step>

</implementation_plan>
