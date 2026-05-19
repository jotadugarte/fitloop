# [REQ-FIT-DXF-002] Nested DXF preserves original layer names for composite pieces.
from __future__ import annotations

from pathlib import Path

import ezdxf
from shapely.geometry import box

from nesting_engine.composite_extract import DecorationEntity
from nesting_engine.dxf_output import write_nested_dxf
from nesting_engine.nest_placement import Placement
from nesting_engine.nest_types import NestedSheet, PlacedPiece

CORTE = "CORTE"
GRABADO = "GRABADO"


def test_write_nested_dxf_uses_original_layer_names_for_composite_pieces(
    tmp_path: Path,
) -> None:
    primary = box(0, 0, 40, 40)
    decoration = DecorationEntity(
        layer_name=GRABADO,
        geometry_type="line",
        payload={"coordinates": [[10.0, 20.0], [30.0, 20.0]]},
    )
    placed = PlacedPiece(
        piece_index=0,
        polygon=primary,
        placement=Placement(x=5.0, y=5.0, rotation_deg=0.0),
        primary_layer_name=CORTE,
        decorations=(decoration,),
    )
    sheet = NestedSheet(
        stock_sort_order=0,
        sheet_index=0,
        width_mm=200.0,
        height_mm=150.0,
        offset_x_mm=0.0,
        pieces=[placed],
    )

    out_path = tmp_path / "nested-composite.dxf"
    write_nested_dxf(out_path, [sheet])

    doc = ezdxf.readfile(out_path)
    layer_names = {layer.dxf.name for layer in doc.layers}
    assert "SHEETS" in layer_names
    assert CORTE in layer_names
    assert GRABADO in layer_names

    modelspace = list(doc.modelspace())
    assert any(entity.dxf.layer == "SHEETS" for entity in modelspace)
    corte_entities = [entity for entity in modelspace if entity.dxf.layer == CORTE]
    grabado_entities = [entity for entity in modelspace if entity.dxf.layer == GRABADO]
    pieces_entities = [entity for entity in modelspace if entity.dxf.layer == "PIECES"]

    assert len(corte_entities) >= 1
    assert len(grabado_entities) >= 1
    assert len(pieces_entities) == 0
