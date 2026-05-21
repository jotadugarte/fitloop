# [REQ-FIT-DXF-002] [REQ-FIT-SPLIT-001] Derived pieces with decorations load as CompositePiece.
from __future__ import annotations

from nesting_engine.composite_extract import CompositePiece
from nesting_engine.piece_loader import load_pieces_from_config


def test_derived_pieces_with_decorations_load_as_composite_piece() -> None:
    warnings: list[str] = []
    config = {
        "input_dxf_paths": [],
        "included_layers": [],
        "curve_tolerance_mm": 0.1,
        "derived_pieces": [
            {
                "parent_piece_key": "0",
                "label": "Pieza-1a",
                "sort_order": 0,
                "primary_layer_name": "CORTE",
                "rings": [
                    [
                        [0.0, 0.0],
                        [50.0, 0.0],
                        [50.0, 30.0],
                        [0.0, 30.0],
                    ]
                ],
                "decorations": [
                    {
                        "layer_name": "GRABADO",
                        "geometry_type": "line",
                        "payload": {"coordinates": [[5.0, 15.0], [45.0, 15.0]]},
                    }
                ],
            }
        ],
    }

    pieces = load_pieces_from_config(config, warnings=warnings)

    assert len(pieces) == 1
    piece = pieces[0]
    assert isinstance(piece, CompositePiece)
    assert piece.primary_layer_name == "CORTE"
    assert len(piece.decorations) == 1
    assert piece.decorations[0].layer_name == "GRABADO"
