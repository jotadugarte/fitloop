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

## Follow-up (post v1.1) — Contornos abiertos como huérfanos de extracción

**Context (2026-05-18):** DXF con `LWPOLYLINE` / `SPLINE` / arcos **abiertos** (p. ej. pieza en S, cinta sin cerrar) no forman polígono en `extract_closed_contours` y **desaparecen** del nest sin aviso. Los sectores con bulge y `closed=False` ya se corrigen en extracción; lo que queda son entidades que siguen siendo **líneas abiertas** tras `polygonize`.

**Objetivo:** Tratarlas como **huérfanos de extracción** (no de nest), visibles en la misma sección de huérfanos (o bloque hermano pre-nest), con **descarga DXF** para corrección manual en CAD (cerrar contorno, repetir vértice inicial, o dibujar el borde opuesto).

### Decisiones propuestas (por cerrar en `explore-task` antes de implementar)

| ID | Propuesta |
|----|-----------|
| O1 | Nuevo motivo en reporte: `open_contour` (o `unclosed_geometry`). Distinto de `oversized_for_sheet` / `no_sheet_capacity`. |
| O2 | Detectar en **`nesting_engine/extract.py`** (o módulo `extract_open_contours.py`): entidades en capa de corte que aportan segmentos abiertos y **no** participan en ningún polígono de `polygonize` ni en un contorno cerrado directo. |
| O3 | Incluir en `report.json` / `placements_json` con geometría exportable: polilínea aplanada (`make_path` + `flattening`) o referencia `source_dxf` + `entity_handle` para re-exportar tal cual. |
| O4 | **DXF de descarga:** script dedicado (p. ej. `write_open_path_dxf.py`) — el exportador actual `write_piece_dxf` / `OrphanPieceExporter` asume **anillos cerrados** (`rings`); rutas abiertas requieren `LWPOLYLINE`/`SPLINE` sin `close`. |
| O5 | UI: tarjeta huérfano con badge “Contorno abierto”, copy: cerrar en CAD → volver a subir / “He actualizado mis DXF” (reutilizar flujo manual F24–F27 cuando exista `OrphanResolution`). |
| O6 | Pre-flight (`ProjectReadinessValidator`): permitir nest con piezas válidas pero **avisar** si hay `open_contour` pendientes; o bloquear nest hasta resolver (decisión de producto). |
| O7 | **Fuera de scope:** auto-cerrar heurístico, offset de cinta, o unir dos bordes paralelos automáticamente. |

### REQ / docs a tocar (cuando se implemente)

- `REQ-FIT-EXT-001` o nuevo `REQ-FIT-EXT-003` — contornos abiertos reportados, no silenciados.
- `REQ-FIT-NEST-003` — ampliar lista de `reason` y presenter.
- `DATA_FLOW_MAP.md` — rama extract → open orphans → descarga DXF.

### Plan de implementación (borrador — **después** de cerrar v1.1 auto-split)

<implementation_plan>

<step id="O-1">
**Test:** `nesting_engine/tests/test_extract_open_contours.py` — `LWPOLYLINE` abierta con bulge (fixture tipo peluo `12FE`) → una entrada `open_contour` con puntos aplanados; no cuenta como pieza nestable. Tag `[REQ-FIT-EXT-001]`.
**Implement:** `extract_open_contours()` o flag en `extract_closed_contours` que devuelva `(polygons, open_paths, warnings)`.
</step>

<step id="O-2">
**Test:** `nesting_engine/tests/test_write_open_path_dxf.py` — round-trip ezdxf lee polilínea abierta. Tag `[REQ-FIT-DXF-001]`.
**Implement:** `write_open_path_dxf.py` + `Dxf::OpenContourExporter` (Rails).
</step>

<step id="O-3">
**Test:** `spec/services/nesting/orphans_presenter_spec.rb` — fusiona huérfanos de nest + `open_contour` de último extract/report. Tag `[REQ-FIT-NEST-003]`.
**Implement:** Extender `nest.py` / pipeline de carga de piezas para emitir open orphans antes del nest; `OrphansPresenter` + i18n `reason.open_contour`.
</step>

<step id="O-4">
**Test:** `spec/requests/project_orphan_dxf_download_spec.rb` — descarga DXF para `open_contour` (polilínea abierta). Tag `[REQ-FIT-NEST-003]`.
**Implement:** Ruta descarga reutilizada o `open_contour_dxf`; vista `_nesting_orphans` — botón descarga siempre que haya geometría exportable (anillo o path abierto).
</step>

</implementation_plan>

**Dependencia:** Completar o al menos no bloquear **v1.1 auto-split** (estados `manual` / `resolved`, `PieceKey`). Este follow-up comparte tarjetas y descarga DXF pero es **pipeline de extracción**, no split.

---

## Codebase reality (verified 2026-05-17)

- `Workspace` — un `Project` efímero por sesión; `discard!` al salir (`app/services/workspace.rb`).
- PIN **no aplica** al flujo efímero: `ProjectAccessGate#require_project_access!` hace `grant_project_access!` si `ephemeral?`.
- `projects#show` efímero **no** renderiza `_nesting_run_history` (solo preview + huérfanos actuales).
- Código PIN / `Project.saved` / `pin_gate` permanece para legacy; **v1.1 split target = workspace efímero únicamente**.

---

## Implementation plan

<implementation_plan>

<step id="1" status="complete">**Test:** `spec/models/orphan_resolution_spec.rb` — `OrphanResolution` on ephemeral project; states `pending|system_split|manual|resolved`; unique `piece_key`. Tags `[REQ-FIT-SPLIT-001]`, `[REQ-FIT-DOM-001]`. **Implement:** Migration + models `OrphanResolution`, `SplitProposal`, `DerivedPiece`; `projects.session_workflow_log` jsonb default `[]`.</step>

<step id="2" status="complete">**Test:** `spec/services/nesting/piece_key_builder_spec.rb` — stable key from attachment id + extractor piece id / geometry fingerprint. Tag `[REQ-FIT-SPLIT-001]`. **Implement:** `Nesting::PieceKeyBuilder` when persisting orphan rows after nest.</step>

<step id="3" status="complete">**Test:** Expand `docs/core/SPEC.md` — full **REQ-FIT-SPLIT-001** (opt-in orphans, states, ephemeral session, manual copy, CLI modes, `split_not_feasible`). Tag `[REQ-FIT-SPLIT-001]`. **Implement:** SPEC + `DATA_FLOW_MAP.md` workflow (split plan job → accept → nest).</step>

<step id="4" status="complete">**Test:** `nesting_engine/tests/test_split_planner.py` — rectangle oversized → 2 parts fit largest stock; hole preserved; recursive re-split; failure → `split_not_feasible`. Tag `[REQ-FIT-SPLIT-001]`. **Implement:** `nesting_engine/split_planner.py` (Shapely; straight cuts any angle; minimize piece count; hole-aware).</step>

<step id="5" status="complete">**Test:** `nesting_engine/tests/test_cli_plan_splits.py` — `mode: "plan_splits"` + `piece_keys` → `split_preview.json`. Tags `[REQ-FIT-CLI-001]`, `[REQ-FIT-SPLIT-001]`. **Implement:** Plan mode in `nest.py` or `split_cli.py`; schema in `nesting_engine/README.md`.</step>

<step id="6" status="complete">**Test:** `spec/services/nesting/orphans_presenter_spec.rb` — merge report orphans + unresolved `OrphanResolution`; exclude `resolved`; disable system_split without rings. Tags `[REQ-FIT-SPLIT-001]`, `[REQ-FIT-NEST-003]`. **Implement:** `Nesting::OrphansPresenter` + `resolution_state`, `system_split_enabled?`.</step>

<step id="7" status="complete">**Test:** `spec/requests/orphan_resolutions_spec.rb` (ephemeral workspace) — PATCH `system_split` / `manual` / `pending`. Tag `[REQ-FIT-SPLIT-001]`. **Implement:** `OrphanResolutionsController` + routes; `session_workflow_log` events (J43).</step>

<step id="8" status="pending">**Test:** `spec/jobs/nesting_split_plan_job_spec.rb` — CLI plan mode; `SplitProposal` draft with preview geometry. Tags `[REQ-FIT-SPLIT-001]`, `[REQ-FIT-JOB-001]`. **Implement:** `Nesting::SplitPlanJob` + `Nesting::SplitPlannerRunner`; Turbo preview frame.</step>

<step id="9" status="pending">**Test:** `spec/system/orphan_auto_split_spec.rb` — partial nest → card → “Dividir con Fitloop” → preview → Aceptar. Tags `[REQ-FIT-SPLIT-001]`, `[REQ-FIT-UI-002]`. **Implement:** `_nesting_orphans.html.erb` — badges, toggles, inline SVG, Aceptar/Rechazar/Regenerar.</step>

<step id="10" status="pending">**Test:** Request spec — accept creates `DerivedPiece`, excludes mother `piece_key`, logs session event. Tag `[REQ-FIT-SPLIT-001]`. **Implement:** `SplitProposalsController#accept` / `#reject` / `#regenerate`; invalidate drafts on sheet stock change (G32).</step>

<step id="11" status="pending">**Test:** `spec/services/nesting/config_builder_split_spec.rb` — `excluded_piece_keys`, `derived_pieces` in payload. Tags `[REQ-FIT-CLI-001]`, `[REQ-FIT-SPLIT-001]`. **Implement:** `Nesting::ConfigBuilder` + extractor skip/inject derived polygons.</step>

<step id="12" status="pending">**Test:** `nesting_engine/tests/test_nest_pipeline.py` — nest with `derived_pieces`; cut lines + labels in nested DXF. Tags `[REQ-FIT-NEST-002]`, `[REQ-FIT-SPLIT-001]`. **Implement:** Engine merges derived pieces; cut lines in `nested.dxf`; labels Pieza-Na/Nb.</step>

<step id="13" status="pending">**Test:** Request spec — “Anidar con piezas actualizadas” auto-enqueues `NestingJob` (G30). Tags `[REQ-FIT-NEST-004]`, `[REQ-FIT-SPLIT-001]`. **Implement:** CTA + `NestingRunsController` flag from accept handler.</step>

<step id="14" status="pending">**Test:** System/request — manual 3-step copy (F24); “He actualizado mis DXF” → readiness → `resolved`. Tags `[REQ-FIT-SPLIT-001]`, `[REQ-FIT-VAL-001]`. **Implement:** i18n `en`/`es`; disabled system button without rings (B5).</step>

<step id="15" status="pending">**Test:** `test_split_planner.py` — any reason → planner runs; `split_not_feasible` in preview (J40). Tag `[REQ-FIT-SPLIT-001]`. **Implement:** Surface in `split_preview.json` + orphan card error state.</step>

<step id="16" status="pending">**Test:** Job spec — cancel nesting invalidates draft `SplitProposal` (J42). Tag `[REQ-FIT-JOB-001]`. **Implement:** Cancel hook on `Nesting::JobRunner` clears stale drafts.</step>

<step id="17" status="pending">**Test:** Targeted RSpec + `pytest nesting_engine/tests -q -m "not slow"`. **Implement:** Mark ROADMAP v1.1 auto-split done; optional ADR `0002-auto-split.md`.</step>

</implementation_plan>
