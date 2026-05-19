# [REQ-FIT-SPLIT-001] Straight-cut auto-split planner (hole-aware, recursive fit).
from __future__ import annotations

from dataclasses import dataclass

from shapely.geometry import LineString, Polygon, box
from shapely.ops import unary_union

from nesting_engine.nest_types import SheetStockSpec

_EPS = 1e-6
_MAX_PIECES = 32
_MAX_ITERATIONS = 64


@dataclass(frozen=True)
class SplitChild:
    label: str
    polygon: Polygon


@dataclass(frozen=True)
class SplitPlanResult:
    feasible: bool
    reason: str | None
    children: list[SplitChild]
    cut_segments: list[tuple[tuple[float, float], tuple[float, float]]]


def plan_split(
    piece: Polygon,
    sheet_stocks: list[SheetStockSpec],
    *,
    margin_mm: float = 0.0,
) -> SplitPlanResult:
    assert piece is not None and not piece.is_empty, "piece is required"
    assert margin_mm >= 0, "margin_mm must be non-negative"

    max_w, max_h = _largest_usable_bin(sheet_stocks, margin_mm)
    if max_w <= _EPS or max_h <= _EPS:
        return SplitPlanResult(False, "split_not_feasible", [], [])

    polygons, cuts = _partition_to_fit(piece, max_w, max_h)
    if polygons is None:
        return SplitPlanResult(False, "split_not_feasible", [], [])

    labels = _child_labels(len(polygons))
    children = [SplitChild(label=label, polygon=poly) for label, poly in zip(labels, polygons, strict=True)]
    return SplitPlanResult(True, None, children, cuts)


def _largest_usable_bin(
    sheet_stocks: list[SheetStockSpec],
    margin_mm: float,
) -> tuple[float, float]:
    assert sheet_stocks, "sheet_stocks is required"

    max_w = 0.0
    max_h = 0.0
    for stock in sheet_stocks[:_MAX_PIECES]:
        inner_w = stock.width_mm - (2 * margin_mm)
        inner_h = stock.height_mm - (2 * margin_mm)
        max_w = max(max_w, inner_w)
        max_h = max(max_h, inner_h)
    return max_w, max_h


def _partition_to_fit(
    piece: Polygon,
    max_w: float,
    max_h: float,
) -> tuple[list[Polygon], list[tuple[tuple[float, float], tuple[float, float]]]] | tuple[None, None]:
    pieces = [piece]
    cuts: list[tuple[tuple[float, float], tuple[float, float]]] = []

    for _ in range(_MAX_ITERATIONS):
        if all(_fits_bbox(poly, max_w, max_h) for poly in pieces):
            return pieces, cuts
        if len(pieces) >= _MAX_PIECES:
            return None, None

        oversized_index = next(i for i, poly in enumerate(pieces) if not _fits_bbox(poly, max_w, max_h))
        oversized = pieces[oversized_index]
        split = _split_once(oversized, max_w, max_h)
        if split is None:
            return None, None

        new_parts, new_cuts = split
        pieces = pieces[:oversized_index] + new_parts + pieces[oversized_index + 1 :]
        cuts.extend(new_cuts)

    return None, None


def _split_once(
    polygon: Polygon,
    max_w: float,
    max_h: float,
) -> tuple[list[Polygon], list[tuple[tuple[float, float], tuple[float, float]]]] | None:
    minx, miny, maxx, maxy = polygon.bounds
    width = maxx - minx
    height = maxy - miny

    if width > max_w + _EPS and width >= height - _EPS:
        return _split_vertical(polygon, minx, miny, maxx, maxy, max_w)
    if height > max_h + _EPS:
        return _split_horizontal(polygon, minx, miny, maxx, maxy, max_h)
    if width > max_w + _EPS:
        return _split_vertical(polygon, minx, miny, maxx, maxy, max_w)
    return None


def _split_vertical(
    polygon: Polygon,
    minx: float,
    miny: float,
    maxx: float,
    maxy: float,
    max_w: float,
) -> tuple[list[Polygon], list[tuple[tuple[float, float], tuple[float, float]]]] | None:
    cut_x = _vertical_cut_position(polygon, minx, maxx, max_w)
    if cut_x is None or cut_x <= minx + _EPS or cut_x >= maxx - _EPS:
        return None

    left = polygon.intersection(box(minx, miny, cut_x, maxy))
    right = polygon.intersection(box(cut_x, miny, maxx, maxy))
    parts = _valid_parts([left, right])
    if len(parts) != 2:
        return None

    segment = ((cut_x, miny), (cut_x, maxy))
    return parts, [segment]


def _split_horizontal(
    polygon: Polygon,
    minx: float,
    miny: float,
    maxx: float,
    maxy: float,
    max_h: float,
) -> tuple[list[Polygon], list[tuple[tuple[float, float], tuple[float, float]]]] | None:
    cut_y = _horizontal_cut_position(polygon, miny, maxy, max_h)
    if cut_y is None or cut_y <= miny + _EPS or cut_y >= maxy - _EPS:
        return None

    bottom = polygon.intersection(box(minx, miny, maxx, cut_y))
    top = polygon.intersection(box(minx, cut_y, maxx, maxy))
    parts = _valid_parts([bottom, top])
    if len(parts) != 2:
        return None

    segment = ((minx, cut_y), (maxx, cut_y))
    return parts, [segment]


def _vertical_cut_position(polygon: Polygon, minx: float, maxx: float, max_w: float) -> float | None:
    preferred = minx + min(max_w, maxx - minx)
    return _adjust_cut_x(polygon, minx, maxx, preferred)


def _horizontal_cut_position(polygon: Polygon, miny: float, maxy: float, max_h: float) -> float | None:
    preferred = miny + min(max_h, maxy - miny)
    return _adjust_cut_y(polygon, miny, maxy, preferred)


def _adjust_cut_x(polygon: Polygon, minx: float, maxx: float, cut_x: float) -> float | None:
    for interior in polygon.interiors:
        hole_minx, _, hole_maxx, _ = Polygon(interior).bounds
        if hole_minx < cut_x < hole_maxx:
            left_cut = hole_minx
            right_cut = hole_maxx
            left_width = left_cut - minx
            right_width = maxx - right_cut
            if left_width > _EPS and left_width <= maxx - minx:
                return left_cut
            if right_width > _EPS:
                return right_cut
            return None
    return cut_x


def _adjust_cut_y(polygon: Polygon, miny: float, maxy: float, cut_y: float) -> float | None:
    for interior in polygon.interiors:
        _, hole_miny, _, hole_maxy = Polygon(interior).bounds
        if hole_miny < cut_y < hole_maxy:
            bottom_cut = hole_miny
            top_cut = hole_maxy
            bottom_height = bottom_cut - miny
            top_height = maxy - top_cut
            if bottom_height > _EPS:
                return bottom_cut
            if top_height > _EPS:
                return top_cut
            return None
    return cut_y


def _valid_parts(parts: list[Polygon]) -> list[Polygon]:
    valid: list[Polygon] = []
    for part in parts:
        cleaned = _as_single_polygon(part)
        if cleaned is not None and cleaned.area > _EPS:
            valid.append(cleaned)
    return valid


def _as_single_polygon(geometry) -> Polygon | None:
    if geometry.is_empty:
        return None
    if isinstance(geometry, Polygon):
        return geometry
    if geometry.geom_type == "MultiPolygon":
        largest = max(geometry.geoms, key=lambda geom: geom.area)
        return largest if largest.area > _EPS else None
    if geometry.geom_type == "GeometryCollection":
        polys = [geom for geom in geometry.geoms if isinstance(geom, Polygon) and geom.area > _EPS]
        if not polys:
            return None
        return max(polys, key=lambda geom: geom.area)
    return None


def _fits_bbox(polygon: Polygon, max_w: float, max_h: float) -> bool:
    minx, miny, maxx, maxy = polygon.bounds
    return (maxx - minx) <= max_w + _EPS and (maxy - miny) <= max_h + _EPS


def _child_labels(count: int) -> list[str]:
    assert 1 <= count <= _MAX_PIECES, "invalid child count"
    alphabet = "abcdefghijklmnopqrstuvwxyz"
    labels: list[str] = []
    for index in range(count):
        if index < len(alphabet):
            labels.append(alphabet[index])
        else:
            labels.append(f"{alphabet[index % len(alphabet)]}{index // len(alphabet)}")
    return labels
