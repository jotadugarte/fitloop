"""Tests for DXF layer name and color discovery."""

from __future__ import annotations

from pathlib import Path

from nesting_engine.read_layers import layer_catalog, union_layer_names

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "sample_piece.dxf"


def test_union_includes_pieces_layer() -> None:
    names = union_layer_names([FIXTURE])
    assert "PIECES" in names


def test_catalog_includes_hex_color() -> None:
    catalog = layer_catalog([FIXTURE])
    pieces = next(entry for entry in catalog if entry["name"] == "PIECES")
    assert pieces["color"].startswith("#")
    assert len(pieces["color"]) == 7
