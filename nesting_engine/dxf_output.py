"""Write nested DXF with sheets offset on +X."""

from __future__ import annotations

from pathlib import Path

import ezdxf
from shapely.affinity import rotate, translate

from nesting_engine.composite_extract import DecorationEntity
from nesting_engine.decoration_transform import transform_decorations
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
    labels = piece_labels or {}
    cuts = cut_segments or []
    include_split_annotations = bool(labels or cuts)
    _ensure_output_layers(doc, sheets, include_split_annotations=include_split_annotations)
    msp = doc.modelspace()

    if include_split_annotations:
        sheet_offset_x = sheets[0].offset_x_mm if sheets else 0.0
        for segment in cuts:
            _add_cut_segment(msp, segment, sheet_offset_x=sheet_offset_x)

    for sheet in sheets:
        _add_sheet_outline(msp, sheet)
        for placed in sheet.pieces:
            _add_piece(msp, placed, sheet_offset_x=sheet.offset_x_mm)
            label = labels.get(placed.piece_index)
            if label:
                _add_piece_label(msp, placed, label, sheet_offset_x=sheet.offset_x_mm)

    doc.saveas(path)


def _ensure_output_layers(
    doc: ezdxf.document.Drawing,
    sheets: list[NestedSheet],
    *,
    include_split_annotations: bool,
) -> None:
    layer_names = {"SHEETS"}
    uses_legacy_pieces = False
    for sheet in sheets:
        for placed in sheet.pieces:
            if placed.primary_layer_name:
                layer_names.add(placed.primary_layer_name)
            else:
                uses_legacy_pieces = True
            for decoration in placed.decorations:
                layer_names.add(decoration.layer_name)
    if uses_legacy_pieces:
        layer_names.add("PIECES")
    if include_split_annotations:
        layer_names.update(["SPLIT_CUTS", "SPLIT_LABELS"])
    for layer_name in sorted(layer_names):
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
    layer_name = placed.primary_layer_name or "PIECES"
    world = _world_polygon(placed.polygon, placed.placement, sheet_offset_x=sheet_offset_x)

    msp.add_lwpolyline(
        list(world.exterior.coords),
        close=True,
        dxfattribs={"layer": layer_name},
    )
    for interior in world.interiors:
        msp.add_lwpolyline(list(interior.coords), close=True, dxfattribs={"layer": layer_name})

    if placed.decorations:
        decorations = transform_decorations(
            list(placed.decorations),
            placed.polygon,
            placed.placement,
        )
        for decoration in decorations:
            _add_decoration(msp, decoration, sheet_offset_x=sheet_offset_x)


def _world_polygon(polygon, placement, *, sheet_offset_x: float):
    rotated = rotate(polygon, placement.rotation_deg, origin="centroid")
    return translate(
        rotated,
        xoff=placement.x + sheet_offset_x,
        yoff=placement.y,
    )


def _add_decoration(msp, decoration: DecorationEntity, *, sheet_offset_x: float) -> None:
    layer_name = decoration.layer_name
    if decoration.geometry_type == "line":
        coords = decoration.payload["coordinates"]
        points = [(float(x) + sheet_offset_x, float(y)) for x, y in coords]
        if len(points) == 2:
            msp.add_line(points[0], points[1], dxfattribs={"layer": layer_name})
            return
        msp.add_lwpolyline(points, dxfattribs={"layer": layer_name})
        return

    if decoration.geometry_type == "text":
        insert = decoration.payload["insert"]
        text = msp.add_text(
            str(decoration.payload.get("text", "")),
            dxfattribs={"layer": layer_name, "height": 2.5},
        )
        text.set_placement((float(insert[0]) + sheet_offset_x, float(insert[1])))
        return

    if decoration.geometry_type == "insert":
        insert = decoration.payload["insert"]
        marker = msp.add_text(
            str(decoration.payload.get("block_name", "")),
            dxfattribs={"layer": layer_name, "height": 2.5},
        )
        marker.set_placement((float(insert[0]) + sheet_offset_x, float(insert[1])))


def _add_cut_segment(msp, segment, *, sheet_offset_x: float) -> None:
    assert len(segment) == 2, "cut segment must have start and end points"
    start, end = segment
    msp.add_line(
        (float(start[0]) + sheet_offset_x, float(start[1])),
        (float(end[0]) + sheet_offset_x, float(end[1])),
        dxfattribs={"layer": "SPLIT_CUTS"},
    )


def _add_piece_label(msp, placed: PlacedPiece, label: str, *, sheet_offset_x: float) -> None:
    world = _world_polygon(placed.polygon, placed.placement, sheet_offset_x=sheet_offset_x)
    centroid = world.centroid
    text = msp.add_text(label, dxfattribs={"layer": "SPLIT_LABELS", "height": 5.0})
    text.set_placement((float(centroid.x), float(centroid.y)))
