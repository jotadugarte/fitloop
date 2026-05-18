# Task: v1.1 — Auto-split (opt-in desde huérfanos)

**Roadmap:** `docs/ROADMAP.md` — Pending — **v1.1 — Auto-split**  
**REQ anchors:** REQ-FIT-SPLIT-001, REQ-FIT-NEST-003, REQ-FIT-DXF-001, REQ-FIT-UI-002, REQ-FIT-CLI-001, REQ-FIT-NEST-004  
**Status:** Spec locked — handoff to `start-task`  
**Classification:** Feature

---

## Problem statement

Tras un nest con huérfanos, el usuario revisa tarjetas por pieza y elige **split sistema**, **resolución manual**, o deja **pendiente**. Solo las piezas marcadas para split entran al planner (preview obligatorio → aceptar por huérfano). Las resueltas (split aceptado o manual verificado en pre-flight) **dejan de aparecer** como huérfanos en runs posteriores. La pieza madre **desaparece** del set de nest tras split aceptado; las hijas llevan etiquetas y trazabilidad.

**No** ofrecer UI “añadir lámina” — si falta stock, el usuario edita inventario y re-nesta.

---

## Discovery log (locked 2026-05-17)

### A — Runs y visibilidad

| ID | Decisión |
|----|----------|
| A1 | En la **misma sesión efímera** (workspace, sin salir de página): huérfanos de **re-nests anteriores** siguen visibles hasta resolver; al marcar split o **resolver**, no reaparecen en runs nuevos. |
| A2 | Marcas de estado **persisten** entre re-nests (mismo `piece_key` estable, no solo `piece_index` del último report). |
| A3 | Panel de huérfanos/resolución **solo post-job** en `project#show` cuando hay huérfanos pendientes o trabajo en curso (derivado de A1). |

### B — Elegibilidad

| ID | Decisión |
|----|----------|
| B4 | Split sistema disponible para **`oversized_for_sheet`** y **`no_sheet_capacity`**; el usuario decide. |
| B5 | **Locked:** sin geometría exportable (`rings`), **deshabilitar** “Dividir con Fitloop”; solo manual o pendiente. |
| B6 | Si el problema es lámina ausente en inventario → usuario añade stock y re-nesta; **no** UI “añadir lámina” desde huérfanos. |

### C — Estados por huérfano

| ID | Decisión |
|----|----------|
| C7 | Tres estados: `pending` · `system_split` · `manual` (+ cuarto efectivo `resolved` tras completar). |
| C8 | Puede **cambiar de opinión** antes de materializar split. |
| C9 | UI **tarjeta a tarjeta** (sin bulk v1.1). |
| C10 | Estado **`resolved`**; al resolver, no reaparece como huérfano en nuevos runs (A1). |

### D — UX split sistema

| ID | Decisión |
|----|----------|
| D11 | **Misma vista** que tarjetas de huérfanos (sin wizard separado). |
| D12 | **Preview obligatorio** antes de materializar subpiezas. |
| D13 | Aceptar / rechazar **por huérfano**. |
| D14 | Tras rechazar, **regenerar** otra propuesta de corte. |
| D15 | Sin parámetros por pieza; motor global **pocas partes + eficiencia de material**. |

### E — Geometría (Python)

| ID | Decisión |
|----|----------|
| E16 | Cortes **rectos, cualquier ángulo**; optimizar material. |
| E17 | **Respetar agujeros** internos (no cortar islas). |
| E18 | Kerf **solo en nest** entre piezas colocadas (no en el plano de corte del split). |
| E19 | Sin máximo fijo de subpiezas; **minimizar recuento**; si subpieza sigue oversized → **re-split automático** en cadena hasta caber o `split_not_feasible`. |

### E.1 — Salida

| ID | Decisión |
|----|----------|
| E21 | Líneas de corte en **`nested.dxf`**. |
| E22 | Etiquetas **Pieza-Na, Pieza-Nb** en DXF, preview y listados. |
| E23 | **`parent_piece_key`** (o equivalente) + `source_dxf` para trazabilidad. |

### F — Manual (locked)

| ID | Decisión |
|----|----------|
| F24 | **Locked:** no editar DXF origen in-app. Copy **explícito** en UI: usuario debe quitar la madre del CAD y subir DXF corregido o nuevo; Fitloop **no** deduplica. |
| F25 | **Locked:** tarjeta `manual` + hint paso a paso + **“He actualizado mis DXF”** → pre-flight → `resolved` si madre ya no extrae. |
| F26 | Sí | Upload manual puede traer **varias** piezas; responsabilidad del usuario evitar duplicados con la madre. |
| F27 | Sí | Tras upload + pre-flight OK → **`resolved` automático**. |
| F28 | Sí | Mezcla split sistema + manual + pendientes en un proyecto. |

### G — Persistencia y re-nest

| ID | Decisión |
|----|----------|
| G29 | Estados, previews y piezas derivadas en **PostgreSQL**. |
| G30 | Tras aceptar split(s) → **“Anidar con piezas actualizadas”** (auto-enqueue job, no solo botón genérico re-nest). |
| G31 | **Madre excluida** del extractor/nest; solo hijas (o geometría manual nueva). |
| G32 | Si cambia inventario de láminas → **invalidar** previews de split pendientes. |

### H — CLI

| ID | Decisión |
|----|----------|
| H33 | Mismo contrato `config.json` ampliado (p. ej. `split_requests`, `excluded_piece_keys`, `derived_pieces`). |
| H34 | **Dos invocaciones** CLI: (1) `plan_splits` / modo plan → preview artifacts; (2) nest normal con piezas actualizadas. |
| H35 | Python emite geometría de preview; Rails pinta SVG (como huérfanos hoy). |

### I — UI / acceso

| ID | Decisión |
|----|----------|
| I36 | Solo **post-job** en proyecto. |
| I37 | **Workspace efímero** (`Workspace`, `Project#ephemeral?`): sin PIN en flujo actual (`grant_project_access!` automático; `validate_pin_assignment` omitido). Proyecto destruido al salir (`Workspace.discard!`). Split sin auth extra. **Fuera de scope v1.1:** eliminar rutas PIN / proyectos `saved` legacy. |
| I38 | Copy nuevo `en`/`es`. |
| I39 | **Badges** en tarjeta: Pendiente / Sistema / Manual / Resuelto (+ En preview si aplica). |

### J — Edge cases

| ID | Pregunta | Resolución |
|----|----------|------------|
| J40 | **Locked:** marcar cualquiera con geometría; motor → `split_not_feasible` si falla; sin bloqueo por `reason`. |
| J41 | **Locked:** sí se ofrece split (B4); usuario elige. |
| J42 | Cancelar job en curso | **Invalida** previews/planes pendientes ligados a ese run. |
| J43 | **Auditoría solo en sesión:** append a `projects.session_workflow_log` (JSON); UI opcional colapsable en workspace; **no** listado persistente para volver días después (no renderizar historial multi-run como producto guardado). |

### K — Entrega

| ID | Decisión |
|----|----------|
| K44 | **Full stack** v1.1 (UI + DB + engine + SPEC + tests). |
| K45 | Actualizar **`REQ-FIT-SPLIT-001`** detalle en `SPEC.md` en el mismo esfuerzo. |

---

## Domain Model

### `PieceKey` (value object — nuevo)

- **Wraps:** string estable `"{source_dxf_blob_id}:{extractor_piece_id}"` o hash de geometría normalizada + capa + archivo.
- **Invariants:** Inmutable una vez asignado al huérfano; sobrevive cambios de `piece_index` entre runs.

### `OrphanResolution` (AR — nuevo, `project_id`)

- **Responsibility:** Estado de resolución por `piece_key`.
- **Fields (conceptual):** `resolution_state` enum `pending` | `system_split` | `manual` | `resolved`; `reason` snapshot; `last_nesting_run_id`; timestamps.
- **Invariants:**
  - Una fila activa por `piece_key` por proyecto.
  - `resolved` → excluido de lista de huérfanos UI y de re-reporte como el mismo huérfano (A1/C10).
  - Cambio de inventario láminas → invalida `split_proposal` asociado (G32).

### `SplitProposal` (AR — nuevo)

- **Responsibility:** Preview de cortes para un `orphan_resolution` en `system_split`.
- **Fields:** `status` `draft` | `accepted` | `rejected`; JSON `cut_segments`, `child_piece_geometries`, `labels`; `version` para regenerar (D14).
- **Invariants:** Aceptar solo tras preview renderizado; aceptar materializa `DerivedPiece` rows y excluye madre (G31).

### `DerivedPiece` (AR — nuevo)

- **Responsibility:** Subpiezas listas para extractor/nest.
- **Fields:** `parent_piece_key`, `label` (Pieza-3a), geometry JSON o attachment, `sort_order`.
- **Invariants:** Kerf no modelado en corte; agujeros preservados en geometría hija.

### `Orphan` (reporte — existente)

- Sin cambio de forma en `report.json`; UI fusiona report + `OrphanResolution` + exclusiones.

### Branded / enums

- `ResolutionState`, `SplitProposalStatus`, `OrphanReason` (existente + `split_not_feasible`).

---

## Proposed UX (locked)

1. Tras job `partial` (o huérfanos pendientes de re-nests en la misma sesión), sección **Huérfanos** ampliada en `_nesting_orphans.html.erb`.
2. Por tarjeta: badge estado; radio/toggles `Pendiente` | `Dividir con Fitloop` | `Resolver manualmente`.
3. Estado `system_split`: inline preview SVG + Aceptar / Rechazar / Regenerar.
4. Aceptar último split pendiente o batch → CTA **“Anidar con piezas actualizadas”** → `NestingRunsController` + flag en snapshot.
5. Manual: hint 3 pasos (descargar → editar CAD → subir DXF) + **“He actualizado mis DXF”** → readiness + auto `resolved` si madre ya no extrae.
6. Eventos `splits_applied` / `split_rejected` en `session_workflow_log` (solo sesión; sin historial persistente multi-día).

---

## CLI / engine (sketch)

**Invocación 1 — plan:** `config.json` + `mode: "plan_splits"` + `piece_keys[]` → `split_preview.json` (cuts + child outlines + labels).

**Invocación 2 — nest:** `excluded_piece_keys[]`, `derived_pieces[]` (or merged into synthetic input layer), normal nest pipeline.

**Módulo nuevo:** `nesting_engine/split_planner.py` (Shapely; rect cuts any angle; hole-aware; minimize piece count; recursive re-split).

**Rails:** `Nesting::SplitPlannerRunner`, `OrphanResolutionsController` o acciones en `ProjectsController`; jobs encadenados.

---

## Risks

| Risk | Mitigation |
|------|------------|
| `piece_index` inestable entre runs | `PieceKey` estable + migración de resoluciones |
| Duplicado pieza madre + manual upload | Copy fuerte; pre-flight warning si misma geometría detectada (heurística opcional v1.1) |
| Dos CLI + tiempo UX | Job corto para plan; progress Turbo |
| SPEC vacío | K45 — expandir REQ-FIT-SPLIT-001 antes de merge |
| Cancel job | J42 — limpiar drafts |

---

## Codebase reality (verified 2026-05-17)

- `Workspace` — un `Project` efímero por sesión; `discard!` al salir (`app/services/workspace.rb`).
- PIN **no aplica** al flujo efímero: `ProjectAccessGate#require_project_access!` hace `grant_project_access!` si `ephemeral?`.
- `projects#show` efímero **no** renderiza `_nesting_run_history` (solo preview + huérfanos actuales).
- Código PIN / `Project.saved` / `pin_gate` permanece para legacy; **v1.1 split target = workspace efímero únicamente**.

---

## Implementation plan

<implementation_plan>

<step id="1">
**Test:** Add `spec/models/orphan_resolution_spec.rb` — `OrphanResolution` belongs to ephemeral project; states `pending|system_split|manual|resolved`; unique `piece_key`. Tag `[REQ-FIT-SPLIT-001]`, `[REQ-FIT-DOM-001]`.
**Implement:** Migration + models `OrphanResolution`, `SplitProposal`, `DerivedPiece`; `projects.session_workflow_log` jsonb default `[]`.
</step>

<step id="2">
**Test:** Add `spec/services/nesting/piece_key_builder_spec.rb` — stable key from attachment id + extractor piece id / geometry fingerprint. Tag `[REQ-FIT-SPLIT-001]`.
**Implement:** `Nesting::PieceKeyBuilder` used when persisting orphan rows after nest.
</step>

<step id="3">
**Test:** Expand `docs/core/SPEC.md` — full **REQ-FIT-SPLIT-001** (opt-in orphans, states, ephemeral session, manual copy, CLI modes, `split_not_feasible`). Tag `[REQ-FIT-SPLIT-001]`.
**Implement:** SPEC + workflow note in `DATA_FLOW_MAP.md` (split plan job → accept → nest); ROADMAP unchanged until ship.
</step>

<step id="4">
**Test:** Add `nesting_engine/tests/test_split_planner.py` — rectangle oversized → 2 parts fit largest stock; hole preserved; recursive re-split when child still oversized; failure → `split_not_feasible`. Tag `[REQ-FIT-SPLIT-001]`.
**Implement:** `nesting_engine/split_planner.py` (Shapely; straight cuts any angle; minimize piece count; hole-aware).
</step>

<step id="5">
**Test:** Add `nesting_engine/tests/test_cli_plan_splits.py` — `config.json` `mode: "plan_splits"` + `piece_keys` → `split_preview.json` with cuts, child rings, labels. Tag `[REQ-FIT-CLI-001]`, `[REQ-FIT-SPLIT-001]`.
**Implement:** Extend `nesting_engine/nest.py` (or `split_cli.py`) for plan mode; document schema in `nesting_engine/README.md`.
</step>

<step id="6">
**Test:** Add `spec/services/nesting/orphans_presenter_spec.rb` — merges latest report orphans with unresolved `OrphanResolution`; excludes `resolved`; disables system_split without rings. Tag `[REQ-FIT-SPLIT-001]`, `[REQ-FIT-NEST-003]`.
**Implement:** Update `Nesting::OrphansPresenter` + presenter structs for `resolution_state`, `system_split_enabled?`.
</step>

<step id="7">
**Test:** Add `spec/requests/orphan_resolutions_spec.rb` (ephemeral workspace) — PATCH state `system_split` / `manual` / `pending`; requires workspace session. Tag `[REQ-FIT-SPLIT-001]`.
**Implement:** `OrphanResolutionsController` (or nested under projects) + routes; append `session_workflow_log` events (J43).
</step>

<step id="8">
**Test:** Add `spec/jobs/nesting_split_plan_job_spec.rb` — enqueues CLI plan mode; stores `SplitProposal` draft with preview geometry. Tag `[REQ-FIT-SPLIT-001]`, `[REQ-FIT-JOB-001]`.
**Implement:** `Nesting::SplitPlanJob` + `Nesting::SplitPlannerRunner` (CLI invocation 1); Turbo broadcast preview frame.
</step>

<step id="9">
**Test:** Add failing system spec `spec/system/orphan_auto_split_spec.rb` — partial nest → orphan card → choose “Dividir con Fitloop” → preview visible → Aceptar. Tag `[REQ-FIT-SPLIT-001]`, `[REQ-FIT-UI-002]`.
**Implement:** Extend `_nesting_orphans.html.erb` — badges, per-card toggles, inline SVG preview, Aceptar/Rechazar/Regenerar; Stimulus if needed.
</step>

<step id="10">
**Test:** Request spec — Aceptar split creates `DerivedPiece` rows, sets mother `piece_key` excluded, marks resolution `resolved` for accepted path / keeps `system_split` until accept; logs session event. Tag `[REQ-FIT-SPLIT-001]`.
**Implement:** `SplitProposalsController#accept` / `#reject` / `#regenerate`; materialize children; invalidate drafts on sheet stock change (G32).
</step>

<step id="11">
**Test:** Add `spec/services/nesting/config_builder_split_spec.rb` — payload includes `excluded_piece_keys`, `derived_pieces` geometry. Tag `[REQ-FIT-CLI-001]`, `[REQ-FIT-SPLIT-001]`.
**Implement:** Extend `Nesting::ConfigBuilder` + extractor pipeline to skip excluded mothers and inject derived polygons.
</step>

<step id="12">
**Test:** Extend `nesting_engine/tests/test_nest_pipeline.py` — nest with `derived_pieces` places children; cut lines + labels in nested DXF output keys. Tag `[REQ-FIT-NEST-002]`, `[REQ-FIT-SPLIT-001]`.
**Implement:** Engine nest path merges derived pieces; emit cut lines in `nested.dxf`; labels Pieza-Na/Nb in report/placements metadata.
</step>

<step id="13">
**Test:** Request spec — after accept, POST “Anidar con piezas actualizadas” enqueues `NestingJob` automatically (G30). Tag `[REQ-FIT-NEST-004]`, `[REQ-FIT-SPLIT-001]`.
**Implement:** CTA + `NestingRunsController` flag; wire from accept handler when pending splits cleared.
</step>

<step id="14">
**Test:** System/request spec — manual card shows explicit 3-step copy (F24); “He actualizado mis DXF” runs readiness; mother absent → `resolved`. Tag `[REQ-FIT-SPLIT-001]`, `[REQ-FIT-VAL-001]`.
**Implement:** i18n `en`/`es` for manual path, disabled system button without rings (B5), duplicate-geometry optional warning copy.
</step>

<step id="15">
**Test:** `nesting_engine/tests/test_split_planner.py` — mark any reason → planner runs; `split_not_feasible` in preview response (J40). Tag `[REQ-FIT-SPLIT-001]`.
**Implement:** Surface `split_not_feasible` in `split_preview.json` + orphan card error state (J41 allowed).
</step>

<step id="16">
**Test:** Job spec — cancel nesting invalidates draft `SplitProposal` for that run (J42). Tag `[REQ-FIT-JOB-001]`.
**Implement:** `Nesting::JobRunner` cancel hook clears stale drafts tied to `nesting_run_id`.
</step>

<step id="17">
**Test:** Run targeted RSpec + `pytest nesting_engine/tests -q -m "not slow"`; architecture doc test if SPEC anchors added.
**Implement:** Mark `docs/ROADMAP.md` v1.1 auto-split done when merged; optional ADR `docs/core/ADRs/0002-auto-split.md` if split algorithm needs normative record.
</step>

</implementation_plan>
