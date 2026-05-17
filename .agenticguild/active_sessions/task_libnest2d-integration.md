<task_session>
  <metadata>
    <task_name>libnest2d-integration</task_name>
    <type>Feature</type>
    <req_id>REQ-FIT-NEST-001 (primary), REQ-FIT-NEST-002, REQ-FIT-QA-001 (deploy docs)</req_id>
    <roadmap_item>libnest2d integration — Replace Shapely rotation-sweep with libnest2d/pynest2d per ADR-0001</roadmap_item>
    <adr>docs/core/ADRs/0001-nesting-library.md</adr>
  </metadata>

  <decision_log>
    <decision id="D1" status="locked">
      <topic>Target environment (v1)</topic>
      <choice>Linux-only + CI (Ubuntu job installs native deps, runs pytest).</choice>
      <user_confirmed>2026-05-17</user_confirmed>
    </decision>
    <decision id="D2" status="locked">
      <topic>Dependency strategy</topic>
      <choice>System apt packages (cmake, Boost, build tools) + pinned pip package in requirements.txt.</choice>
      <user_confirmed>2026-05-17</user_confirmed>
      <open_spike>Validate `python-libnest2d` vs Ultimaker `pynest2d` in step 1.</open_spike>
    </decision>
    <decision id="D3" status="accepted">
      <topic>Shapely spike fallback</topic>
      <choice>Remove `nest_spike` placement path once libnest2d is green (tests + pipeline). Keep Shapely only for geometry I/O helpers if still needed (affinity, simplify in nest.py).</choice>
      <user_confirmed>Retirar cuando libnest2d esté en verde.</user_confirmed>
    </decision>
    <decision id="D4" status="locked">
      <topic>Quality vs contract</topic>
      <choice>Contract-first: stable JSON/CLI; tests on invariants not exact coordinates.</choice>
      <user_confirmed>2026-05-17</user_confirmed>
    </decision>
    <decision id="D5" status="accepted">
      <topic>Time limit</topic>
      <choice>Respect `time_limit_sec` (default 600) with best-so-far partial result per REQ-FIT-NEST-003 / REQ-FIT-JOB-001.</choice>
      <gap>Config already passes `time_limit_sec` from Rails; Python `nest.py` / `nest_multi_bin` do not yet consume it — implementation must wire cooperative timeout inside libnest2d loop AND remain compatible with Rails `Timeout.timeout` in `Nesting::JobRunner`.</gap>
      <user_confirmed>Respetar el límite actual.</user_confirmed>
    </decision>
    <decision id="D6" status="accepted">
      <topic>Integration surface (code map)</topic>
      <choice>Replace placement in `nest_bin.py` (not `nest.py` orchestration). New module e.g. `nest_libnest2d.py` behind `nest_multi_bin`. Update `capabilities()` to report libnest2d active.</choice>
      <rationale>Roadmap text says nest.py; actual solver is nest_bin → nest_spike. margin/kerf split per SYSTEM_ARCHITECTURE §7 unchanged.</rationale>
    </decision>
  </decision_log>

  <risk_matrix>
    | Risk | Mitigation |
    |------|------------|
    | PyPI package unmaintained / API mismatch | P0 spike step in start-task: evaluate `python-libnest2d` vs Ultimaker source; document choice in ADR-0001 addendum or ADR-0002 only if blocked |
    | CI without apt deps | Add workflow step installing cmake, boost, build-essential; cache venv |
    | Time cap only in Rails | Python honors `time_limit_sec` for incremental output; Rails timeout remains safety net |
    | Golden E2E brittle on coordinates | Assert status, orphan rules, file presence; avoid exact x/y |
    | Kerf/margin semantics drift | REQ-tagged tests for margin-at-edge-only and kerf buffer remain mandatory |
  </risk_matrix>

  <domain_model>
    <entity name="NestPiece">
      <responsibility>Single extractable polygon (possibly with holes) identified by index in the job.</responsibility>
      <invariants>Valid Shapely Polygon; area &gt; 0; index stable for placements.json and orphans.</invariants>
    </entity>
    <entity name="SheetStockSpec">
      <responsibility>Ordered bin definition (width, height, finite quantity or infinite).</responsibility>
      <invariants>Non-negative dimensions; sort_order unique per job; quantity null means unlimited sheets.</invariants>
    </entity>
    <entity name="Placement">
      <responsibility>Affine transform: x_mm, y_mm, rotation_deg for a piece on a sheet.</responsibility>
      <invariants>World polygon after transform stays inside usable bin (margin applied); kerf clearance vs other pieces.</invariants>
    </entity>
    <entity name="MultiBinResult">
      <responsibility>Aggregate output: sheets with placed pieces, orphans, warnings.</responsibility>
      <invariants>Orphan piece_index references valid input; each placed piece appears at most once.</invariants>
    </entity>
    <value_objects>
      <vo name="MarginMm">Non-negative sheet-edge inset only (not inter-piece gap).</vo>
      <vo name="KerfMm">Non-negative piece-to-piece clearance via buffered obstacles.</vo>
      <vo name="TimeLimitSec">Positive integer; default 600; drives partial + best-so-far.</vo>
    </value_objects>
  </domain_model>

  <architecture_notes>
    - ADR-0001: production = libnest2d; spike was proof-only.
    - Do not add nesting math to Rails.
    - After green: delete or slim `nest_spike.py` placement functions; retain tests migrated to libnest2d equivalents.
    - DEPLOY.md: add section Native nesting dependencies (apt packages, verify import, troubleshooting).
  </architecture_notes>

  <open_questions>
    <q id="Q1">Which Python binding passes the spike checklist (holes, rotation, multi-item)? Resolved in start-task spike step.</q>
    <q id="Q2">Does libnest2d expose per-iteration callback for best-so-far, or do we snapshot on timer?</q>
  </open_questions>

  <implementation_plan status="locked">
    <step id="1" status="complete">[REQ-FIT-NEST-001] Binding spike: install candidate (`python-libnest2d` first) on Linux with apt deps; write `nesting_engine/tests/test_libnest2d_binding.py` asserting import, hole polygon placement, and rotation — test fails until binding works; record chosen package + version in session notes and pin in `requirements.txt`.</step>
    <step id="2" status="complete">[REQ-FIT-NEST-001] Write failing test `test_capabilities_reports_libnest2d_production` — expects `capabilities().spike_only is False` and library name contains `libnest2d`; implement `capabilities()` in new `nest_libnest2d.py` (stub OK until step 3).</step>
    <step id="3" status="complete">[REQ-FIT-NEST-002] Write failing tests in `test_nest_libnest2d.py` for `nest_sheet(pieces, bin_w, bin_h, margin_mm, kerf_mm) → list[Placement]` — single-bin cases mirroring spike: rectangle pack, 90° rotation fit, polygon with hole; then implement adapter Shapely ↔ libnest2d.</step>
    <step id="4" status="complete">[REQ-FIT-NEST-002] Write failing tests for `nest_multi_bin` via libnest2d path: multi-sheet order, infinite quantity, kerf gap invariant, margin-at-edge-only (reuse/adapt existing `test_nest_pipeline.py` cases); switch `nest_bin.py` to call `nest_libnest2d` instead of `nest_spike._place_with_rotation`.</step>
    <step id="5" status="complete">[REQ-FIT-NEST-003] Write failing test: `run_from_config` honors `time_limit_sec` — returns partial placements + warning before hard exit; implement cooperative timer / best-so-far snapshot in `nest_multi_bin` and thread `time_limit_sec` from `nest.run_from_config`.</step>
    <step id="6" status="complete">[REQ-FIT-NEST-002] Contract regression: run `test_nest_pipeline.py` CLI fixture tests — adjust assertions to structure/invariants only (not exact x/y); confirm `placements.json` / `report.json` keys unchanged.</step>
    <step id="7" status="pending">Remove Shapely placement from `nest_spike.py` (`run_spike_nest`, `_place_with_rotation`, rotation sweep); migrate `test_nest_spike.py` to libnest2d or fold into `test_libnest2d_binding.py`; keep Shapely only where used for affinity/simplify in `nest.py` / `dxf_output`.</step>
    <step id="8" status="pending">[REQ-FIT-QA-001] Document in `docs/DEPLOY.md`: apt packages, venv install, `python -c "import …"` smoke check, CI parity note; extend `.github/workflows/ci.yml` with `nesting_engine` job (apt + pip + pytest).</step>
    <step id="9" status="pending">Update `docs/core/ADRs/0001-nesting-library.md` limits table (P3 = libnest2d active); mark roadmap item done in `docs/ROADMAP.md`.</step>
    <step id="10" status="pending">Run full suite: `.venv/bin/pytest nesting_engine/`, `bundle exec rspec spec/system/golden_nesting_e2e_spec.rb` (contract/status only).</step>
  </implementation_plan>

  <working_notes>
    2026-05-17: Spec locked — D1/D2/D4 user-confirmed; implementation_plan written for start-task handoff.
    2026-05-17: Binding spike — chose `python-libnest2d==0.1.3` (imports `pynest2d`); prebuilt manylinux wheel, no apt build on dev. Adapter: `nesting_engine/nest_libnest2d.py` (`binding_spike_nest`). CW contour + reversed hole rings for libnest2d winding. Q1 resolved for pip path; apt/cmake deferred to CI step 8.
    2026-05-17: `nest_multi_bin` lives in `nest_libnest2d`; `nest_bin` delegates via lazy import. Per-piece placement uses `_place_piece_on_sheet` → `_place_with_rotation` (margin/kerf/obstacles); `nest_sheet` is libnest2d batch path for single-bin. Step 7 will drop spike placement.
  </working_notes>
</task_session>
