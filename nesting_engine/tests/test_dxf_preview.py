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


def create_open_polyline_dxf(path: Path, layer: str, gap_size: float) -> None:
    import ezdxf
    doc = ezdxf.new("R2010")
    doc.modelspace().add_lwpolyline(
        [(gap_size, 0.0), (100.0, 0.0), (100.0, 100.0), (0.0, 100.0), (0.0, 0.0)],
        close=False,
        dxfattribs={"layer": layer},
    )
    doc.saveas(path)


def test_preview_auto_close_under_threshold(tmp_path: Path) -> None:
    dxf_path = tmp_path / "preview_auto_close_under.dxf"
    create_open_polyline_dxf(dxf_path, LAYER, 5.0)

    file_configs = [{"layer_names": [LAYER], "auto_close_layers": [LAYER]}]
    preview = build_source_preview([dxf_path], [LAYER], file_configs=file_configs)

    layer_preview = preview["layers"][0]
    assert len(layer_preview["gaps"]) == 1
    assert layer_preview["gaps"][0]["distance_mm"] == 5.0
    assert layer_preview["gaps"][0]["auto_closed"] is True
    assert len(layer_preview["auto_close_lines"]) == 1
    assert layer_preview["auto_close_lines"][0] == [[5.0, 0.0], [0.0, 0.0]]


def test_preview_auto_close_over_threshold_does_not_close(tmp_path: Path) -> None:
    dxf_path = tmp_path / "preview_auto_close_over.dxf"
    create_open_polyline_dxf(dxf_path, LAYER, 20.0)

    file_configs = [{"layer_names": [LAYER], "auto_close_layers": [LAYER]}]
    preview = build_source_preview([dxf_path], [LAYER], file_configs=file_configs)

    layer_preview = preview["layers"][0]
    assert len(layer_preview["gaps"]) == 1
    assert layer_preview["gaps"][0]["distance_mm"] == 20.0
    assert layer_preview["gaps"][0]["auto_closed"] is False
    assert len(layer_preview["auto_close_lines"]) == 0

