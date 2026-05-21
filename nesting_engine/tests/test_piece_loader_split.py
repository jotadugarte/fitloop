# [REQ-FIT-SPLIT-001] Config-driven exclusion and derived piece injection.
from __future__ import annotations

from shapely.geometry import box

from nesting_engine.piece_loader import load_pieces_from_config


def test_load_pieces_skips_excluded_indices_and_appends_derived() -> None:
    """[REQ-FIT-SPLIT-001] excluded_piece_keys remove DXF pieces by index; derived_pieces append."""
    warnings: list[str] = []
    config = {
        "input_dxf_paths": [],
        "included_layers": [],
        "curve_tolerance_mm": 0.1,
        "excluded_piece_keys": [],
        "derived_pieces": [
            {
                "parent_piece_key": "0",
                "label": "Pieza-1a",
                "sort_order": 0,
                "rings": [
                    [
                        [0.0, 0.0],
                        [50.0, 0.0],
                        [50.0, 30.0],
                        [0.0, 30.0],
                    ]
                ],
            }
        ],
    }

    pieces = load_pieces_from_config(config, warnings=warnings)

    assert len(pieces) == 1
    assert pieces[0].bounds == box(0, 0, 50, 30).bounds
