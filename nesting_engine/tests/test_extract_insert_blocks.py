# [REQ-FIT-EXT-002] INSERT on layer, nested blocks, missing block warnings, curve tolerance.
from __future__ import annotations

from pathlib import Path

import ezdxf

from nesting_engine.extract import extract_closed_contours

LAYER = "PIECES"


def _save(doc: ezdxf.document.Drawing, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    doc.saveas(path)


def test_insert_on_selected_layer_yields_one_piece_without_modelspace_contour(tmp_path: Path) -> None:
    path = tmp_path / "insert_piece.dxf"
    doc = ezdxf.new("R2010")
    block = doc.blocks.new("PIECE_BLOCK")
    block.add_lwpolyline(
        [(0, 0), (80, 0), (80, 40), (0, 40)],
        close=True,
        dxfattribs={"layer": "0"},
    )
    doc.modelspace().add_blockref("PIECE_BLOCK", insert=(10, 5), dxfattribs={"layer": LAYER})
    _save(doc, path)

    warnings: list[str] = []
    contours = extract_closed_contours(path, layer_name=LAYER, warnings=warnings)

    assert len(contours) == 1
    assert contours[0].area > 0
    assert warnings == []
    assert not any(entity.dxf.layer == LAYER and entity.dxftype() == "LWPOLYLINE" for entity in doc.modelspace())


def test_missing_block_definition_emits_warning(tmp_path: Path) -> None:
    path = tmp_path / "missing_block.dxf"
    doc = ezdxf.new("R2010")
    doc.modelspace().add_blockref("GHOST_BLOCK", insert=(0, 0), dxfattribs={"layer": LAYER})
    _save(doc, path)

    warnings: list[str] = []
    contours = extract_closed_contours(path, layer_name=LAYER, warnings=warnings)

    assert contours == []
    assert any("GHOST_BLOCK" in message for message in warnings)


def test_nested_blocks_within_depth_limit(tmp_path: Path) -> None:
    path = tmp_path / "nested_ok.dxf"
    doc = ezdxf.new("R2010")
    inner = doc.blocks.new("INNER")
    inner.add_lwpolyline([(0, 0), (30, 0), (30, 20), (0, 20)], close=True)
    outer = doc.blocks.new("OUTER")
    outer.add_blockref("INNER", insert=(5, 5))
    doc.modelspace().add_blockref("OUTER", insert=(0, 0), dxfattribs={"layer": LAYER})
    _save(doc, path)

    warnings: list[str] = []
    contours = extract_closed_contours(path, layer_name=LAYER, max_block_depth=8, warnings=warnings)

    assert len(contours) == 1
    assert warnings == []


def test_nested_blocks_beyond_depth_limit_emit_warning(tmp_path: Path) -> None:
    path = tmp_path / "nested_deep.dxf"
    doc = ezdxf.new("R2010")
    names = [f"LEVEL_{index}" for index in range(10)]
    leaf = doc.blocks.new(names[-1])
    leaf.add_lwpolyline([(0, 0), (20, 0), (20, 10), (0, 10)], close=True)

    for index in range(len(names) - 2, -1, -1):
        block = doc.blocks.new(names[index])
        block.add_blockref(names[index + 1], insert=(1, 1))

    doc.modelspace().add_blockref(names[0], insert=(0, 0), dxfattribs={"layer": LAYER})
    _save(doc, path)

    warnings: list[str] = []
    contours = extract_closed_contours(path, layer_name=LAYER, max_block_depth=8, warnings=warnings)

    assert contours == []
    assert any("depth exceeded" in message.lower() for message in warnings)


def test_circle_tessellation_respects_curve_tolerance(tmp_path: Path) -> None:
    path = tmp_path / "circle_tol.dxf"
    doc = ezdxf.new("R2010")
    doc.modelspace().add_circle(center=(50, 50), radius=25, dxfattribs={"layer": LAYER})
    _save(doc, path)

    coarse = extract_closed_contours(path, layer_name=LAYER, curve_tolerance_mm=2.0)
    fine = extract_closed_contours(path, layer_name=LAYER, curve_tolerance_mm=0.05)

    assert len(coarse) == 1
    assert len(fine) == 1
    assert len(fine[0].exterior.coords) > len(coarse[0].exterior.coords)
