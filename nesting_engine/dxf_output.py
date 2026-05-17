"""Write nested DXF with sheets offset on +X."""

from __future__ import annotations

from pathlib import Path

import ezdxf
from shapely.affinity import rotate, translate

from nesting_engine.nest_bin import NestedSheet, PlacedPiece


def write_nested_dxf(path: Path | str, sheets: list[NestedSheet]) -> None:
    assert sheets is not None, "sheets required"

    doc = ezdxf.new("R2010")
    _ensure_output_layers(doc)
    msp = doc.modelspace()

    for sheet in sheets:
        _add_sheet_outline(msp, sheet)
        for placed in sheet.pieces:
            _add_piece(msp, placed, sheet_offset_x=sheet.offset_x_mm)

    doc.saveas(path)


def _ensure_output_layers(doc: ezdxf.document.Drawing) -> None:
    for layer_name in ("SHEETS", "PIECES"):
        if layer_name not in doc.layers:
            doc.layers.add(layer_name)


def _add_sheet_outline(msp, sheet: NestedSheet) -> None:
    x0 = sheet.offset_x_mm
    y0 = 0.0
    points = [
        (x0, y0),
        (x0 + sheet.width_mm, y0),
        (x0 + sheet.width_mm, y0 + sheet.height_mm),
        (x0, y0 + sheet.height_mm),
    ]
    msp.add_lwpolyline(points, close=True, dxfattribs={"layer": "SHEETS"})


def _add_piece(msp, placed: PlacedPiece, *, sheet_offset_x: float) -> None:
    rotated = rotate(placed.polygon, placed.placement.rotation_deg, origin="centroid")
    # placement.x/y are translation offsets from nest_spike (margin - bounds.min), not absolute coords.
    world = translate(
        rotated,
        xoff=placed.placement.x + sheet_offset_x,
        yoff=placed.placement.y,
    )

    msp.add_lwpolyline(
        list(world.exterior.coords),
        close=True,
        dxfattribs={"layer": "PIECES"},
    )
    for interior in world.interiors:
        msp.add_lwpolyline(list(interior.coords), close=True, dxfattribs={"layer": "PIECES"})
