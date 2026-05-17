# [REQ-FIT-NEST-002] Nested DXF must place pieces on sheets regardless of source DXF coordinates.
from __future__ import annotations

from pathlib import Path

import ezdxf
from shapely.affinity import rotate, translate
from shapely.geometry import box

from nesting_engine.dxf_output import write_nested_dxf
from nesting_engine.nest_bin import SheetStockSpec, nest_multi_bin


def _piece_bounds_on_sheet(sheet, placed):
    rotated = rotate(placed.polygon, placed.placement.rotation_deg, origin="centroid")
    return translate(
        rotated,
        xoff=placed.placement.x + sheet.offset_x_mm,
        yoff=placed.placement.y,
    ).bounds


def test_world_offset_piece_lands_inside_sheet_outline(tmp_path: Path) -> None:
    piece = box(5000.0, 3000.0, 5040.0, 3030.0)
    stocks = [SheetStockSpec(width_mm=500.0, height_mm=400.0, quantity=1, sort_order=0)]
    margin = 5.0

    result = nest_multi_bin(
        [piece],
        stocks,
        margin_mm=margin,
        kerf_mm=0.0,
        sheet_gap_mm=15.0,
    )

    assert result.orphans == []
    assert len(result.sheets) == 1

    sheet = result.sheets[0]
    placed = sheet.pieces[0]
    minx, miny, maxx, maxy = _piece_bounds_on_sheet(sheet, placed)

    assert minx >= sheet.offset_x_mm + margin - 0.01
    assert miny >= margin - 0.01
    assert maxx <= sheet.offset_x_mm + sheet.width_mm - margin + 0.01
    assert maxy <= sheet.height_mm - margin + 0.01

    out_path = tmp_path / "nested.dxf"
    write_nested_dxf(out_path, result.sheets)

    doc = ezdxf.readfile(out_path)
    piece_polys = [
        entity
        for entity in doc.modelspace()
        if entity.dxftype() == "LWPOLYLINE" and entity.dxf.layer == "PIECES"
    ]
    assert len(piece_polys) == 1
    xs = [point[0] for point in piece_polys[0].get_points()]
    ys = [point[1] for point in piece_polys[0].get_points()]
    assert min(xs) >= sheet.offset_x_mm + margin - 0.01
    assert min(ys) >= margin - 0.01
    assert max(xs) <= sheet.offset_x_mm + sheet.width_mm - margin + 0.01
    assert max(ys) <= sheet.height_mm - margin + 0.01
