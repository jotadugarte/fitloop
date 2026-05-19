# [REQ-FIT-DXF-002] Extract composite pieces: primary polygons + auxiliary decorations.
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import ezdxf
from ezdxf.entities import Line, MText, Text
from shapely.geometry import LineString, Point, Polygon

from nesting_engine.extract import _line_segment, extract_closed_contours

_MAX_ENTITIES = 100_000
_MIN_CLIP_LENGTH_MM = 0.01


@dataclass
class DecorationEntity:
    layer_name: str
    geometry_type: str
    payload: dict


@dataclass
class CompositePiece:
    polygon: Polygon
    decorations: list[DecorationEntity] = field(default_factory=list)
    piece_index: int = 0


def load_composite_pieces(
    dxf_path: Path | str,
    primary_layer: str,
    auxiliary_layers: list[str],
    *,
    curve_tolerance_mm: float = 0.1,
    warnings: list[str] | None = None,
) -> list[CompositePiece]:
    assert primary_layer and primary_layer.strip(), "primary_layer is required"
    assert auxiliary_layers is not None, "auxiliary_layers is required"
    assert curve_tolerance_mm > 0, "curve_tolerance_mm must be positive"

    path = Path(dxf_path)
    assert path.is_file(), f"DXF file not found: {path}"

    report: list[str] = warnings if warnings is not None else []
    aux_layers = {name for name in auxiliary_layers if name}

    primaries = extract_closed_contours(
        path,
        primary_layer,
        curve_tolerance_mm=curve_tolerance_mm,
        warnings=report,
    )
    pieces = [
        CompositePiece(polygon=polygon, piece_index=index)
        for index, polygon in enumerate(primaries)
    ]

    if not aux_layers or not pieces:
        return pieces

    doc = ezdxf.readfile(path)
    scanned = 0
    for entity in doc.modelspace():
        scanned += 1
        assert scanned <= _MAX_ENTITIES, "DXF entity limit exceeded"
        layer_name = entity.dxf.layer
        if layer_name not in aux_layers:
            continue

        if isinstance(entity, Line):
            _attach_line_decoration(entity, layer_name, pieces)
        elif isinstance(entity, (Text, MText)):
            _attach_text_decoration(entity, layer_name, pieces)

    return pieces


def _attach_line_decoration(entity: Line, layer_name: str, pieces: list[CompositePiece]) -> None:
    segment = _line_segment(entity)
    if segment[0] == segment[1]:
        return
    line = LineString(segment)

    for piece in pieces:
        clipped = piece.polygon.intersection(line)
        for part in _line_parts(clipped):
            piece.decorations.append(
                DecorationEntity(
                    layer_name=layer_name,
                    geometry_type="line",
                    payload={"coordinates": list(part.coords)},
                )
            )


def _attach_text_decoration(entity: Text | MText, layer_name: str, pieces: list[CompositePiece]) -> None:
    insert = entity.dxf.insert
    point = Point(float(insert.x), float(insert.y))
    text_value = getattr(entity.dxf, "text", None) or getattr(entity, "text", "")

    for piece in pieces:
        if not _point_in_primary_piece(point, piece.polygon):
            continue
        piece.decorations.append(
            DecorationEntity(
                layer_name=layer_name,
                geometry_type="text",
                payload={
                    "text": str(text_value),
                    "insert": [float(insert.x), float(insert.y)],
                },
            )
        )
        return


def _point_in_primary_piece(point: Point, polygon: Polygon) -> bool:
    if not polygon.contains(point):
        return False
    for hole in polygon.interiors:
        if Polygon(hole).contains(point):
            return True
    return True


def _line_parts(geometry: object) -> list[LineString]:
    if geometry.is_empty:
        return []
    if isinstance(geometry, LineString):
        return [geometry] if geometry.length >= _MIN_CLIP_LENGTH_MM else []
    if geometry.geom_type == "MultiLineString":
        return [
            part
            for part in geometry.geoms
            if isinstance(part, LineString) and part.length >= _MIN_CLIP_LENGTH_MM
        ]
    return []
