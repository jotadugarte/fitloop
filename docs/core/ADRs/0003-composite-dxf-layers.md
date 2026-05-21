# ADR-0003: Composite DXF layers (primary + auxiliary) (v1.2)

**Status:** Accepted  
**Date:** 2026-05-18  
**REQ:** REQ-FIT-DXF-002

## Context and problem statement

Shop DXFs often separate **cut outlines** from **engraving, marks, and text** on different layers. v1 treated every included layer as nestable closed contours, which mis-counts pieces, nests decoration geometry as independent parts, and forces output onto a single `PIECES` layer.

Users need one **primary (cut) layer per file**, optional **auxiliary** layers clipped to those outlines, and a **nested DXF** that preserves original AutoCAD layer names for CAM/post.

## Decision drivers

- Per-file layer roles in Rails (`ProjectLayer.layer_role`) without breaking legacy union mode
- Nesting math stays in Python; Rails emits CLI config only
- Kerf and margin semantics unchanged (`margin_mm` sheet edge, `kerf_mm` piece-to-piece)
- Invariant tests only (fit, kerf clearance, layer names)—no golden x/y coordinates
- Auto-split must partition decorations with the same cuts as the primary polygon (`REQ-FIT-SPLIT-001`; follow-up steps 16–19)

## Decision outcome

**Chosen:** Composite extract → nest primary polygons only → transform and emit decorations on source layers.

### Rails

- `layer_role`: `primary` | `auxiliary` | nil (legacy).
- `ProjectLayer::SetPrimary` — exclusive primary per attachment; primary implies `included`.
- Pre-flight: auxiliary without primary on the same file → error (`REQ-FIT-VAL-001`).
- `Nesting::ConfigBuilder` — per-file `input_files[]` with `primary_layer` + `auxiliary_layers[]`, or legacy `included_layers`.
- `Dxf::PieceCounter.layer_names_for_count` — primary layer only when composite mode is active.
- Source preview — clipped auxiliary polylines via `dxf_preview` + `input_files` config.

### Python

- `composite_extract.load_composite_pieces` → `CompositePiece` + `DecorationEntity[]` (Option B clip, insert-point TEXT/INSERT).
- `piece_loader` selects composite path when `primary_layer` is set.
- `nest_multi_bin` uses `piece_polygon()` / `placed_piece_from_source` for `CompositePiece`.
- `decoration_transform` + `dxf_output` — nested DXF keeps `CORTE` / `GRABADO` (etc.), not forced `PIECES`.

### Positive consequences

- CAM-ready nested DXF with recognizable layer names
- Accurate pre-flight piece counts (cut outlines only)
- Legacy projects without `layer_role` behave as before

### Negative consequences

- Per-file layer UI is required for composite mode (not union-checkbox only)
- Split + derived-piece decoration pipeline is additional work (SPEC cross-ref; not in initial v1.2 core ship)

## Validation

- RSpec: `project_layer_spec`, `project_layers_spec`, `config_builder_spec`, `piece_counter_spec`, `project_readiness_validator_spec`, `project_source_preview_spec`
- pytest: `test_composite_extract.py`, `test_piece_loader_composite.py`, `test_decoration_transform.py`, `test_dxf_output_composite.py`, `test_nest_pipeline_composite.py`, `test_dxf_preview_composite.py`
- System: `spec/system/project_layers_composite_spec.rb`
- Docs: `test/spec/composite_dxf_spec_doc_test.rb`, `test/architecture/composite_dxf_architecture_doc_test.rb`
