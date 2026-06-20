"""Emit sorted DXF layer catalog (name + color) from one or more files (JSON to stdout)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import ezdxf
from ezdxf import colors


import math
from typing import TYPE_CHECKING

from ezdxf.path import make_path
from shapely.geometry import LineString, Polygon

if TYPE_CHECKING:
    from nesting_engine.composite_extract import CompositePiece

_GAP_ENDPOINT_TOLERANCE_MM = 1.0
_BOUNDARY_BAND_FACTOR = 2.0
_INTERIOR_COVERAGE_MIN = 0.85


def layer_color_hex(layer) -> str:
    aci = layer.dxf.color
    if aci in (0, 256):
        aci = 7
    red, green, blue = colors.aci2rgb(aci)
    return f"#{red:02x}{green:02x}{blue:02x}"


def find_layer_gaps(doc: ezdxf.document.Drawing, layer_name: str, curve_tolerance_mm: float = 0.25) -> list[dict[str, object]]:
    """
    Return open-end gaps on explicitly open LWPOLYLINE/POLYLINE entities.

    [REQ-FIT-DXF-002] Report per-entity gaps even when other closed pieces exist on
    the same layer (e.g. 015.dxf: three closed pieces plus one auth-range open cut).
    """
    gaps = []
    for entity in doc.modelspace():
        if not hasattr(entity, "dxf") or not entity.dxf.hasattr("layer"):
            continue
        if entity.dxf.layer != layer_name:
            continue
        if entity.dxftype() not in ("LWPOLYLINE", "POLYLINE"):
            continue

        if entity.dxftype() == "LWPOLYLINE":
            is_closed = entity.closed
        else:
            is_closed = entity.is_closed

        if is_closed:
            continue

        try:
            path = make_path(entity)
            points = [(float(v.x), float(v.y)) for v in path.flattening(curve_tolerance_mm)]
        except Exception:
            continue

        if len(points) < 2:
            continue

        x0, y0 = points[0]
        x1, y1 = points[-1]
        dist = math.hypot(x1 - x0, y1 - y0)

        if dist > curve_tolerance_mm:
            gaps.append({
                "distance_mm": round(dist, 4),
                "start": [round(x0, 4), round(y0, 4)],
                "end": [round(x1, 4), round(y1, 4)]
            })
    return gaps


def _polyline_endpoints_match_gap(
    points: list[tuple[float, float]],
    gap_start: list[float],
    gap_end: list[float],
) -> bool:
    if len(points) < 2:
        return False

    def near(left: tuple[float, float], right: list[float]) -> bool:
        return (
            abs(left[0] - float(right[0])) <= _GAP_ENDPOINT_TOLERANCE_MM
            and abs(left[1] - float(right[1])) <= _GAP_ENDPOINT_TOLERANCE_MM
        )

    start = (float(points[0][0]), float(points[0][1]))
    end = (float(points[-1][0]), float(points[-1][1]))
    return (
        near(start, gap_start) and near(end, gap_end)
    ) or (
        near(start, gap_end) and near(end, gap_start)
    )


def _open_polyline_points_for_gap(
    doc: ezdxf.document.Drawing,
    layer_name: str,
    gap: dict[str, object],
    *,
    curve_tolerance_mm: float,
) -> list[tuple[float, float]] | None:
    for entity in doc.modelspace():
        if not hasattr(entity, "dxf") or not entity.dxf.hasattr("layer"):
            continue
        if entity.dxf.layer != layer_name:
            continue
        if entity.dxftype() not in ("LWPOLYLINE", "POLYLINE"):
            continue

        if entity.dxftype() == "LWPOLYLINE":
            is_closed = entity.closed
        else:
            is_closed = entity.is_closed

        if is_closed:
            continue

        try:
            path = make_path(entity)
            points = [(float(v.x), float(v.y)) for v in path.flattening(curve_tolerance_mm)]
        except Exception:
            continue

        if len(points) < 2:
            continue

        if _polyline_endpoints_match_gap(points, gap["start"], gap["end"]):
            return points

    return None


def _gap_polyline_resolved_by_piece(
    polyline_points: list[tuple[float, float]],
    piece_polygon: Polygon,
    *,
    curve_tolerance_mm: float,
) -> bool:
    """[REQ-FIT-DXF-002] True when an open entity gap is already absorbed into a closed extract."""
    line = LineString(polyline_points)
    if line.is_empty:
        return False

    boundary_band = piece_polygon.boundary.buffer(curve_tolerance_mm * _BOUNDARY_BAND_FACTOR)
    remainder = line.difference(boundary_band)
    if remainder.length <= curve_tolerance_mm:
        return True

    solid = Polygon(piece_polygon.exterior)
    inside = line.intersection(solid.buffer(curve_tolerance_mm))
    if line.length > curve_tolerance_mm and inside.length / line.length >= _INTERIOR_COVERAGE_MIN:
        return True

    return False


def filter_gaps_resolved_by_extraction(
    gaps: list[dict[str, object]],
    doc: ezdxf.document.Drawing,
    layer_name: str,
    pieces: list[CompositePiece],
    *,
    curve_tolerance_mm: float,
) -> list[dict[str, object]]:
    """[REQ-FIT-DXF-002] Drop raw-entity gaps subsumed by composite extraction (e.g. 008.dxf)."""
    if not gaps or not pieces:
        return gaps

    kept: list[dict[str, object]] = []
    for gap in gaps:
        polyline_points = _open_polyline_points_for_gap(
            doc,
            layer_name,
            gap,
            curve_tolerance_mm=curve_tolerance_mm,
        )
        if polyline_points is None:
            kept.append(gap)
            continue

        resolved = any(
            _gap_polyline_resolved_by_piece(
                polyline_points,
                piece.polygon,
                curve_tolerance_mm=curve_tolerance_mm,
            )
            for piece in pieces
        )
        if not resolved:
            kept.append(gap)

    return kept


GAP_SILENT_MM = 2.0
GAP_AUTH_MAX_MM = 15.0


def gap_needs_authorization(distance_mm: float) -> bool:
    """True for gaps in the 2–15 mm range (matches diagnose_dxf auth classification)."""
    value = float(distance_mm)
    return GAP_SILENT_MM < value <= GAP_AUTH_MAX_MM


def gap_is_ignored(distance_mm: float) -> bool:
    return float(distance_mm) > GAP_AUTH_MAX_MM


def layer_catalog_from_file(path: Path) -> dict[str, str]:
    doc = ezdxf.readfile(path)
    catalog: dict[str, str] = {}
    for layer in doc.layers:
        catalog[layer.dxf.name] = layer_color_hex(layer)
    for entity in doc.modelspace():
        if entity.dxf.hasattr("layer"):
            name = entity.dxf.layer
            if name in catalog:
                continue
            layer = doc.layers.get(name) if name in doc.layers else None
            catalog[name] = layer_color_hex(layer) if layer is not None else "#808080"
    return catalog


def layer_gaps_for_file(
    path: Path,
    layer_name: str,
    *,
    curve_tolerance_mm: float = 0.25,
) -> list[dict[str, object]]:
    """[REQ-FIT-DXF-002] Closed-contour gap scan for a single cut layer on demand."""
    doc = ezdxf.readfile(path)
    return find_layer_gaps(doc, layer_name, curve_tolerance_mm=curve_tolerance_mm)


def layer_gaps_for_composite_file(
    path: Path,
    primary_layer: str,
    auxiliary_layers: list[str] | None = None,
    *,
    curve_tolerance_mm: float = 0.25,
    auto_close_gaps: bool = False,
) -> list[dict[str, object]]:
    """[REQ-FIT-DXF-002] Gap scan for primary layer after composite extraction filter."""
    from nesting_engine.composite_extract import load_composite_pieces

    resolved_path = Path(path)
    doc = ezdxf.readfile(resolved_path)
    pieces = load_composite_pieces(
        resolved_path,
        primary_layer,
        auxiliary_layers or [],
        curve_tolerance_mm=curve_tolerance_mm,
        auto_close_gaps=auto_close_gaps,
    )
    gaps = find_layer_gaps(doc, primary_layer, curve_tolerance_mm=curve_tolerance_mm)
    return filter_gaps_resolved_by_extraction(
        gaps,
        doc,
        primary_layer,
        pieces,
        curve_tolerance_mm=curve_tolerance_mm,
    )


def layer_catalog(paths: list[Path]) -> list[dict[str, object]]:
    """Layer names and colors only; gap scans run on demand for primary/legacy cut layers."""
    merged: dict[str, dict[str, object]] = {}
    for path in paths:
        for name, color in layer_catalog_from_file(path).items():
            if name not in merged:
                merged[name] = {"color": color, "gaps": []}
    return [{"name": name, "color": info["color"], "gaps": info["gaps"]} for name, info in sorted(merged.items())]


def union_layer_names(paths: list[Path]) -> list[str]:
    return [entry["name"] for entry in layer_catalog(paths)]


def _parse_composite_gaps_argv(argv: list[str]) -> tuple[str, Path, list[str], bool]:
    assert len(argv) >= 3 and argv[0] == "--gaps-for-composite", "composite gaps argv"
    primary_layer = argv[1]
    path = Path(argv[2])
    auxiliary_layers: list[str] = []
    auto_close_gaps = False
    index = 3
    while index < len(argv):
        token = argv[index]
        if token == "--aux":
            index += 1
            assert index < len(argv), "--aux requires a value"
            auxiliary_layers = [name for name in argv[index].split(",") if name]
        elif token == "--auto-close":
            auto_close_gaps = True
        else:
            raise SystemExit(f"unknown flag: {token}")
        index += 1
    return primary_layer, path, auxiliary_layers, auto_close_gaps


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    if len(argv) >= 3 and argv[0] == "--gaps-for-composite":
        primary_layer, path, auxiliary_layers, auto_close_gaps = _parse_composite_gaps_argv(argv)
        result = layer_gaps_for_composite_file(
            path,
            primary_layer,
            auxiliary_layers,
            auto_close_gaps=auto_close_gaps,
        )
        print(json.dumps(result))
        return 0
    if len(argv) >= 3 and argv[0] == "--gaps-for":
        result = layer_gaps_for_file(Path(argv[2]), argv[1])
        print(json.dumps(result))
        return 0
    if not argv:
        print("[]")
        return 0
    result = layer_catalog([Path(p) for p in argv])
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
