# Task: Composite DXF layers (primary + auxiliary)

**Status:** Spec locked (amended 2026-05-18: auto-split + composite) — handoff to `start-task`  
**Started:** 2026-05-18  
**Roadmap:** v1.2 — Composite DXF layers (`REQ-FIT-DXF-002`) + split integration (`REQ-FIT-SPLIT-001`)

---

## Problem statement

A single DXF can have **n layers** with different roles: cut polygons (nesting pieces), engraving, marks, text, etc. Today all `included` layers contribute **independent** closed contours to nesting. The user needs:

1. One **primary layer per file** (exclusive) — closed polygons = nestable pieces.
2. Optional **auxiliary layers** (checkboxes) — geometry that is **not** nested alone; it is **clipped/associated** to the primary polygon that contains it.
3. On nest: move/rotate the primary piece as today; auxiliary geometry keeps **relative position** to its parent piece.
4. Geometry **outside** any primary polygon → **discarded** (no warning product requirement; silent ignore).
5. Output `nested.dxf` preserves **original layer names** for auxiliary (and primary) geometry.

---

## User decisions (2026-05-18)

| # | Topic | Decision |
|---|--------|----------|
| 1 | Primary layer scope | **Per DXF file** (can differ by file: `corte` vs `CUT`) |
| 2 | Auxiliary entity types | **All** — lines, arcs, polylines, TEXT/MTEXT, INSERT, circles, etc. |
| 3 | Association rule | Only geometry **inside** each primary polygon; keep relative position; **discard** outside |
| 4 | Outside geometry | **Ignore** (no orphan/auxiliary piece) |
| 5 | UI | **Exclusive** primary selector (one per file); auxiliary = separate checkboxes |
| 6 | Output layers | **Keep original DXF layer names** in nested output |
| 7 | Transform | Auxiliary **translates and rotates** with parent piece (same placement transform) |
| 8 | Holes in primary | Auxiliary inside holes **associates** to that piece (same parent) |
| 9 | Boundary crossing | **Option B — clip/intersection:** keep only geometry inside each primary polygon; discard exterior portions. Lines/arcs/polylines may split across two pieces (each piece gets its interior segment). |
| 10 | TEXT / MTEXT | Associate if **insert point** is inside primary polygon; no glyph clipping. Outside → ignore. |
| 11 | INSERT (blocks) | Associate if **insert point** is inside primary polygon; resolve block geometry per existing depth ≤8 rule. Outside → ignore. |
| 12 | **Auto-split (v1.1)** | When mother piece has primary + auxiliaries, **same cut lines** split the primary polygon into separate nest pieces; auxiliaries **partition with their child** (clip per child region, same rules as extract). Each child nests as an **independent polygon**; its decorations **translate/rotate** with that child, preserving relative position. |

---

## Auto-split + composite pieces (normative)

**Scope:** Integrates with existing `REQ-FIT-SPLIT-001` (`split_planner.plan_split`, `DerivedPiece`, `excluded_piece_keys`).

1. **Split plane:** Cuts apply to the **primary polygon** only (unchanged planner). Cut segments are shared; auxiliary layers are **not** split independently.
2. **Child pieces:** Each `SplitChild` / `DerivedPiece` is a separate nest polygon (Pieza-Na, Pieza-Nb, …) — two (or more) **different** pieces on the sheet, same as today.
3. **Decoration partition:** For each decoration on the mother `CompositePiece`, assign to child `k` via `intersection(decoration, child_primary_polygon)` (Option B clip). Decoration crossing the cut → **split** between children (each keeps its interior segment). Insert-point rules for TEXT/INSERT: assign to child whose polygon **contains the insert point**; if on cut boundary, prefer child whose interior contains the point (tie-break: largest overlap area).
4. **Nest:** Each derived piece loads as `CompositePiece` (rings + `decorations[]` subset). Nest pipeline treats them like any other piece; transforms apply to primary + that child's decorations together.
5. **Mother excluded:** Mother `piece_key` stays in `excluded_piece_keys`; children enter via `derived_pieces[]` with **both** `rings` and `decorations` in payload (extend `geometry_json` or parallel `decorations_json` on `DerivedPiece`).
6. **Preview / accept:** Split preview SVG shows cut lines on primary **and** clipped aux geometry per child outline. Accept materializes per-child decoration payloads.

**Out of scope:** Different cut angles per auxiliary layer; re-associating aux across children after nest (only at split + extract).

---

## UI copy (locked)

### Label

- **ES:** Capa principal  
- **EN:** Primary layer  

### Tooltip (short) — approved 2026-05-18

- **ES:** `Contornos a anidar; el resto queda dentro de cada pieza.`  
- **EN:** `Outlines to nest; other geometry stays inside each piece.`  

### Auxiliary layers (draft)

- **ES:** Capas asociadas  
- **EN:** Associated layers  
- Helper (optional): `Grabado, marcas, texto… se mueven con la pieza que los contiene.`

---

## Domain model (CbC)

**Approved:** 2026-05-18 (start-task step 3.0, user PROCEED).

### PrimaryLayerSelection (per attachment)

- **Responsibility:** At most one `ProjectLayer` per `active_storage_attachment_id` marked as primary (`is_primary` or `role: :primary`).
- **Invariants:**
  - Zero or one primary per attachment; never two primaries on the same file.
  - If any auxiliary layer is `included`, a primary **must** be set for that attachment (readiness validation).
  - Primary layer is automatically `included` for extraction (or implied included when set).

### AuxiliaryLayerSelection (per attachment)

- **Responsibility:** Subset of layers marked `included` + `role: :auxiliary` (or `included` without being primary).
- **Invariants:**
  - Auxiliary layers never produce standalone nest pieces.
  - Entities only survive extraction if spatially inside a primary polygon (per association rules below).

### CompositePiece (engine value object)

- **Responsibility:** One nestable unit = primary `Polygon` (+ holes) + attached **decorations** list.
- **Invariants:**
  - Nesting optimizer uses **primary polygon only** (plus kerf/margin rules unchanged).
  - After placement transform `T`, every decoration entity applies `T` relative to piece origin.
  - `piece_key` / identity derived from primary geometry (+ file id), not from decorations.
  - **On auto-split:** `partition_decorations(children: list[Polygon], cuts)` → one `CompositePiece` per child with clipped decoration subset; no decoration may remain on the excluded mother.

### DecorationEntity (engine)

- Wraps raw DXF entity reference or normalized geometry (layer name, entity type, transformable representation).
- **Invariants:**
  - Preserves `layer_name` for output emission.
  - Discarded if not inside any primary polygon of that file.

### Spatial association rule (normative)

- For each auxiliary entity, test against primary polygons of **the same source file**.
- **Inside** = primary polygon fill **including holes as interior** (hole geometry associates to parent piece).
- **Lines / arcs / open or closed polylines:** `intersection(entity, primary_polygon)` — keep interior parts only; discard exterior. One entity crossing two primary polygons → **two decorations**, one per piece, each clipped independently.
- **TEXT / MTEXT:** include whole entity if **insert point** ∈ primary polygon (no glyph clip).
- **INSERT:** include if **insert point** ∈ primary polygon; nested block resolution depth ≤8 (REQ-FIT-EXT-002).
- **Circles / points:** clip or center-in rules aligned with entity type in implementation plan (default: center inside for points; circle → arc segment(s) inside or discard if no intersection).
- **Outside all primary polygons:** silent discard (no report requirement).

### ProjectLayer (Rails persistence extension)

- New columns (names TBD): `role` enum (`primary` | `auxiliary` | nil) or `is_primary: boolean` + `included`.
- Scoped uniqueness: one `is_primary` per `(project_id, active_storage_attachment_id)`.

---

## Architectural notes

- **Rails:** UI + persistence + `Nesting::ConfigBuilder` extensions; readiness validator updates.
- **Python:** Extract composite pieces; nest primary only; emit nested DXF with original layer names + transformed decorations (`dxf_output.py` / extract pipeline).
- **Does not violate** SYSTEM_ARCHITECTURE kill list (nesting math stays Python).
- **SPEC gap:** New `REQ-FIT-DXF-002` (or extend `REQ-FIT-DXF-001`) — requires SPEC + possibly ADR for piece model change.

---

## Resolved defaults (plan lock 2026-05-18)

3. **Preview SVG:** yes — show clipped auxiliary geometry with primary outlines (same association rules).
4. **CLI config:** per-file `input_files[]` with `primary_layer` + `auxiliary_layers[]`; legacy flat `included_layers` still accepted when no per-file primary set.
5. **Backward compatibility:** if `primary_layer` absent for a file, treat every `included` layer as **primary-only** (current behavior); once user sets a primary on that file, aux checkboxes apply.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Entity-type explosion in transform | Phase 1: lines/arcs/polylines; phase 2: TEXT/INSERT if hard |
| Performance (many entities per piece) | Spatial index per file at extract time |
| Output DXF fidelity | Golden tests on layer names + relative positions, not absolute coords |

---

## Implementation plan

<implementation_plan>

<step id="1" status="complete">
**Test:** `spec/models/project_layer_spec.rb` — one `layer_role: primary` per attachment; setting primary clears other primaries on same attachment; primary implies included. Tags `[REQ-FIT-DXF-002]`, `[REQ-FIT-DOM-001]`.
**Implement:** Migration `layer_role` enum (`primary`, `auxiliary`, null) on `project_layers`; model validations + `ProjectLayer::SetPrimary` service; DB partial unique index one primary per `(project_id, active_storage_attachment_id)`.
</step>

<step id="2" status="complete">
**Test:** Expand `docs/core/SPEC.md` — **REQ-FIT-DXF-002** (primary per file, auxiliary clip B, insert-point TEXT/INSERT, output preserves layer names, composite invariants, **auto-split partitions aux with same cuts as primary**). Cross-ref `REQ-FIT-SPLIT-001`. Tag `[REQ-FIT-DXF-002]`. **Implement:** SPEC detail + `DATA_FLOW_MAP.md` § extract → composite → split partition → nest → emit.
</step>

<step id="3" status="complete">
**Test:** `spec/services/project_readiness_validator_spec.rb` — error when auxiliary included without primary on same file; ok when only primary; legacy union mode unchanged. Tags `[REQ-FIT-DXF-002]`, `[REQ-FIT-VAL-001]`.
**Implement:** `ProjectReadinessValidator` + i18n `project_readiness.primary_layer_required` (en/es).
</step>

<step id="4" status="complete">
**Test:** `spec/requests/project_layers_spec.rb` — PATCH sets exclusive primary radio per attachment + auxiliary checkboxes; cannot mark two primaries. Tag `[REQ-FIT-DXF-002]`.
**Implement:** Group layers by attachment in `project_layers/index` (and setup form if shared); radio `primary_layer_id` + auxiliary checkboxes; `ProjectLayerSelection` / controller permit `layer_role`; tooltip ES/EN locked copy.
</step>

<step id="5" status="complete">
**Test:** `spec/services/nesting/config_builder_spec.rb` — `input_files[]` emits `primary_layer` + `auxiliary_layers`; legacy `included_layers` when no primary. Tags `[REQ-FIT-CLI-001]`, `[REQ-FIT-DXF-002]`.
**Implement:** `Nesting::ConfigBuilder#input_files_payload` + union fallback.
</step>

<step id="6" status="complete">
**Test:** `nesting_engine/tests/test_composite_extract.py` — fixture DXF: primary `CORTE` + `GRABADO` line crossing border → two segments on two pieces; line fully outside discarded; TEXT insert inside kept whole. Tag `[REQ-FIT-DXF-002]`.
**Implement:** `nesting_engine/composite_extract.py` — `load_composite_pieces(path, primary_layer, auxiliary_layers, ...)` returning `CompositePiece` list with `DecorationEntity` payloads; clip via Shapely intersection; spatial index per file.
</step>

<step id="7" status="complete">
**Test:** `nesting_engine/tests/test_composite_extract.py` — hole interior associates decoration; INSERT insert-point rule; circle clips to arc inside. Tags `[REQ-FIT-DXF-002]`, `[REQ-FIT-EXT-002]`.
**Implement:** Entity handlers in `composite_extract.py` (LINE, ARC, LWPOLYLINE, CIRCLE, TEXT, MTEXT, INSERT depth ≤8); assertions on bounded entity loops.
</step>

<step id="8" status="complete">
**Test:** `nesting_engine/tests/test_piece_loader_composite.py` — `load_pieces_from_config` uses composite path when `primary_layer` present; legacy path unchanged. Tags `[REQ-FIT-DXF-002]`, `[REQ-FIT-CLI-001]`.
**Implement:** Wire `piece_loader.py` → `composite_extract`; attach decorations list on piece objects passed to nest pipeline.
</step>

<step id="9" status="complete">
**Test:** `nesting_engine/tests/test_decoration_transform.py` — translate+rotate decoration with `PlacedPiece` transform; relative offset invariant (fixture: mark at known offset from centroid). Tag `[REQ-FIT-DXF-002]`.
**Implement:** `nesting_engine/decoration_transform.py` — apply same `rotate(centroid)` + `translate` as primary polygon to each decoration primitive.
</step>

<step id="10" status="complete">
**Test:** `nesting_engine/tests/test_dxf_output_composite.py` — nested DXF contains original layer names (`CORTE`, `GRABADO`); no forced `PIECES` for composite runs; SHEETS unchanged. Tag `[REQ-FIT-DXF-002]`.
**Implement:** Extend `dxf_output.write_nested_dxf` / `_add_piece` to emit primary rings on **source primary layer name** + write decoration entities on their layers; ensure layers exist in output doc.
</step>

<step id="11" status="complete">
**Test:** `nesting_engine/tests/test_nest_pipeline_composite.py` — end-to-end nest: two pieces + engraved lines; assert invariants (fit, kerf, layer names in output doc, decoration count per piece); **no golden x/y**. Tags `[REQ-FIT-NEST-002]`, `[REQ-FIT-DXF-002]`.
**Implement:** Pipeline passes `CompositePiece` through `nest_multi_bin`; placements carry decoration payloads to output writer.
</step>

<step id="12" status="complete">
**Test:** `spec/services/dxf/piece_counter_spec.rb` — counts only primary layer polygons when `layer_role` primary set. Tag `[REQ-FIT-DXF-002]`.
**Implement:** `Dxf::PieceCounter` / readiness path uses primary layer only (not auxiliary).
</step>

<step id="13" status="complete">
**Test:** `nesting_engine/tests/test_dxf_preview_composite.py` or request spec for preview JSON — auxiliary polylines visible clipped in preview. Tag `[REQ-FIT-DXF-002]`, `[REQ-FIT-UI-004]`.
**Implement:** `dxf_preview.py` + Rails preview builder: include clipped aux geometry per included attachment.
</step>

<step id="14" status="complete">
**Test:** `spec/system/project_layers_composite_spec.rb` — select primary + aux → nest → download nested DXF; layers preserved (smoke). Tags `[REQ-FIT-DXF-002]`, `[REQ-FIT-UI-001]`.
**Implement:** System spec + any Stimulus/CSS for grouped layer UI (`data-testid` primary-layer-radio).
</step>

<step id="15" status="complete">
**Test:** `test/architecture/` or doc test — REQ-FIT-DXF-002 referenced. Tag `[REQ-FIT-ARCH-001]`.
**Implement:** Optional ADR `docs/core/ADRs/0003-composite-dxf-layers.md`; update `nesting_engine/README.md` CLI schema; ROADMAP v1.2 item.
</step>

<step id="16" status="complete">
**Test:** `nesting_engine/tests/test_split_composite.py` — mother `CompositePiece` with grabado line in each half → `plan_split` + `partition_decorations` yields two children; each child decoration count correct; clip on cut boundary. Tags `[REQ-FIT-DXF-002]`, `[REQ-FIT-SPLIT-001]`.
**Implement:** `partition_decorations(mother, split_children, cut_segments)` in `composite_extract.py` or `split_planner.py` helper; call from split plan pipeline when mother has decorations.
</step>

<step id="17">
**Test:** `nesting_engine/tests/test_cli_plan_splits_composite.py` — `plan_splits` for composite orphan → `split_preview.json` child geometries include `decorations[]` per child. Tags `[REQ-FIT-SPLIT-001]`, `[REQ-FIT-DXF-002]`.
**Implement:** `nest.py` plan mode loads mother as `CompositePiece`; preview + `child_piece_geometries` carry decoration payloads.
</step>

<step id="18">
**Test:** `spec/requests/split_proposals_accept_spec.rb` (extend) — accept persists `DerivedPiece` with `decorations_json`; `config_builder` emits derived pieces with decorations for nest. Tags `[REQ-FIT-SPLIT-001]`, `[REQ-FIT-DXF-002]`.
**Implement:** Migration `derived_pieces.decorations_json` (jsonb default `[]`); `MaterializeSplitProposal`; `ConfigBuilder#derived_pieces_payload`; `piece_loader._derived_pieces_from_config` attaches decorations.
</step>

<step id="19">
**Test:** `nesting_engine/tests/test_nest_pipeline_composite.py` (extend) — nest with derived composite children post-split; nested DXF has per-child aux on original layers after placement. Tags `[REQ-FIT-NEST-002]`, `[REQ-FIT-SPLIT-001]`, `[REQ-FIT-DXF-002]`.
**Implement:** End-to-end split → accept → nest updated pieces; invariant tests only.
</step>

<step id="20">
**Test:** Targeted `bundle exec rspec` (files above) + `pytest nesting_engine/tests -q -m "not slow"`.
**Implement:** Fix regressions; mark ROADMAP v1.2 composite layers (+ split note).
</step>

</implementation_plan>
