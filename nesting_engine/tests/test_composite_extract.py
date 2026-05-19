# [REQ-FIT-DXF-002] Composite extract: primary polygons + clipped auxiliary decorations.
from __future__ import annotations

from pathlib import Path

import ezdxf
import pytest
from shapely.geometry import LineString, Point

from nesting_engine.composite_extract import (
    CompositePiece,
    DecorationEntity,
    load_composite_pieces,
)

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
    msp.add_text("MARK", dxfattribs={"layer": GRABADO, "insert": (20, 20)})
    doc.saveas(path)


def test_load_composite_pieces_yields_two_primaries(tmp_path: Path) -> None:
    path = tmp_path / "composite-two-pieces.dxf"
    _write_composite_fixture(path)

    pieces = load_composite_pieces(
        path,
        primary_layer=CORTE,
        auxiliary_layers=[GRABADO],
    )

    assert len(pieces) == 2
    assert all(isinstance(piece, CompositePiece) for piece in pieces)
    assert all(piece.polygon.is_valid and piece.polygon.area > 0 for piece in pieces)


def test_grabado_line_crossing_border_splits_between_two_pieces(tmp_path: Path) -> None:
    path = tmp_path / "composite-split-line.dxf"
    _write_composite_fixture(path)

    pieces = load_composite_pieces(
        path,
        primary_layer=CORTE,
        auxiliary_layers=[GRABADO],
    )

    line_decorations = [
        deco
        for piece in pieces
        for deco in piece.decorations
        if deco.layer_name == GRABADO and deco.geometry_type == "line"
    ]
    assert len(line_decorations) == 2
    lengths = sorted(_line_length(deco) for deco in line_decorations)
    assert lengths[0] == pytest.approx(5.0, abs=0.5)
    assert lengths[1] == pytest.approx(5.0, abs=0.5)


def test_grabado_line_fully_outside_primaries_is_discarded(tmp_path: Path) -> None:
    path = tmp_path / "composite-outside-line.dxf"
    _write_composite_fixture(path)

    pieces = load_composite_pieces(
        path,
        primary_layer=CORTE,
        auxiliary_layers=[GRABADO],
    )

    for piece in pieces:
        for deco in piece.decorations:
            if deco.geometry_type != "line":
                continue
            line = _decoration_line(deco)
            assert line.distance(Point(200, 200)) > 1.0


def test_text_insert_inside_primary_is_kept_whole(tmp_path: Path) -> None:
    path = tmp_path / "composite-text.dxf"
    _write_composite_fixture(path)

    pieces = load_composite_pieces(
        path,
        primary_layer=CORTE,
        auxiliary_layers=[GRABADO],
    )

    text_holders = [
        piece
        for piece in pieces
        if any(d.geometry_type == "text" for d in piece.decorations)
    ]
    assert len(text_holders) == 1
    text = next(d for d in text_holders[0].decorations if d.geometry_type == "text")
    assert text.layer_name == GRABADO
    assert text.payload.get("text") == "MARK"
    assert text_holders[0].polygon.contains(Point(20, 20))


def _line_length(deco: DecorationEntity) -> float:
    return _decoration_line(deco).length


def _decoration_line(deco: DecorationEntity) -> LineString:
    coords = deco.payload["coordinates"]
    return LineString(coords)


def _write_washer_primary_with_hole_mark(path: Path) -> None:
    doc = ezdxf.new("R2010")
    msp = doc.modelspace()
    msp.add_circle(center=(0, 0), radius=50, dxfattribs={"layer": CORTE})
    msp.add_circle(center=(0, 0), radius=20, dxfattribs={"layer": CORTE})
    msp.add_line((5, 0), (15, 0), dxfattribs={"layer": GRABADO})
    doc.saveas(path)


def _write_insert_fixtures(path: Path) -> None:
    doc = ezdxf.new("R2010")
    msp = doc.modelspace()
    msp.add_lwpolyline(
        [(0, 0), (80, 0), (80, 40), (0, 40)],
        close=True,
        dxfattribs={"layer": CORTE},
    )
    block = doc.blocks.new("MARK_BLOCK")
    block.add_line((0, 0), (10, 0), dxfattribs={"layer": "0"})
    msp.add_blockref("MARK_BLOCK", insert=(40, 20), dxfattribs={"layer": GRABADO})
    msp.add_blockref("MARK_BLOCK", insert=(200, 200), dxfattribs={"layer": GRABADO})
    doc.saveas(path)


def _write_circle_clip_fixture(path: Path) -> None:
    doc = ezdxf.new("R2010")
    msp = doc.modelspace()
    msp.add_lwpolyline(
        [(0, 0), (100, 0), (100, 100), (0, 100)],
        close=True,
        dxfattribs={"layer": CORTE},
    )
    msp.add_circle(center=(90, 50), radius=20, dxfattribs={"layer": GRABADO})
    doc.saveas(path)


def test_decoration_inside_primary_hole_associates_to_piece(tmp_path: Path) -> None:
    path = tmp_path / "composite-hole-mark.dxf"
    _write_washer_primary_with_hole_mark(path)

    pieces = load_composite_pieces(
        path,
        primary_layer=CORTE,
        auxiliary_layers=[GRABADO],
        curve_tolerance_mm=0.25,
    )

    assert len(pieces) == 1
    line_decorations = [
        deco for deco in pieces[0].decorations if deco.geometry_type == "line"
    ]
    assert len(line_decorations) == 1
    assert _decoration_line(line_decorations[0]).length == pytest.approx(10.0, abs=0.5)


def test_insert_associates_when_insert_point_inside_primary(tmp_path: Path) -> None:
    path = tmp_path / "composite-insert.dxf"
    _write_insert_fixtures(path)

    pieces = load_composite_pieces(
        path,
        primary_layer=CORTE,
        auxiliary_layers=[GRABADO],
    )

    assert len(pieces) == 1
    insert_decorations = [
        deco for deco in pieces[0].decorations if deco.geometry_type == "insert"
    ]
    assert len(insert_decorations) == 1
    assert insert_decorations[0].payload["block_name"] == "MARK_BLOCK"
    assert insert_decorations[0].payload["insert"] == pytest.approx([40.0, 20.0])


def test_circle_auxiliary_clips_to_arc_inside_primary(tmp_path: Path) -> None:
    path = tmp_path / "composite-circle-clip.dxf"
    _write_circle_clip_fixture(path)

    pieces = load_composite_pieces(
        path,
        primary_layer=CORTE,
        auxiliary_layers=[GRABADO],
        curve_tolerance_mm=0.25,
    )

    assert len(pieces) == 1
    arc_decorations = [
        deco
        for deco in pieces[0].decorations
        if deco.geometry_type in {"arc", "line", "circle"}
    ]
    assert len(arc_decorations) >= 1
    total_length = sum(
        _decoration_line(deco).length
        for deco in arc_decorations
        if deco.geometry_type in {"arc", "line"}
    )
    full_circumference = 2 * 3.14159265 * 20
    assert total_length < full_circumference * 0.75
    assert total_length > 5.0
