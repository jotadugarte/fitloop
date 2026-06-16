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

@pytest.mark.slow
def test_015_splits_valid_and_open_panels_from_extraction() -> None:
    path = Path(__file__).resolve().parent / "fixtures" / "individuals" / "015.dxf"

    preview = build_source_preview(
        [path],
        [],
        curve_tolerance_mm=0.25,
        file_configs=[{"primary_layer": CORTE, "auxiliary_layers": []}],
    )

    corte = {row["name"]: row for row in preview["layers"]}[CORTE]
    closed_exteriors = sum(
        1
        for is_open, is_internal in zip(
            corte["polyline_open_flags"],
            corte["polyline_internal_cut_flags"],
            strict=True,
        )
        if not is_open and not is_internal
    )
    open_n = sum(1 for is_open in corte["polyline_open_flags"] if is_open)
    assert closed_exteriors == 3
    assert open_n == 1
    assert len(corte["gaps"]) == 1
    assert len(corte["auto_close_lines"]) == 1


@pytest.mark.slow
def test_015_valid_panel_includes_primary_internal_cut_lines() -> None:
    path = Path(__file__).resolve().parent / "fixtures" / "individuals" / "015.dxf"

    preview = build_source_preview(
        [path],
        [],
        curve_tolerance_mm=0.25,
        file_configs=[{"primary_layer": CORTE, "auxiliary_layers": []}],
    )

    corte = {row["name"]: row for row in preview["layers"]}[CORTE]
    internal_cut_count = sum(
        1
        for is_open, is_internal in zip(
            corte["polyline_open_flags"],
            corte["polyline_internal_cut_flags"],
            strict=True,
        )
        if not is_open and is_internal
    )
    assert internal_cut_count >= 2


@pytest.mark.slow
def test_008_preview_has_no_false_open_gaps_when_extraction_is_single_piece() -> None:
    """[REQ-FIT-DXF-002] Micro-gaps on absorbed crossbar segments must not block the workshop."""
    path = Path(__file__).resolve().parent / "fixtures" / "individuals" / "008.dxf"

    preview = build_source_preview(
        [path],
        [],
        curve_tolerance_mm=0.25,
        file_configs=[{"primary_layer": CORTE, "auxiliary_layers": []}],
    )

    corte = {row["name"]: row for row in preview["layers"]}[CORTE]
    closed_exteriors = sum(
        1
        for is_open, is_internal in zip(
            corte["polyline_open_flags"],
            corte["polyline_internal_cut_flags"],
            strict=True,
        )
        if not is_open and not is_internal
    )
    open_n = sum(1 for is_open in corte["polyline_open_flags"] if is_open)
    assert closed_exteriors == 1
    assert open_n == 0
    assert corte["gaps"] == []
    assert corte["auto_close_lines"] == []


@pytest.mark.slow
def test_015_marcado_auxiliary_shows_on_open_piece_before_auto_close() -> None:
    path = Path(__file__).resolve().parent / "fixtures" / "individuals" / "015.dxf"

    preview = build_source_preview(
        [path],
        [],
        curve_tolerance_mm=0.25,
        file_configs=[{"primary_layer": CORTE, "auxiliary_layers": ["MARCADO"]}],
    )

    layers = {row["name"]: row for row in preview["layers"]}
    assert "MARCADO" in layers
    marcado = layers["MARCADO"]
    assert marcado["polylines"]
    assert all(marcado["polyline_open_flags"])


@pytest.mark.slow
def test_015_auto_close_moves_open_piece_and_marcado_to_valid_panel() -> None:
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
    closed_exteriors = sum(
        1
        for is_open, is_internal in zip(
            corte["polyline_open_flags"],
            corte["polyline_internal_cut_flags"],
            strict=True,
        )
        if not is_open and not is_internal
    )
    assert closed_exteriors == 4
    assert not any(corte["polyline_open_flags"])

    marcado = layers["MARCADO"]
    assert marcado["polylines"]
    assert not any(marcado["polyline_open_flags"])
