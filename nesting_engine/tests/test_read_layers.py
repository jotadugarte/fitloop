"""Tests for DXF layer name discovery."""

from __future__ import annotations

from pathlib import Path

from nesting_engine.read_layers import union_layer_names

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "sample_piece.dxf"


def test_union_includes_pieces_layer() -> None:
    names = union_layer_names([FIXTURE])
    assert "PIECES" in names
