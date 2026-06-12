# [REQ-FIT-DXF-002] piece_loader uses composite extract when primary_layer is set.
from __future__ import annotations

from pathlib import Path

import ezdxf
from shapely.geometry import Polygon

from nesting_engine.composite_extract import CompositePiece
from nesting_engine.piece_loader import load_pieces_from_config

CORTE = "CORTE"
GRABADO = "GRABADO"


def _write_composite_fixture(path: Path) -> None:
    doc = ezdxf.new("R2010")
    msp = doc.modelspace()
    msp.add_lwpolyline(
        [(0, 0), (40, 0), (40, 40), (0, 40)],
        close=True,
        dxfattribs={"layer": CORTE},
    )
    msp.add_lwpolyline(
        [(60, 0), (100, 0), (100, 40), (60, 40)],
        close=True,
        dxfattribs={"layer": CORTE},
    )
    msp.add_line((35, 20), (65, 20), dxfattribs={"layer": GRABADO})
    msp.add_text("MARK", dxfattribs={"layer": GRABADO, "insert": (20, 20)})
    doc.saveas(path)


def test_load_pieces_from_config_uses_composite_path_when_primary_layer_set(
    tmp_path: Path,
) -> None:
    path = tmp_path / "composite-loader.dxf"
    _write_composite_fixture(path)
    warnings: list[str] = []

    pieces = load_pieces_from_config(
        {
            "curve_tolerance_mm": 0.25,
            "input_files": [
                {
                    "path": str(path),
                    "primary_layer": CORTE,
                    "auxiliary_layers": [GRABADO],
                }
            ],
        },
        warnings=warnings,
    )

    assert len(pieces) == 2
    assert all(isinstance(piece, CompositePiece) for piece in pieces)
    decoration_count = sum(len(piece.decorations) for piece in pieces)
    assert decoration_count >= 3


def test_load_pieces_from_config_legacy_included_layers_returns_composite_pieces(tmp_path: Path) -> None:
    """included_layers now returns CompositePiece objects so that internal cut lines
    from overlapping polylines are preserved in the output DXF.  Pieces that do NOT
    overlap have no decorations, but they are still CompositePiece instances."""
    path = tmp_path / "legacy-loader.dxf"
    _write_composite_fixture(path)
    warnings: list[str] = []

    pieces = load_pieces_from_config(
        {
            "curve_tolerance_mm": 0.25,
            "input_files": [
                {
                    "path": str(path),
                    "included_layers": [CORTE],
                }
            ],
        },
        warnings=warnings,
    )

    assert len(pieces) == 2
    # Pieces are now CompositePiece objects carrying the layer name
    assert all(isinstance(piece, CompositePiece) for piece in pieces)
    # The two rectangles do NOT overlap, so no internal line decorations are needed
    assert all(len(piece.decorations) == 0 for piece in pieces)
