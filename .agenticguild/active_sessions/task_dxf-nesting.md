<task_session>
  <metadata>
    <task_name>DXF Sheet Nesting Web App</task_name>
    <slug>dxf-nesting</slug>
    <type>Feature (Greenfield)</type>
    <status>spec-locked</status>
    <classification>Feature (Greenfield)</classification>
    <roadmap_item>P1 — Domain &amp; access</roadmap_item>
    <scope_note>P0 complete 2026-05-16. Executing P1 steps 6–8 (models, PIN, project CRUD UI).</scope_note>
  </metadata>

  <vision>
    Web app in <code>fitloop</code> (Rails 8 + Hotwire + PostgreSQL): nesting projects with
    ordered sheet inventory (finite + ∞), multi-DXF, layer checklist, 6-digit project PIN,
    10-digit admin master PIN, Python nesting engine, live progress, nested DXF + preview.
    v1.1 adds auto-split for oversized pieces (curved geometry, preview before apply).
  </vision>

  <decision_log>
    <decision id="D1"><topic>Units</topic><choice>Millimeters.</choice></decision>
    <decision id="D2"><topic>Pieces</topic><choice>Closed contour on selected layer = 1 piece; INSERT on selected layer = 1 piece (geometry from block, transformed, not exploded to loose entities).</choice></decision>
    <decision id="D2b"><topic>Nested blocks (v1)</topic><choice>Resolve INSERT recursively up to depth 8; geometry from nested block defs transformed into world space. If depth exceeded or missing block def → skip entity + warning in job report. (Architect recommendation accepted.)</choice></decision>
    <decision id="D3"><topic>Rotation</topic><choice>Any angle.</choice></decision>
    <decision id="D4"><topic>Duplicates</topic><choice>N geometric instances = N pieces.</choice></decision>
    <decision id="D5"><topic>Access</topic><choice>User chooses 6-digit PIN at project creation (validated, stored hashed). Admin 10-digit master PIN in Rails credentials unlocks any project. No PIN recovery for users.</choice></decision>
    <decision id="D24"><topic>Product name</topic><choice>Fitloop (UI branding).</choice></decision>
    <decision id="D25"><topic>i18n</topic><choice>Rails I18n: Spanish + English in v1; locale files structured for additional locales later. Error messages and UI copy translated.</choice></decision>
    <decision id="D26"><topic>Job status UX</topic><choice>Distinct statuses: completed | partial | failed (user confirmed 2026-05-16).</choice></decision>
    <decision id="D6"><topic>Outputs</topic><choice>Nested DXF + browser preview from placements.json.</choice></decision>
    <decision id="D7"><topic>Multi-DXF</topic><choice>Many inputs per project, single nesting run.</choice></decision>
    <decision id="D8"><topic>Output DXF layout</topic><choice>One file; each used sheet as rectangle, offset +X (default gap 15mm).</choice></decision>
    <decision id="D9"><topic>Repo</topic><choice>Greenfield inside fitloop.</choice></decision>
    <decision id="D10"><topic>Nesting</topic><choice>Option B — irregular polygon nesting, iterative, time-capped with best-so-far.</choice></decision>
    <decision id="D11"><topic>Kerf</topic><choice>Per-project, default 0 mm.</choice></decision>
    <decision id="D12"><topic>Margin</topic><choice>Per-project, default 5 mm.</choice></decision>
    <decision id="D13"><topic>Holes</topic><choice>Hole-aware.</choice></decision>
    <decision id="D14"><topic>Curves</topic><choice>Tessellate; tolerance per project, default 0.1 mm.</choice></decision>
    <decision id="D15"><topic>Limits</topic><choice>No hard file/piece caps v1.</choice></decision>
    <decision id="D16"><topic>Layers UX</topic><choice>Checkbox list = union of layer names from all uploaded DXFs.</choice></decision>
    <decision id="D17"><topic>Sheet inventory</topic><choice>Multiple stocks (w×h, qty finite or ∞). User sets consumption order in UI (drag sort). Engine consumes in that order; finite sheets before using next stock type per sorted list.</choice></decision>
    <decision id="D18"><topic>Min area</topic><choice>None v1.</choice></decision>
    <decision id="D19"><topic>Job UX</topic><choice>Progress bar + ETA; user waits. Hidden safety time cap (default 600s); if exceeded, return best-so-far + notify user job hit time limit. Cancel button. If job runs longer than ETA, show message that it is still working.</choice></decision>
    <decision id="D20"><topic>Re-process</topic><choice>Allow "Volver a anidar" on same project; new NestingRun; results may vary slightly between runs.</choice></decision>
    <decision id="D21"><topic>Orphans / partial (OD3)</topic><choice>Rare with ∞ stock, but v1 policy: export best placement + job report listing orphans (reason codes). v1 orphan reasons: piece larger than max sheet (no split yet), engine timeout, unparseable entity, missing block. v1.1 split reduces oversized orphans.</choice></decision>
    <decision id="D22"><topic>Auto-split</topic><choice>Deferred to v1.1 — not in initial MVP. v1.1: split oversized pieces (curved outlines, not only rectilinear), fewest parts, material-efficient; user preview of split lines before final nest; split lines in output DXF; labels Pieza-1a, Pieza-1b.</choice></decision>
    <decision id="D23"><topic>Pre-flight validation</topic><choice>Block job if no layers selected or zero extractable pieces (i18n error messages).</choice></decision>
    <decision id="D27"><topic>Python bridge v1</topic><choice>CLI (config.json + file paths). Engine packaged as importable modules; FastAPI wrapper deferred.</choice></decision>
  </decision_log>

  <why_orphans_with_infinite_sheets>
    With ∞ sheets, <em>quantity</em> is not the limit. Pieces can still be unplaced when:
    (v1) Polygon bounding box or actual geometry exceeds largest sheet and auto-split is not available yet.
    Engine hits safety time cap before placing remaining pieces (partial result).
    Invalid/unreadable geometry skipped earlier.
    (v1.1+) Split algorithm cannot find a feasible cut (pathological shape) — rare.
    Therefore partial export + orphan report remains a safety net, not because you "run out" of ∞ sheets.
  </why_orphans_with_infinite_sheets>

  <architecture_confirmed date="2026-05-16">
    <web>Ruby on Rails 8 + Hotwire (Turbo/Stimulus) + PostgreSQL + Active Storage + Solid Queue (background jobs).</web>
    <nesting_engine>Python 3 service invoked from ActiveJob (CLI v1; optional FastAPI microservice later). Libraries: ezdxf, Shapely, libnest2d (or equivalent per spike).</nesting_engine>
    <bridge>Rails writes config JSON + temp DXF paths → Python returns nested DXF + placements.json + report.json → Rails attaches files and broadcasts Turbo Stream.</bridge>
    <not_in_scope>Rails does not perform nesting math; Python does not serve HTML or own project persistence.</not_in_scope>
  </architecture_confirmed>

  <phasing>
    <mvp_v1>
      Rails app, models, Active Storage, Solid Queue, Hotwire progress.
      Project CRUD, SheetStock ordering UI, layer checklist, multi-DXF upload.
      PIN + admin PIN, pre-flight validations.
      Python CLI: extract → nest (libnest2d spike) → DXF + placements.json + report.json.
      Re-nest, preview SVG, download.
      Oversized-for-sheet → orphan in report (no split).
    </mvp_v1>
    <v1_1>
      Split planner for oversized pieces (curved polygons), preview UI, apply splits then nest.
    </v1_1>
  </phasing>

  <risk_matrix>
    | Risk | Mitigation |
    |------|------------|
    | Non-deterministic nest | Document; re-nest button |
    | Long jobs | 600s cap, cancel, notify when past ETA |
    | Nested blocks | Depth limit 8, report skips |
    | libnest2d holes/any-angle | Early spike in start-task |
    | Master PIN | credentials, rate limit |
  </risk_matrix>

  ## Domain Model

  ### Project
  - Invariants: title present; ≥1 SheetStock; ≥1 selected layer; pin 6 digits; on completed/partial has nested_dxf unless failed validation-only
  - Fields: title, pin_digest, kerf_mm (0), margin_mm (5), curve_tolerance_mm (0.1), sheet_gap_mm (15), nesting_time_limit_sec (600), status enum (draft|ready|processing|completed|partial|failed), progress_percent, progress_message, timestamps
  - Attachments: many input_dxf, one nested_dxf

  ### SheetStock
  - width_mm, height_mm, quantity (null=∞), sort_order (user priority)

  ### ProjectLayer
  - layer_name, included boolean

  ### NestingRun
  - project_id, params snapshot, status, started_at, finished_at, report_json, links to result blob

  ### Piece (runtime)
  - polygon with holes, mm, source ref, optional parent_piece_id after v1.1 split

  ### Branded types (approved 2026-05-16; reconfirmed for P1 2026-05-16)
  - `Millimeters` — distances (kerf, margin, sheet gap, curve tolerance)
  - `Degrees` — piece rotation in nesting
  - `ProjectId` — project identifier
  - `PieceId` — runtime piece identifier
  - `Pin6` — user project PIN (6 digits, chosen at create)
  - `AdminPin10` — admin master PIN (10 digits, Rails credentials)

  <implementation_plan>
    <phase name="P0 — Anchors &amp; toolchain" goal="Lock architecture docs and dev environment">
      <step id="1" status="complete">Write failing spec: `docs/core/SYSTEM_ARCHITECTURE.md` lists Rails 8 + Hotwire + PostgreSQL + Solid Queue and forbids nesting math in Ruby (test via audit script or docs lint if present; else checklist in session).</step>
      <step id="2" status="complete">Populate `docs/core/SPEC.md` with REQ-FIT-001..00N covering project PIN, sheet inventory, layer filter, nesting statuses (completed|partial|failed), CLI contract.</step>
      <step id="3" status="complete">Scaffold Rails 8 app in repo root: PostgreSQL, Hotwire, Active Storage, Solid Queue, i18n (en, es). Write failing request spec for Fitloop home → make pass.</step>
      <step id="4" status="complete">Add `nesting_engine/` Python package + `requirements.txt` + pytest. Write failing test: read sample DXF fixture → extract ≥1 closed contour on selected layer → make pass (ezdxf + Shapely).</step>
      <step id="5" status="complete">Spike: libnest2d (or fallback) with hole + rotation; record ADR `docs/core/ADRs/0001-nesting-library.md` with chosen lib and limits.</step>
    </phase>
    <phase name="P1 — Domain &amp; access" goal="Projects, stocks, PIN">
      <step id="6" status="complete">Write failing model specs: Project (title, pin_digest, kerf/margin/tolerance defaults), SheetStock (w, h, qty nullable, sort_order), ProjectLayer, NestingRun → implement migrations/models.</step>
      <step id="7" status="complete">Write failing specs: user PIN validation (6 digits, chosen at create, bcrypt); admin master PIN from credentials unlocks project → implement `ProjectAccess` service.</step>
      <step id="8" status="pending">Write failing system spec: create project (title, user PIN), add ordered SheetStock rows (finite + ∞), assert sort_order persisted → CRUD UI with Stimulus sortable.</step>
    </phase>
    <phase name="P2 — Inputs" goal="DXF upload &amp; layer discovery">
      <step id="9" status="pending">Write failing spec: attach multiple DXF via Active Storage; union layer names endpoint/view → implement direct upload + layer checklist (i18n).</step>
      <step id="10" status="pending">Write failing spec: pre-flight rejects zero layers selected / zero pieces (i18n errors) → implement `ProjectReadinessValidator` calling Python extract dry-run or Ruby layer scan.</step>
      <step id="11" status="pending">Write failing Python tests: INSERT on selected layer (no explode), nested blocks depth≤8, missing block → report warning; tessellation tolerance 0.1mm → implement extractor.</step>
    </phase>
    <phase name="P3 — Nesting pipeline" goal="CLI bridge, job, outputs">
      <step id="12" status="pending">Define CLI contract JSON schema in `nesting_engine/README.md`. Write failing job spec: `NestingJob` writes config + invokes CLI mock → attaches `nested.dxf` → implement job + `Nesting::CliRunner`.</step>
      <step id="13" status="pending">Write failing Python tests: multi-bin nest (ordered SheetStock, ∞ creates new sheets), kerf/margin, outputs placements.json + report.json (orphans, warnings) → implement nest + DXF writer (sheet rectangles offset on X, gap 15mm).</step>
      <step id="14" status="pending">Write failing spec: status completed vs partial vs failed from report; oversized piece → orphan in v1 → integrate real CLI.</step>
      <step id="15" status="pending">Write failing system spec: Turbo Stream progress updates (percent, message, ETA overrun text); 600s cap returns partial + notice; cancel job → implement broadcast + cancel.</step>
    </phase>
    <phase name="P4 — UX completion" goal="Preview, re-nest, polish">
      <step id="16" status="pending">Write failing spec: SVG/canvas preview from placements.json matches sheet count → implement preview partial.</step>
      <step id="17" status="pending">Write failing spec: "Re-nest" creates new NestingRun, replaces downloadable result → implement button + history list.</step>
      <step id="18" status="pending">Write failing spec: download nested DXF; project list/history without login; PIN gate on show → polish Fitloop UI (en/es).</step>
      <step id="19" status="pending">End-to-end test with golden sample DXF + manual QA checklist; update ROADMAP; document deploy (Rails + Python venv on same host).</step>
    </phase>
    <phase name="P5 — v1.1 (deferred)" goal="Auto-split">
      <step id="20" status="pending">ADR + failing tests for curved polygon split planner; preview UI; apply splits then nest — out of v1 scope until v1 ships.</step>
    </phase>
  </implementation_plan>

  <working_notes>
    2026-05-16 Round 5: OD3=partial+orphans safety net; job cap+cancel+notify; reprocess yes;
    nested blocks recursive depth 8; split v1.1 with curves+preview; validations confirmed.
    2026-05-16 Round 6: Fitloop branding; i18n en+es; user-created PIN; completed vs partial explained.
    2026-05-16 PROCEED: implementation_plan finalized; D27 CLI v1; handoff to start-task.
  </working_notes>
</task_session>
