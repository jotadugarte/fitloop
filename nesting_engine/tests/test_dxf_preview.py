"""Tests for layer-filtered DXF source preview geometry."""

from __future__ import annotations

from pathlib import Path

from nesting_engine.dxf_preview import build_source_preview

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "sample_piece.dxf"
LAYER = "PIECES"


def test_build_source_preview_includes_selected_layer_geometry() -> None:
    preview = build_source_preview([FIXTURE], [LAYER], curve_tolerance_mm=0.25)

    assert preview["width_mm"] > 0
    assert preview["height_mm"] > 0
    layers = preview["layers"]
    assert len(layers) == 1
    assert layers[0]["name"] == LAYER
    assert layers[0]["color"].startswith("#")
    assert layers[0]["polylines"]


def test_build_source_preview_hides_unselected_layers() -> None:
    preview = build_source_preview([FIXTURE], ["MISSING_LAYER"], curve_tolerance_mm=0.25)

    assert preview["layers"] == []
