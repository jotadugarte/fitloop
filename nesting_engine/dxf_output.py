"""Write nested DXF with sheets offset on +X."""

from __future__ import annotations

from pathlib import Path

import ezdxf
from shapely.affinity import rotate, translate

from nesting_engine.nest_types import NestedSheet, PlacedPiece


def write_piece_dxf(
    path: Path | str,
    rings: list[list[list[float]]],
    *,
    layer_name: str = "PIECES",
) -> None:
    assert rings, "at least one ring is required"
    assert len(rings[0]) >= 3, "exterior ring must have at least three points"

    doc = ezdxf.new("R2010")
    if layer_name not in doc.layers:
        doc.layers.add(layer_name)
    msp = doc.modelspace()

    exterior = [(float(x), float(y)) for x, y in rings[0]]
    msp.add_lwpolyline(exterior, close=True, dxfattribs={"layer": layer_name})
    for hole in rings[1:]:
        if len(hole) < 3:
            continue
        coords = [(float(x), float(y)) for x, y in hole]
        msp.add_lwpolyline(coords, close=True, dxfattribs={"layer": layer_name})

    doc.saveas(path)


def write_nested_dxf(
    path: Path | str,
    sheets: list[NestedSheet],
    *,
    cut_segments: list | None = None,
    piece_labels: dict[int, str] | None = None,
) -> None:
    assert sheets is not None, "sheets required"

    doc = ezdxf.new("R2010")
    _ensure_output_layers(doc)
    msp = doc.modelspace()

    labels = piece_labels or {}
    sheet_offset_x = sheets[0].offset_x_mm if sheets else 0.0
    for segment in cut_segments or []:
        _add_cut_segment(msp, segment, sheet_offset_x=sheet_offset_x)

    for sheet in sheets:
        _add_sheet_outline(msp, sheet)
        for placed in sheet.pieces:
            _add_piece(msp, placed, sheet_offset_x=sheet.offset_x_mm)
            label = labels.get(placed.piece_index)
            if label:
                _add_piece_label(msp, placed, label, sheet_offset_x=sheet.offset_x_mm)

    doc.saveas(path)


def _ensure_output_layers(doc: ezdxf.document.Drawing) -> None:
    for layer_name in ("SHEETS", "PIECES", "SPLIT_CUTS", "SPLIT_LABELS"):
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
    # placement.x/y are translation offsets from nest_placement (margin - bounds.min), not absolute coords.
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


def _add_cut_segment(msp, segment, *, sheet_offset_x: float) -> None:
    assert len(segment) == 2, "cut segment must have start and end points"
    start, end = segment
    msp.add_line(
        (float(start[0]) + sheet_offset_x, float(start[1])),
        (float(end[0]) + sheet_offset_x, float(end[1])),
        dxfattribs={"layer": "SPLIT_CUTS"},
    )


def _add_piece_label(msp, placed: PlacedPiece, label: str, *, sheet_offset_x: float) -> None:
    rotated = rotate(placed.polygon, placed.placement.rotation_deg, origin="centroid")
    world = translate(
        rotated,
        xoff=placed.placement.x + sheet_offset_x,
        yoff=placed.placement.y,
    )
    centroid = world.centroid
    text = msp.add_text(label, dxfattribs={"layer": "SPLIT_LABELS", "height": 5.0})
    text.set_placement((float(centroid.x), float(centroid.y)))
