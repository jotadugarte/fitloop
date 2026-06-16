# [REQ-FIT-NEST-002] Global layout objective for multi-bin nesting comparisons.
from __future__ import annotations

from dataclasses import dataclass

from shapely.geometry import Polygon

from nesting_engine.nest_placement import placed_polygon, score_sheet_layout
from nesting_engine.nest_types import NestedSheet, PlacedPiece
from nesting_engine.piece_loader import piece_polygon


@dataclass(frozen=True)
class SheetScore:
    free_area_mm2: float
    footprint_mm2: float
    layout_maxy: float
    min_y: float
    min_x: float
    waste_mm2: float


@dataclass(frozen=True)
class LayoutScore:
    sheet_count: int
    total_waste_mm2: float
    total_footprint_mm2: float
    max_layout_maxy: float
    min_min_y: float
    min_min_x: float
    total_free_area_mm2: float
    sheets: tuple[SheetScore, ...]


def compare_layouts(left: LayoutScore, right: LayoutScore) -> int:
    """Return negative when left is strictly better than right, positive when worse, 0 when tied."""
    left_key = _layout_rank_key(left)
    right_key = _layout_rank_key(right)
    if left_key < right_key:
        return -1
    if left_key > right_key:
        return 1
    return 0


def layout_better_than(left: LayoutScore, right: LayoutScore) -> bool:
    return compare_layouts(left, right) < 0


def _layout_rank_key(score: LayoutScore) -> tuple:
    return (
        score.sheet_count,
        score.total_waste_mm2,
        score.total_footprint_mm2,
        score.max_layout_maxy,
        -score.total_free_area_mm2,
        score.min_min_y,
        score.min_min_x,
    )


def _sheet_placed_polygons(
    sheet: NestedSheet,
    pieces: list[Polygon],
) -> list[Polygon]:
    worlds: list[Polygon] = []
    for row in sheet.pieces:
        worlds.append(placed_polygon(pieces[row.piece_index], row.placement))
    return worlds


def score_sheet(
    sheet: NestedSheet,
    pieces: list[Polygon],
    *,
    margin_mm: float,
) -> SheetScore:
    placed = _sheet_placed_polygons(sheet, pieces)
    free_area, footprint = score_sheet_layout(
        sheet.width_mm,
        sheet.height_mm,
        margin_mm,
        placed,
    )
    if placed:
        minx = min(poly.bounds[0] for poly in placed)
        miny = min(poly.bounds[1] for poly in placed)
        maxy = max(poly.bounds[3] for poly in placed)
    else:
        minx = margin_mm
        miny = margin_mm
        maxy = margin_mm

    usable_w = sheet.width_mm - 2 * margin_mm
    usable_h = sheet.height_mm - 2 * margin_mm
    usable_area = usable_w * usable_h
    material_area = sum(piece_polygon(poly).area for poly in placed)
    waste = max(0.0, usable_area - material_area)

    return SheetScore(
        free_area_mm2=free_area,
        footprint_mm2=footprint,
        layout_maxy=maxy,
        min_y=miny,
        min_x=minx,
        waste_mm2=waste,
    )


def score_nested_layout(
    sheets: list[NestedSheet],
    pieces: list[Polygon],
    *,
    margin_mm: float,
) -> LayoutScore:
    sheet_scores = tuple(
        score_sheet(sheet, pieces, margin_mm=margin_mm) for sheet in sheets
    )
    if not sheet_scores:
        return LayoutScore(
            sheet_count=0,
            total_waste_mm2=0.0,
            total_footprint_mm2=0.0,
            max_layout_maxy=0.0,
            min_min_y=0.0,
            min_min_x=0.0,
            total_free_area_mm2=0.0,
            sheets=(),
        )

    return LayoutScore(
        sheet_count=len(sheet_scores),
        total_waste_mm2=sum(row.waste_mm2 for row in sheet_scores),
        total_footprint_mm2=sum(row.footprint_mm2 for row in sheet_scores),
        max_layout_maxy=max(row.layout_maxy for row in sheet_scores),
        min_min_y=min(row.min_y for row in sheet_scores),
        min_min_x=min(row.min_x for row in sheet_scores),
        total_free_area_mm2=sum(row.free_area_mm2 for row in sheet_scores),
        sheets=sheet_scores,
    )


def score_orphan_penalty(orphan_count: int, sheet_area_mm2: float) -> float:
    assert orphan_count >= 0 and sheet_area_mm2 > 0.0
    return float(orphan_count) * sheet_area_mm2


def layout_score_with_orphans(
    sheets: list[NestedSheet],
    pieces: list[Polygon],
    *,
    margin_mm: float,
    orphan_count: int,
    reference_sheet_area_mm2: float,
) -> LayoutScore:
    base = score_nested_layout(sheets, pieces, margin_mm=margin_mm)
    if orphan_count <= 0:
        return base
    penalty = score_orphan_penalty(orphan_count, reference_sheet_area_mm2)
    return LayoutScore(
        sheet_count=base.sheet_count + orphan_count,
        total_waste_mm2=base.total_waste_mm2 + penalty,
        total_footprint_mm2=base.total_footprint_mm2,
        max_layout_maxy=base.max_layout_maxy,
        min_min_y=base.min_min_y,
        min_min_x=base.min_min_x,
        total_free_area_mm2=base.total_free_area_mm2,
        sheets=base.sheets,
    )
