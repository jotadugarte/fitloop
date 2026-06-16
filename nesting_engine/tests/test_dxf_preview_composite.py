# [REQ-FIT-DXF-002] [REQ-FIT-UI-004] Source preview shows clipped auxiliary geometry.
from __future__ import annotations

from pathlib import Path

import ezdxf
import pytest

from nesting_engine.dxf_preview import build_source_preview

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
    msp.add_line((200, 200), (220, 210), dxfattribs={"layer": GRABADO})
    doc.saveas(path)


def _polyline_length_mm(line: list[list[float]]) -> float:
    total = 0.0
    for index in range(1, len(line)):
        dx = line[index][0] - line[index - 1][0]
        dy = line[index][1] - line[index - 1][1]
        total += (dx * dx + dy * dy) ** 0.5
    return total


def test_build_source_preview_includes_clipped_auxiliary_polylines(tmp_path: Path) -> None:
    path = tmp_path / "composite-preview.dxf"
    _write_composite_fixture(path)

    preview = build_source_preview(
        [path],
        [],
        curve_tolerance_mm=0.25,
        file_configs=[{"primary_layer": CORTE, "auxiliary_layers": [GRABADO]}],
    )

    layers = {row["name"]: row for row in preview["layers"]}
    assert CORTE in layers
    assert GRABADO in layers
    assert len(layers[CORTE]["polylines"]) == 2

    grabado_lines = layers[GRABADO]["polylines"]
    assert grabado_lines
    grabado_points = [point for line in grabado_lines for point in line]
    assert all(not (point[0] > 150 and point[1] > 150) for point in grabado_points)

    grabado_length = sum(_polyline_length_mm(line) for line in grabado_lines)
    assert grabado_length == pytest.approx(10.0, abs=1.5)


@pytest.mark.slow
def test_015_open_corte_shows_marcado_in_open_auxiliary_preview() -> None:
    """[REQ-FIT-DXF-002] Option B: auxiliary marks inside open primary before auto-close."""
    path = Path(__file__).resolve().parent / "fixtures" / "individuals" / "015.dxf"

    preview = build_source_preview(
        [path],
        [],
        curve_tolerance_mm=0.25,
        file_configs=[{"primary_layer": CORTE, "auxiliary_layers": ["MARCADO"]}],
    )

    layers = {row["name"]: row for row in preview["layers"]}
    assert CORTE in layers
    assert "MARCADO" in layers

    corte = layers[CORTE]
    closed_corte = sum(1 for is_open in corte["polyline_open_flags"] if not is_open)
    open_corte = sum(1 for is_open in corte["polyline_open_flags"] if is_open)
    assert closed_corte == 3
    assert open_corte == 1
    assert len(corte["gaps"]) == 1
    assert len(corte["auto_close_lines"]) == 1
    assert corte["gaps"][0]["distance_mm"] == pytest.approx(14.8348, rel=1e-3)

    marcado = layers["MARCADO"]
    assert marcado["polylines"]
    assert all(marcado["polyline_open_flags"])


@pytest.mark.slow
def test_015_auto_close_moves_marcado_to_valid_panel() -> None:
    path = Path(__file__).resolve().parent / "fixtures" / "individuals" / "015.dxf"

    preview = build_source_preview(
        [path],
        [],
        curve_tolerance_mm=0.25,
        file_configs=[
            {
                "primary_layer": CORTE,
                "auxiliary_layers": ["MARCADO"],
                "auto_close_layers": [CORTE],
            }
        ],
    )

    layers = {row["name"]: row for row in preview["layers"]}
    corte = layers[CORTE]
    assert not any(corte["polyline_open_flags"])
    assert sum(1 for is_open in corte["polyline_open_flags"] if not is_open) == 4

    marcado = layers["MARCADO"]
    assert marcado["polylines"]
    assert not any(marcado["polyline_open_flags"])
