"""Tests for single-piece DXF export."""

from __future__ import annotations

from pathlib import Path

import ezdxf

from nesting_engine.dxf_output import write_piece_dxf

LAYER = "PIECES"


def test_write_piece_dxf_writes_closed_contour(tmp_path: Path) -> None:
    path = tmp_path / "piece.dxf"
    rings = [
        [
            [0.0, 0.0],
            [100.0, 0.0],
            [100.0, 50.0],
            [0.0, 50.0],
        ]
    ]

    write_piece_dxf(path, rings, layer_name=LAYER)

    doc = ezdxf.readfile(path)
    polylines = [
        entity
        for entity in doc.modelspace()
        if entity.dxftype() == "LWPOLYLINE" and entity.dxf.layer == LAYER
    ]
    assert len(polylines) == 1
    assert polylines[0].closed is True


def test_write_piece_dxf_writes_hole(tmp_path: Path) -> None:
    path = tmp_path / "washer.dxf"
    rings = [
        [
            [0.0, 0.0],
            [100.0, 0.0],
            [100.0, 100.0],
            [0.0, 100.0],
        ],
        [
            [30.0, 30.0],
            [70.0, 30.0],
            [70.0, 70.0],
            [30.0, 70.0],
        ],
    ]

    write_piece_dxf(path, rings, layer_name=LAYER)

    doc = ezdxf.readfile(path)
    assert len([e for e in doc.modelspace() if e.dxftype() == "LWPOLYLINE"]) == 2
