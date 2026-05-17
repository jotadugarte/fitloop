"""Preview linework tests for arc slots."""

from __future__ import annotations

from pathlib import Path

import ezdxf

from nesting_engine.dxf_preview import build_source_preview

LAYER = "PIECES"


def test_preview_includes_pointed_slot_tip_lines(tmp_path: Path) -> None:
    path = tmp_path / "slot_tip_lines.dxf"
    doc = ezdxf.new("R2010")
    msp = doc.modelspace()
    msp.add_arc(center=(70, 0), radius=25, start_angle=90, end_angle=270, dxfattribs={"layer": LAYER})
    msp.add_arc(center=(170, 0), radius=25, start_angle=270, end_angle=90, dxfattribs={"layer": LAYER})
    msp.add_line((70, -25), (170, -25), dxfattribs={"layer": LAYER})
    msp.add_line((170, 25), (70, 25), dxfattribs={"layer": LAYER})
    msp.add_line((195, 25), (205, 0), dxfattribs={"layer": LAYER})
    msp.add_line((205, 0), (195, -25), dxfattribs={"layer": LAYER})
    doc.saveas(path)

    preview = build_source_preview([path], [LAYER], curve_tolerance_mm=0.1)
    polylines = preview["layers"][0]["polylines"]

    assert len(polylines) == 6
    tip_lines = [line for line in polylines if len(line) == 2 and line[0][0] >= 195.0]
    assert len(tip_lines) == 2
