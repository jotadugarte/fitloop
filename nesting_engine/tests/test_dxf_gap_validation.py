# [REQ-FIT-VAL-001] Tests for DXF gap validation thresholds and preview.
from __future__ import annotations

from pathlib import Path
import ezdxf
import pytest

from nesting_engine.extract import extract_closed_contours
from nesting_engine.dxf_preview import build_source_preview

LAYER = "PIECES"


def create_open_polyline_dxf(path: Path, gap_size: float) -> None:
    doc = ezdxf.new("R2010")
    # A box of 100 x 100 with a gap of gap_size at the start/end
    # The gap is between (0, 0) and (gap_size, 0)
    doc.modelspace().add_lwpolyline(
        [(gap_size, 0.0), (100.0, 0.0), (100.0, 100.0), (0.0, 100.0), (0.0, 0.0)],
        close=False,
        dxfattribs={"layer": LAYER},
    )
    doc.saveas(path)


def test_extract_silent_gap_auto_closes(tmp_path: Path) -> None:
    # Gap size <= 2.0 mm (e.g., 1.5 mm) should be closed silently by default
    dxf_path = tmp_path / "silent_gap.dxf"
    create_open_polyline_dxf(dxf_path, 1.5)

    contours = extract_closed_contours(dxf_path, layer_name=LAYER, auto_close_gaps=False)
    assert len(contours) == 1
    assert contours[0].area == pytest.approx(10000.0, abs=200.0)


def test_extract_medium_gap_respects_parameter(tmp_path: Path) -> None:
    # Gap size between 2.0 mm and 15.0 mm (e.g., 5.0 mm)
    dxf_path = tmp_path / "medium_gap.dxf"
    create_open_polyline_dxf(dxf_path, 5.0)

    # By default, should not close
    contours_no_close = extract_closed_contours(dxf_path, layer_name=LAYER, auto_close_gaps=False)
    assert len(contours_no_close) == 0

    # If auto_close_gaps=True, should close
    contours_close = extract_closed_contours(dxf_path, layer_name=LAYER, auto_close_gaps=True)
    assert len(contours_close) == 1
    assert contours_close[0].area == pytest.approx(10000.0, abs=200.0)


def test_extract_large_gap_is_never_closed(tmp_path: Path) -> None:
    # Gap size > 15.0 mm (e.g., 20.0 mm) should never be closed
    dxf_path = tmp_path / "large_gap.dxf"
    create_open_polyline_dxf(dxf_path, 20.0)

    contours = extract_closed_contours(dxf_path, layer_name=LAYER, auto_close_gaps=True)
    assert len(contours) == 0


def test_preview_reports_gaps_on_layer(tmp_path: Path) -> None:
    dxf_path = tmp_path / "preview_gap.dxf"
    create_open_polyline_dxf(dxf_path, 5.0)

    preview = build_source_preview([dxf_path], [LAYER])

    assert "layers" in preview
    layer_preview = preview["layers"][0]
    assert "gaps" in layer_preview
    assert len(layer_preview["gaps"]) == 1

    gap = layer_preview["gaps"][0]
    assert gap["distance_mm"] == pytest.approx(5.0)
    assert gap["start"] == [5.0, 0.0]
    assert gap["end"] == [0.0, 0.0]
    assert gap["auto_closed"] is False


def test_preview_with_auto_close_draws_dashed_closure(tmp_path: Path) -> None:
    dxf_path = tmp_path / "preview_auto_close.dxf"
    create_open_polyline_dxf(dxf_path, 5.0)

    file_configs = [{"layer_names": [LAYER], "auto_close_layers": [LAYER]}]
    preview = build_source_preview([dxf_path], [LAYER], file_configs=file_configs)

    layer_preview = preview["layers"][0]
    assert "gaps" in layer_preview
    assert len(layer_preview["gaps"]) == 1
    assert layer_preview["gaps"][0]["auto_closed"] is True

    assert "auto_close_lines" in layer_preview
    assert len(layer_preview["auto_close_lines"]) == 1
    assert layer_preview["auto_close_lines"][0] == [[5.0, 0.0], [0.0, 0.0]]
