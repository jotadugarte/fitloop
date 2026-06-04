# Task: Real Student DXF — Extract Hardening
**Created:** 2026-06-03  
**Status:** Discovery — awaiting first real DXF fixture

---

## Context

A real student DXF was tested against the current `extract.py` pipeline and produced multiple failures:
- Forms not recognized (silently ignored)
- Forms distorted (geometry wrong)
- Forms split into multiple pieces when they should be one

The **strategy chosen**: TDD incremental hardening.
- ❌ NOT a rewrite from scratch
- ✅ Feed real DXF fragments one by one → write failing test → fix → verify no regression → scale up

---

## Architecture Boundary (non-negotiable)
Per `SYSTEM_ARCHITECTURE.md`:
- DXF parsing and geometry math lives in Python (`nesting_engine/`)
- Rails does NOT perform nesting math
- Test fixtures go in `nesting_engine/tests/fixtures/`
- Test files follow existing pattern: `test_extract_*.py`

---

## Layer Decision Protocol (Architecture Reference)

El engine tiene **dos modos** según `ProjectLayer.layer_role`:

| Rol | Capa | Qué hace el engine |
|-----|------|--------------------|
| **`primary`** | 1 sola por archivo | `extract_closed_contours` → contornos de corte (los polígonos que se anidan) |
| **`auxiliary`** | 0 o más por archivo | `load_composite_pieces` → decoraciones internas (grabado, texto, marcas) — se clipean al polígono primario |
| **`included`** (sin rol) | N capas planas | `extract_closed_contours` por cada capa — modo legacy sin decoraciones |

### Regla de decisión al recibir un DXF real:

1. **Listar todos los layers** del DXF con el comando `--layers` del diagnóstico
2. **Identificar cuál layer tiene los contornos exteriores** de las piezas → ese es `primary`
3. **Identificar layers con geometría interior** (grabado, texto, líneas internas, agujeros no cerrados) → esos son `auxiliary`
4. **Si todo está en un solo layer** → modo `included` simple (solo `extract_closed_contours`)
5. **Si hay agujeros reales cerrados** (huecos dentro del contorno) → deben estar en el mismo layer que el primario; el engine los convierte en `Polygon.interiors`

### Flujo código:
```
primary_layer ──► extract_closed_contours() ──► list[Polygon] (con holes si aplica)
                                                      │
auxiliary_layers ──► load_composite_pieces() ──► list[CompositePiece]
                                                      │ .polygon = Polygon
                                                      └ .decorations = [DecorationEntity]
```

---

## Workflow Protocol

Each shape fragment follows this cycle:
```
1. User drops a .dxf fragment file
2. Agent inspects the file: entity types, layer, structure
3. Agent writes a FAILING test in test_extract_real_student.py
4. Agent runs the test → confirms RED
5. Agent patches extract.py (or composite_extract.py if needed)
6. Agent runs test → confirms GREEN
7. Agent runs full test suite → confirms NO REGRESSION
8. Move to next fragment
```

---

## Scratchpad — Shapes Catalog

Track each fragment as it comes in:

| # | Fixture file | Entity types | Problem type | Test | Status |
|---|---|---|---|---|---|
| — | (none yet) | — | — | — | 🔴 waiting |

---

## Known Issues (pre-existing from real file test)

To be filled as fragments arrive:
- [ ] TBD — form type unknown until fragments shared

---

## Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-06-03 | Keep existing `extract.py`, do NOT rewrite from scratch | 834 lines of working logic + full test suite = too much to throw away; bugs are edge cases, not structural failures |
| 2026-06-03 | TDD incremental: fragment → failing test → fix → no regression | Gives coverage of real-world cases without breaking existing working paths |
| 2026-06-03 | New test file: `test_extract_real_student.py` | Keep real-student tests isolated from synthetic ones for clarity |

---

## Test Infrastructure

- **Existing fixtures dir:** `nesting_engine/tests/fixtures/`
- **New test file:** `nesting_engine/tests/test_extract_real_student.py` (to be created)
- **Run all extract tests:** `cd nesting_engine && python -m pytest tests/test_extract*.py -v`
- **Run suite:** `cd nesting_engine && python -m pytest tests/ -v`

---

## Implementation Plan

*(To be filled when enough shapes are characterized — after at least 3-4 fragments analyzed)*
