# [REQ-FIT-DXF-002] Extract composite pieces: primary polygons + auxiliary decorations.
#
# Module layout:
# - load_composite_pieces: primary contours + auxiliary entity scan
# - _attach_* helpers: clip decorations to piece polygons
# - partition_decorations: assign mother decorations to split children
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import ezdxf
from ezdxf.entities import Circle, Insert, Line, LWPolyline, MText, Polyline, Text
from ezdxf.path import make_path
from shapely.geometry import LineString, Point, Polygon

from nesting_engine.extract import (
    _circle_polygon,
    _line_segment,
    _open_curve_segments,
    _open_polyline_segments,
    extract_closed_contours,
)

_MAX_ENTITIES = 100_000
_DEFAULT_MAX_BLOCK_DEPTH = 8
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
    primary_layer_name: str = ""


def load_composite_pieces(
    dxf_path: Path | str,
    primary_layer: str,
    auxiliary_layers: list[str],
    *,
    curve_tolerance_mm: float = 0.1,
    max_block_depth: int = _DEFAULT_MAX_BLOCK_DEPTH,
    warnings: list[str] | None = None,
    auto_close_gaps: bool = False,
) -> list[CompositePiece]:
    assert primary_layer and primary_layer.strip(), "primary_layer is required"
    assert auxiliary_layers is not None, "auxiliary_layers is required"
    assert curve_tolerance_mm > 0, "curve_tolerance_mm must be positive"
    assert max_block_depth >= 1, "max_block_depth must be at least 1"

    path = Path(dxf_path)
    assert path.is_file(), f"DXF file not found: {path}"

    report: list[str] = warnings if warnings is not None else []
    aux_layers = {name for name in auxiliary_layers if name}

    primaries = extract_closed_contours(
        path,
        primary_layer,
        curve_tolerance_mm=curve_tolerance_mm,
        warnings=report,
        auto_close_gaps=auto_close_gaps,
    )
    pieces = [
        CompositePiece(
            polygon=polygon,
            piece_index=index,
            primary_layer_name=primary_layer,
        )
        for index, polygon in enumerate(primaries)
    ]

    if not aux_layers or not pieces:
        return pieces

    doc = ezdxf.readfile(path)
    scanned = 0
    for entity in doc.modelspace():
        scanned += 1
        assert scanned <= _MAX_ENTITIES, "DXF entity limit exceeded"
        if entity.dxf.layer not in aux_layers:
            continue
        _attach_auxiliary_entity(
            entity,
            entity.dxf.layer,
            pieces,
            curve_tolerance_mm=curve_tolerance_mm,
        )

    return pieces


def _attach_auxiliary_entity(
    entity: object,
    layer_name: str,
    pieces: list[CompositePiece],
    *,
    curve_tolerance_mm: float,
) -> None:
    if isinstance(entity, Line):
        _attach_line_decoration(entity, layer_name, pieces)
    elif isinstance(entity, Circle):
        _attach_circle_decoration(entity, layer_name, pieces, curve_tolerance_mm=curve_tolerance_mm)
    elif isinstance(entity, Insert):
        _attach_insert_decoration(entity, layer_name, pieces)
    elif isinstance(entity, (Text, MText)):
        _attach_text_decoration(entity, layer_name, pieces)
    elif hasattr(entity, "dxftype") and entity.dxftype() == "ARC":
        _attach_curve_segments_decoration(entity, layer_name, pieces, curve_tolerance_mm=curve_tolerance_mm)
    elif isinstance(entity, (LWPolyline, Polyline)):
        _attach_polyline_decoration(entity, layer_name, pieces, curve_tolerance_mm=curve_tolerance_mm)


def _attach_line_decoration(entity: Line, layer_name: str, pieces: list[CompositePiece]) -> None:
    segment = _line_segment(entity)
    if segment[0] == segment[1]:
        return
    _attach_linestring_to_pieces(LineString(segment), layer_name, pieces)


def _attach_circle_decoration(
    entity: Circle,
    layer_name: str,
    pieces: list[CompositePiece],
    *,
    curve_tolerance_mm: float,
) -> None:
    circle_polygon = _circle_polygon(entity, curve_tolerance_mm=curve_tolerance_mm)
    if circle_polygon is None or circle_polygon.is_empty:
        return
    ring = LineString(circle_polygon.exterior.coords)
    _attach_linestring_to_pieces(ring, layer_name, pieces)


def _attach_curve_segments_decoration(
    entity: object,
    layer_name: str,
    pieces: list[CompositePiece],
    *,
    curve_tolerance_mm: float,
) -> None:
    for segment in _open_curve_segments(entity, curve_tolerance_mm=curve_tolerance_mm):
        if segment[0] == segment[1]:
            continue
        _attach_linestring_to_pieces(LineString(segment), layer_name, pieces)


def _attach_polyline_decoration(
    entity: LWPolyline | Polyline,
    layer_name: str,
    pieces: list[CompositePiece],
    *,
    curve_tolerance_mm: float,
) -> None:
    for segment in _open_polyline_segments(entity, curve_tolerance_mm=curve_tolerance_mm):
        if segment[0] == segment[1]:
            continue
        _attach_linestring_to_pieces(LineString(segment), layer_name, pieces)

    if isinstance(entity, LWPolyline) and entity.closed:
        _attach_closed_path_decoration(entity, layer_name, pieces, curve_tolerance_mm=curve_tolerance_mm)
    if isinstance(entity, Polyline) and entity.is_closed:
        _attach_closed_path_decoration(entity, layer_name, pieces, curve_tolerance_mm=curve_tolerance_mm)


def _attach_closed_path_decoration(
    entity: object,
    layer_name: str,
    pieces: list[CompositePiece],
    *,
    curve_tolerance_mm: float,
) -> None:
    path = make_path(entity)
    points = [(float(v.x), float(v.y)) for v in path.flattening(curve_tolerance_mm)]
    if len(points) < 2:
        return
    ring = LineString(points + [points[0]])
    _attach_linestring_to_pieces(ring, layer_name, pieces)


def _attach_insert_decoration(entity: Insert, layer_name: str, pieces: list[CompositePiece]) -> None:
    insert = entity.dxf.insert
    point = Point(float(insert.x), float(insert.y))

    for piece in pieces:
        if not _point_associates_with_piece(point, piece.polygon):
            continue
        piece.decorations.append(
            DecorationEntity(
                layer_name=layer_name,
                geometry_type="insert",
                payload={
                    "block_name": entity.dxf.name,
                    "insert": [float(insert.x), float(insert.y)],
                },
            )
        )
        return


def _attach_text_decoration(entity: Text | MText, layer_name: str, pieces: list[CompositePiece]) -> None:
    insert = entity.dxf.insert
    point = Point(float(insert.x), float(insert.y))
    text_value = getattr(entity.dxf, "text", None) or getattr(entity, "text", "")

    for piece in pieces:
        if not _point_associates_with_piece(point, piece.polygon):
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


def _attach_linestring_to_pieces(
    line: LineString,
    layer_name: str,
    pieces: list[CompositePiece],
) -> None:
    if line.is_empty or line.length < _MIN_CLIP_LENGTH_MM:
        return

    for piece in pieces:
        clipped = _append_clipped_line_parts(line, layer_name, piece)
        if clipped:
            continue
        if _line_in_hole_interior(line, piece.polygon):
            _append_line_decoration(piece, layer_name, line)


def _append_clipped_line_parts(
    line: LineString,
    layer_name: str,
    piece: CompositePiece,
) -> bool:
    parts = _line_parts(piece.polygon.intersection(line))
    if not parts:
        return False
    for part in parts:
        _append_line_decoration(piece, layer_name, part)
    return True


def _append_line_decoration(
    piece: CompositePiece,
    layer_name: str,
    line: LineString,
) -> None:
    piece.decorations.append(
        DecorationEntity(
            layer_name=layer_name,
            geometry_type="line",
            payload={"coordinates": list(line.coords)},
        )
    )


def _point_associates_with_piece(point: Point, polygon: Polygon) -> bool:
    if polygon.contains(point):
        return True
    for interior in polygon.interiors:
        if Polygon(interior).contains(point):
            return True
    return False


def _line_in_hole_interior(line: LineString, polygon: Polygon) -> bool:
    if line.length < _MIN_CLIP_LENGTH_MM:
        return False
    midpoint = line.interpolate(0.5, normalized=True)
    for interior in polygon.interiors:
        if Polygon(interior).contains(midpoint):
            return True
    return False


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


def partition_decorations(
    mother: CompositePiece,
    split_children: list[object],
    cut_segments: list[tuple[tuple[float, float], tuple[float, float]]] | None = None,
) -> list[CompositePiece]:
    """[REQ-FIT-DXF-002] [REQ-FIT-SPLIT-001] Assign mother decorations to split child polygons."""
    assert mother is not None, "mother is required"
    assert split_children is not None, "split_children is required"
    _ = cut_segments

    children = [
        CompositePiece(
            polygon=child.polygon,
            decorations=[],
            primary_layer_name=mother.primary_layer_name,
        )
        for child in split_children
    ]
    for decoration in mother.decorations:
        _partition_decoration(decoration, children)
    return children


def _partition_decoration(
    decoration: DecorationEntity,
    children: list[CompositePiece],
) -> None:
    if decoration.geometry_type == "line":
        _partition_line_decoration(decoration, children)
        return
    if decoration.geometry_type in ("text", "insert"):
        _partition_point_decoration(decoration, children)


def _partition_line_decoration(
    decoration: DecorationEntity,
    children: list[CompositePiece],
) -> None:
    coordinates = decoration.payload.get("coordinates") or []
    if len(coordinates) < 2:
        return

    line = LineString(coordinates)
    if line.is_empty or line.length < _MIN_CLIP_LENGTH_MM:
        return

    for child in children:
        clipped = _append_clipped_line_parts(line, decoration.layer_name, child)
        if clipped:
            continue
        if _line_in_hole_interior(line, child.polygon):
            _append_line_decoration(child, decoration.layer_name, line)


def _partition_point_decoration(
    decoration: DecorationEntity,
    children: list[CompositePiece],
) -> None:
    insert = decoration.payload.get("insert")
    if not insert or len(insert) < 2:
        return

    point = Point(float(insert[0]), float(insert[1]))
    for child in children:
        if not _point_associates_with_piece(point, child.polygon):
            continue
        child.decorations.append(_copy_decoration(decoration))
        return


def _copy_decoration(decoration: DecorationEntity) -> DecorationEntity:
    return DecorationEntity(
        layer_name=decoration.layer_name,
        geometry_type=decoration.geometry_type,
        payload=dict(decoration.payload),
    )
