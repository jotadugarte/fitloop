<task_session>
  <metadata>
    <task_name>Merge setup into workshop (contextual UX modes)</task_name>
    <type>Feature</type>
    <req_id>REQ-FIT-UI-001, REQ-FIT-UI-003, REQ-FIT-AUTH-001 (W1, W5)</req_id>
    <roadmap_item>UX polish — eliminate Parámetros iniciales intermediate page</roadmap_item>
    <created>2026-05-30</created>
    <status>Locked — execution in progress</status>
  </metadata>

  ## Problem statement

  Today the ephemeral funnel is **Inicio → EMPEZAR → Parámetros iniciales (`/projects/new`) → Continuar → Mi taller (`/taller`)**. Setup and workshop duplicate láminas, DXF upload, and nesting parameters. Recent UI work aligned láminas styling across both pages; the intermediate page adds friction without distinct capability.

  **Goal:** Single screen at `/taller` with **contextual UX** — setup guidance for first-time configuration, full workshop UX after the user has started nesting.

  ## Approved direction (user 2026-05-30)

  > Fusionar, pero con UX contextual. No basta con redirigir `/empezar` → `/taller` y borrar `/projects/new`.

  ### Modo setup (`draft`, sin anidado aún)

  - **Orden vertical:** láminas → parámetros de anidado → archivos DXF.
  - **Collapsibles abiertos:** solo **Inventario de láminas** y **Detalle DXF** (`<details open>`).
  - **Parámetros de anidado:** siempre visibles entre láminas y DXF — **sin** `<details>` (no colapsables en setup).
  - Welcome con pasos actuales de `projects.setup.welcome` (sin «Continuar»; último paso → «Iniciar anidado»).
  - Ocultar o atenuar **Vistas previas / progreso** hasta el primer anidado.
  - **«Iniciar anidado»:** si faltan láminas, DXF, capas, etc. → **flash/error** (no deshabilitar el botón).

  ### Modo taller (`ready` / ya anidado / post–first-run)

  - Comportamiento actual de Mi taller.
  - Paneles colapsados por defecto per **REQ-FIT-UI-003** (`workshop-sheet-inventory`, `workshop-source-dxf-detail`).
  - Preview + huérfanos visibles.

  ```mermaid
  flowchart LR
    A[EMPEZAR] --> B[/taller]
    B --> C{workshop_setup_mode?}
    C -->|sí| D[Modo setup]
    C -->|no| E[Modo taller]
    D --> F[Láminas + DXF abiertos]
    D --> F2[Parámetros visibles sin colapsar]
    D --> G[Welcome setup 3-4 pasos]
    D --> H[Preview/progreso ocultos o atenuados]
    E --> I[Paneles colapsados REQ-FIT-UI-003]
    E --> J[Preview + huérfanos visibles]
  ```

  ## Decision log

  | ID | Decision | Rationale |
  |----|----------|-----------|
  | D1 | **Predicate:** `Project#workshop_setup_mode?` → `draft? && nesting_runs.none?` | Matches «draft, sin anidado aún»; first `NestingRunsController#create` flips to taller UI via `processing` + run row. Re-nest after discard+empezar resets to setup. |
  | D2 | **`projects#start`:** `Workspace.discard!` → `find_or_create!` → redirect `workshop_path` | Preserves discard-on-restart; lands directly in workshop. |
  | D3 | **Remove** `GET/POST /projects/new`, `projects#create`, `projects#edit`, `finish_ephemeral_setup`, setup views | Single source of truth at `/taller`. |
  | D4 | **Remove** `GET /projects/new` (and `create`/`edit`) — **no legacy redirect**. App not live; no bookmarks to preserve. `resources :projects` trimmed to `index` only (redirects to empezar/taller) or removed entirely if unused. | User 2026-05-30: «Borrar y ya.» |
  | D5 | **Status `ready`:** Set in `StartsNesting#start_nesting_for!` when leaving `draft` (before `processing`), OR drop `ready` as a distinct pre-nest state and rely on `draft` until nest. **Recommend:** set `ready` immediately before `processing` on first nest only if needed for analytics; UI uses `workshop_setup_mode?`, not `ready?`. Document in SPEC W1. |
  | D6 | **Toolbar `Mi taller`:** Always `workshop_path`; `projects#show` auto-creates via `find_or_create!` when unbound (same as today’s `new` side effect). | Eliminates `/empezar` hop from nav when no session. |
  | D7 | **Collapsible persistence:** Extend `collapsible_persistence_controller.js` — `lockedClosedOnPath` applies only when **not** setup mode (pass `data-workshop-setup-mode` on `<main>` or check server-rendered `open` on details). | REQ-FIT-UI-003 preserved for returning users; setup mode opens panels via HTML `open` attribute + skip lock. |
  | D8 | **Nesting parameters (setup):** Inline section between láminas and DXF — reuse `_nesting_settings` inside a static `fit-section` / `panel--inset` (no `<details>`). **Taller mode:** unchanged collapsed `_nesting_parameters` at bottom. | User Q1/Q4: params visible but not collapsible; only láminas + DXF use open collapsibles. |
  | D11 | **Zero sheet stocks:** On «Iniciar anidado», redirect with **alert** (explicit check before/at readiness). Do not disable button. | User Q2. Extend `ProjectReadinessValidator` or `NestingRunsController` with `no_sheet_stocks` i18n for ephemeral. |
  | D9 | **No new DB columns** | Mode is derived from `status` + `nesting_runs` count. |
  | D10 | **SPEC + ADR-0004 addendum** | W1 step 2 changes; document intentional removal of setup page. |

  ## Domain model

  No new persisted entities. Behavioral contract:

  ### Project (extended predicate)

  - **`workshop_setup_mode?`** (new instance method)
    - **Invariant:** true only when `status == draft` AND `nesting_runs` is empty.
    - **False when:** any nesting run exists OR status is not `draft`.

  ### WorkshopUxMode (value object — view/helper layer, not AR)

  - Wraps `project` + `workshop_setup_mode?`
  - **Methods:** `#setup?`, `#taller?`, `#show_preview_zone?`, `#show_progress?`, `#default_open_panels`, `#welcome_i18n_key`
  - Lives in helper or small PORO under `app/models/` or `app/presenters/` — prefer **`Workshop::UxMode`** presenter to keep views thin.

  ### Existing invariants unchanged

  - `ProjectReadinessValidator` gates nest start (REQ-FIT-VAL-001).
  - Sheet inventory rules (finite before ∞, at most one unlimited) unchanged.
  - Ephemeral bind via `Workspace` (W5).

  ## Current codebase touchpoints

  | File | Role today | Change |
  |------|------------|--------|
  | `projects_controller#start` | discard → `new_project_path` | discard → create → `workshop_path` |
  | `projects_controller#new/edit/update/create` | Setup form + `finish_ephemeral_setup` | Remove or gut; `update` may remain for legacy — redirect |
  | `show.html.erb` | Always full workshop | Conditional sections via `Workshop::UxMode` |
  | `_show_welcome.html.erb` | Show steps | Branch setup vs show steps |
  | `_show_sheet_inventory.html.erb` | Collapsed default | `open` when setup mode |
  | `_show_source_dxf_detail.html.erb` | Collapsed default | `open` when setup mode |
  | `_show_preview_zone.html.erb` | Always visible | Hidden or `project-show__preview-zone--muted` in setup |
  | `_nesting_progress` section in show | Always visible | Hidden in setup |
  | `_setup_form.html.erb`, `new.html.erb` | Setup page | Delete |
  | `collapsible_persistence_controller.js` | Locks workshop panels closed | Respect setup mode |
  | `application_helper#toolbar_workshop_path` | → `start_project_path` if unbound | → `workshop_path` |
  | `config/routes.rb` | `resources :projects, only: [:index, :new, :create]` | Remove `new`/`create`; drop or minimal `index` → empezar |
  | `config/locales/es.yml` | setup welcome mentions Continuar | Rewrite step 4 → «Iniciar anidado» |
  | `spec/requests/ephemeral_workspace_spec.rb` | Asserts setup page | Assert workshop setup mode |
  | `docs/core/SPEC.md` W1 | Step 2 setup form | Step 2 workshop setup mode |

  ## Risk matrix

  | Risk | Impact | Mitigation |
  |------|--------|------------|
  | First visit feels crowded | Medium | Hide preview/progress; open only láminas+DXF; setup welcome |
  | Collapsible JS overrides `open` | High | Setup mode bypass in `lockedClosedOnPath`; test system spec |
  | Specs assume `/projects/new` | Medium | Bulk update request/system specs |
  | Paywall/download flows use `new_project_path` | Medium | Audit grep; redirect or workshop |
  | `finish_ephemeral_setup` layer apply on monolithic submit | Low | Layers already applied via per-file «Aplicar capas» in workshop |
  | Missing DXF error only on Continuar today | Low | `NestingRunsController` already redirects with readiness errors; add sheet-stock check if zero sheets |
  | `es_panic` locale parity | Low | Mirror `es.yml` key changes |

  ## Resolved questions (user 2026-05-30)

  | # | Question | Decision |
  |---|----------|----------|
  | Q1 | Parámetros en setup | **Visibles y abiertos** — sección fija (no collapsible). |
  | Q2 | Cero láminas | **Mostrar error** al pulsar «Iniciar anidado». |
  | Q3 | Bookmark `/projects/new` | **Eliminar ruta** — sin redirect (app no en vivo). |
  | Q4 | Orden | **Láminas → parámetros → DXF.** Solo láminas y DXF con collapsible **abierto**; parámetros sin colapsar. |

  ### Q3 — Qué significaba (en simple)

  ~~La ruta antigua `/projects/new` dejaría de existir.~~ **Decisión final:** borrar `/projects/new`, `create`, `edit` y vistas setup — **sin redirect 301**. No hay usuarios en producción con favoritos.

  ## Out of scope

  - Multi-step wizard / stepper UI.
  - Persisting projects list.
  - Changes to nesting engine or billing.

  ## Test strategy (REQ-tagged)

  - Request: `ephemeral_workspace_spec` — EMPEZAR lands on `/taller` with setup mode markers (`data-workshop-setup-mode="true"`, setup welcome, no preview zone).
  - Request: first nest transitions UI (re-render or follow-up GET) to taller mode markers.
  - Request: `workspace_tabs_spec`, `app_toolbar_spec`, `i18n_views_spec` updated.
  - System (optional): collapsible panels open on fresh setup, closed after nest.
  - JS unit: `lockedClosedOnPath` false when setup mode attribute present.

  <implementation_plan status="LOCKED 2026-05-30">
    <step id="1" status="complete">**SPEC + ADR:** Update W1/W5 in `docs/core/SPEC.md`; short ADR-0004 addendum documenting removal of `/projects/new` and `Workshop::UxMode` predicate.</step>
    <step id="2" status="pending">**Domain helper:** Add `Project#workshop_setup_mode?` and `Workshop::UxMode` presenter with `#show_preview_zone?`, `#show_nesting_progress?`, `#welcome_steps`, etc. Unit spec `[REQ-FIT-UI-001]`.</step>
    <step id="3" status="pending">**Routing + controller:** Change `projects#start` to redirect `workshop_path`; `show` uses `Workspace.find_or_create!` when unbound; **delete** `new`/`create`/`edit`/`update` setup path (`finish_ephemeral_setup`) — no legacy redirect for `/projects/new`. Trim `resources :projects` in routes. Update specs that hit removed routes.</step>
    <step id="4" status="pending">**Views — setup mode:** Reorder `show.html.erb`: welcome → láminas (`open`) → **inline** `_nesting_settings` (no collapsible) → DXF (`open`) → actions. Hide preview + progress. Taller mode unchanged (collapsed láminas/DXF; `_nesting_parameters` at bottom).</step>
    <step id="5" status="pending">**Stimulus + CSS:** Adjust `collapsible_persistence_controller.js` for setup mode; add `data-workshop-setup-mode` on main; optional `.project-show--setup` styles for muted hidden sections.</step>
    <step id="6" status="pending">**Toolbar + helpers:** `toolbar_workshop_path` → always `workshop_path`; update `download_paywall` and other `new_project_path` references.</step>
    <step id="7" status="pending">**i18n:** Update `projects.setup.welcome.steps` (remove Continuar → Iniciar anidado); `es_panic` parity; remove unused `projects.new.setup_title` or repurpose.</step>
    <step id="8" status="pending">**Delete dead code:** Remove `_setup_form.html.erb`, `new.html.erb`, setup-specific CSS (`.project-setup*`), `collapsible-key=setup-*` if unused.</step>
    <step id="9" status="pending">**Regression:** Run `ephemeral_workspace_spec`, `projects_crud_spec`, `workspace_tabs_spec`, `app_toolbar_spec`, `i18n_views_spec`, `project_dxf_upload_spec`, `nesting_start_workspace_spec`; fix failures.</step>
    <step id="10" status="pending">**QA checklist:** Update `docs/QA_MANUAL_CHECKLIST.md` funnel steps (no Parámetros iniciales page).</step>
  </implementation_plan>

  <working_notes>
  User approved contextual merge 2026-05-30. Q1–Q4 resolved 2026-05-30 (inline params, error on missing sheets, **delete /projects/new** sin redirect, order láminas→params→DXF). Awaiting PROCEED to lock plan and hand off to start-task.
  </working_notes>
</task_session>
