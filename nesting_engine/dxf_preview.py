"""Build SVG-friendly geometry from input DXFs for selected layers only."""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import ezdxf
from ezdxf.entities import Insert
from ezdxf.math import Matrix44, Vec3
from ezdxf.path import make_path

from nesting_engine.read_layers import layer_catalog_from_file

_MAX_ENTITIES = 100_000
_DEFAULT_MAX_BLOCK_DEPTH = 8
_FILE_GAP_MM = 40.0


def build_source_preview(
    dxf_paths: list[Path],
    layer_names: list[str],
    *,
    curve_tolerance_mm: float = 0.25,
    max_block_depth: int = _DEFAULT_MAX_BLOCK_DEPTH,
    file_configs: list[dict[str, object]] | None = None,
) -> dict[str, object]:
    if not dxf_paths:
        return _empty_preview()

    layers: dict[str, dict[str, object]] = {}
    bounds = _empty_bounds()
    cursor_max_x: float | None = None

    for file_index, path in enumerate(dxf_paths):
        file_config = _file_config_at(file_configs, file_index)
        placement = _file_preview_placement(
            path,
            layer_names,
            file_config=file_config,
            curve_tolerance_mm=curve_tolerance_mm,
            max_block_depth=max_block_depth,
            cursor_max_x=cursor_max_x,
        )
        if placement is None:
            continue
        file_layers, colors, place_offset_x, file_bounds = placement
        _merge_shifted_layers(layers, file_layers, colors, place_offset_x)
        bounds, cursor_max_x = _advance_preview_bounds(bounds, file_bounds, place_offset_x)

    if bounds["min_x"] is math.inf:
        return _empty_preview()
    return _preview_payload(layers, bounds)


def _empty_bounds() -> dict[str, float]:
    return {"min_x": math.inf, "min_y": math.inf, "max_x": -math.inf, "max_y": -math.inf}


def _file_preview_placement(
    path: Path,
    layer_names: list[str],
    *,
    file_config: dict[str, object],
    curve_tolerance_mm: float,
    max_block_depth: int,
    cursor_max_x: float | None,
) -> tuple[
    dict[str, dict[str, object]],
    dict[str, str],
    float,
    dict[str, float],
] | None:
    doc = ezdxf.readfile(path)
    colors = layer_catalog_from_file(path)
    file_layers = _file_layer_polylines(
        path,
        doc,
        layer_names,
        file_config=file_config,
        curve_tolerance_mm=curve_tolerance_mm,
        max_block_depth=max_block_depth,
    )
    if not file_layers:
        return None

    file_bounds = _bounds_from_layer_polylines(file_layers)
    if file_bounds is None:
        return None

    place_offset_x = 0.0 if cursor_max_x is None else cursor_max_x + _FILE_GAP_MM - file_bounds["min_x"]
    return file_layers, colors, place_offset_x, file_bounds


def _bounds_from_layer_polylines(
    file_layers: dict[str, dict[str, object]],
) -> dict[str, float] | None:
    min_x = math.inf
    min_y = math.inf
    max_x = -math.inf
    max_y = -math.inf
    for data in file_layers.values():
        polylines = data["polylines"]
        for points in polylines:
            for x, y in points:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if min_x is math.inf:
        return None
    return {"min_x": min_x, "min_y": min_y, "max_x": max_x, "max_y": max_y}


def _merge_shifted_layers(
    layers: dict[str, dict[str, object]],
    file_layers: dict[str, dict[str, object]],
    colors: dict[str, str],
    place_offset_x: float,
) -> None:
    for layer_name, data in file_layers.items():
        polylines = data["polylines"]
        polyline_open_flags = data.get("polyline_open_flags") or [False] * len(polylines)
        gaps = data["gaps"]
        auto_close_lines = data["auto_close_lines"]

        shifted_polylines = [[[_shift_x(x, place_offset_x), y] for x, y in line] for line in polylines]

        shifted_gaps = []
        for gap in gaps:
            shifted_gaps.append({
                "distance_mm": gap["distance_mm"],
                "start": [_shift_x(gap["start"][0], place_offset_x), gap["start"][1]],
                "end": [_shift_x(gap["end"][0], place_offset_x), gap["end"][1]],
                "auto_closed": gap["auto_closed"]
            })

        shifted_auto_close_lines = [[[_shift_x(x, place_offset_x), y] for x, y in line] for line in auto_close_lines]

        entry = layers.setdefault(
            layer_name,
            {
                "name": layer_name,
                "color": colors.get(layer_name, "#808080"),
                "polylines": [],
                "polyline_open_flags": [],
                "gaps": [],
                "auto_close_lines": []
            },
        )
        if layer_name in colors:
            entry["color"] = colors[layer_name]

        entry["polylines"].extend(shifted_polylines)
        entry["polyline_open_flags"].extend(polyline_open_flags)
        entry["gaps"].extend(shifted_gaps)
        entry["auto_close_lines"].extend(shifted_auto_close_lines)


def _advance_preview_bounds(
    bounds: dict[str, float],
    file_bounds: dict[str, float],
    place_offset_x: float,
) -> tuple[dict[str, float], float]:
    placed_min_x = file_bounds["min_x"] + place_offset_x
    placed_max_x = file_bounds["max_x"] + place_offset_x
    return {
        "min_x": min(bounds["min_x"], placed_min_x),
        "min_y": min(bounds["min_y"], file_bounds["min_y"]),
        "max_x": max(bounds["max_x"], placed_max_x),
        "max_y": max(bounds["max_y"], file_bounds["max_y"]),
    }, placed_max_x


def _preview_payload(
    layers: dict[str, dict[str, object]],
    bounds: dict[str, float],
) -> dict[str, object]:
    ordered_layers = [
        {
            "name": name,
            "color": layers[name]["color"],
            "polylines": layers[name]["polylines"],
            "polyline_open_flags": layers[name]["polyline_open_flags"],
            "gaps": layers[name]["gaps"],
            "auto_close_lines": layers[name]["auto_close_lines"],
        }
        for name in sorted(layers)
    ]
    min_x = bounds["min_x"]
    min_y = bounds["min_y"]
    max_x = bounds["max_x"]
    max_y = bounds["max_y"]
    return {
        "width_mm": max(max_x - min_x, 1.0),
        "height_mm": max(max_y - min_y, 1.0),
        "offset_x_mm": min_x,
        "offset_y_mm": min_y,
        "layers": ordered_layers,
    }


def _file_config_at(
    file_configs: list[dict[str, object]] | None,
    file_index: int,
) -> dict[str, object]:
    if not file_configs or file_index >= len(file_configs):
        return {}
    return file_configs[file_index]


def _file_layer_polylines(
    path: Path,
    doc: ezdxf.document.Drawing,
    default_layer_names: list[str],
    *,
    file_config: dict[str, object],
    curve_tolerance_mm: float,
    max_block_depth: int,
) -> dict[str, dict[str, object]]:
    primary_layer = file_config.get("primary_layer")
    if isinstance(primary_layer, str) and primary_layer.strip():
        return _composite_file_layer_polylines(
            path,
            doc,
            primary_layer.strip(),
            list(file_config.get("auxiliary_layers") or []),
            curve_tolerance_mm=curve_tolerance_mm,
            max_block_depth=max_block_depth,
            file_config=file_config,
        )

    included = {name for name in list(file_config.get("layer_names") or default_layer_names) if name}
    if not included:
        return {}

    result: dict[str, dict[str, object]] = {
        name: {"polylines": [], "polyline_open_flags": [], "gaps": [], "auto_close_lines": []}
        for name in included
    }
    for polyline in _iter_layer_polylines(
        doc,
        included,
        curve_tolerance_mm=curve_tolerance_mm,
        max_block_depth=max_block_depth,
    ):
        layer_name = str(polyline["layer"])
        points = polyline["points"]
        result.setdefault(layer_name, {"polylines": [], "polyline_open_flags": [], "gaps": [], "auto_close_lines": []})
        result[layer_name]["polylines"].append(points)
        result[layer_name]["polyline_open_flags"].append(polyline.get("is_open", False))

    auto_close_layers = file_config.get("auto_close_layers") or []
    from nesting_engine.read_layers import find_layer_gaps
    for name in result:
        gaps = find_layer_gaps(doc, name, curve_tolerance_mm)
        is_auto_close = name in auto_close_layers
        gaps_with_status = []
        auto_close_lines = []
        for gap in gaps:
            should_auto_close = is_auto_close and gap["distance_mm"] <= 15.0
            gap_data = {
                "distance_mm": gap["distance_mm"],
                "start": gap["start"],
                "end": gap["end"],
                "auto_closed": should_auto_close
            }
            gaps_with_status.append(gap_data)
            if should_auto_close:
                auto_close_lines.append([gap["start"], gap["end"]])

        result[name]["gaps"] = gaps_with_status
        result[name]["auto_close_lines"] = auto_close_lines

    return {name: data for name, data in result.items() if data["polylines"]}


def _composite_file_layer_polylines(
    path: Path,
    doc: ezdxf.document.Drawing,
    primary_layer: str,
    auxiliary_layers: list[str],
    *,
    curve_tolerance_mm: float,
    max_block_depth: int,
    file_config: dict[str, object],
) -> dict[str, dict[str, object]]:
    from nesting_engine.composite_extract import load_composite_pieces

    result: dict[str, dict[str, object]] = {
        primary_layer: {"polylines": [], "polyline_open_flags": [], "gaps": [], "auto_close_lines": []}
    }
    for polyline in _iter_layer_polylines(
        doc,
        {primary_layer},
        curve_tolerance_mm=curve_tolerance_mm,
        max_block_depth=max_block_depth,
    ):
        result[primary_layer]["polylines"].append(polyline["points"])
        result[primary_layer]["polyline_open_flags"].append(polyline.get("is_open", False))

    auto_close_layers = file_config.get("auto_close_layers") or []
    from nesting_engine.read_layers import find_layer_gaps
    gaps = find_layer_gaps(doc, primary_layer, curve_tolerance_mm)
    is_auto_close = primary_layer in auto_close_layers
    gaps_with_status = []
    auto_close_lines = []
    for gap in gaps:
        should_auto_close = is_auto_close and gap["distance_mm"] <= 15.0
        gap_data = {
            "distance_mm": gap["distance_mm"],
            "start": gap["start"],
            "end": gap["end"],
            "auto_closed": should_auto_close
        }
        gaps_with_status.append(gap_data)
        if should_auto_close:
            auto_close_lines.append([gap["start"], gap["end"]])

    result[primary_layer]["gaps"] = gaps_with_status
    result[primary_layer]["auto_close_lines"] = auto_close_lines

    aux_layers = [name for name in auxiliary_layers if name]
    if aux_layers:
        pieces = load_composite_pieces(
            path,
            primary_layer,
            aux_layers,
            curve_tolerance_mm=curve_tolerance_mm,
            max_block_depth=max_block_depth,
        )
        for piece in pieces:
            for decoration in piece.decorations:
                if decoration.geometry_type != "line":
                    continue
                coordinates = decoration.payload.get("coordinates")
                if not coordinates or len(coordinates) < 2:
                    continue
                points = [[float(x), float(y)] for x, y in coordinates]
                result.setdefault(
                    decoration.layer_name,
                    {"polylines": [], "polyline_open_flags": [], "gaps": [], "auto_close_lines": []}
                )
                result[decoration.layer_name]["polylines"].append(points)
                result[decoration.layer_name]["polyline_open_flags"].append(False)

    return {name: data for name, data in result.items() if data["polylines"]}


def _empty_preview() -> dict[str, object]:
    return {
        "width_mm": 1.0,
        "height_mm": 1.0,
        "offset_x_mm": 0.0,
        "offset_y_mm": 0.0,
        "layers": [],
    }


def _shift_x(x: float, offset_x: float) -> float:
    return x + offset_x


def _iter_layer_polylines(
    doc: ezdxf.document.Drawing,
    included_layers: set[str],
    *,
    curve_tolerance_mm: float,
    max_block_depth: int,
) -> list[dict[str, object]]:
    polylines: list[dict[str, object]] = []
    scanned = 0

    for entity in doc.modelspace():
        scanned += 1
        assert scanned <= _MAX_ENTITIES, "DXF entity limit exceeded"
        polylines.extend(
            _polylines_from_entity(
                doc,
                entity,
                included_layers,
                Matrix44(),
                depth=0,
                curve_tolerance_mm=curve_tolerance_mm,
                max_block_depth=max_block_depth,
            )
        )

    return polylines


def _polylines_from_entity(
    doc: ezdxf.document.Drawing,
    entity: object,
    included_layers: set[str],
    transform: Matrix44,
    *,
    depth: int,
    curve_tolerance_mm: float,
    max_block_depth: int,
) -> list[dict[str, object]]:
    if isinstance(entity, Insert):
        if depth >= max_block_depth:
            return []
        block = doc.blocks.get(entity.dxf.name)
        if block is None:
            return []
        combined = transform @ entity.matrix44()
        nested: list[dict[str, object]] = []
        for child in block:
            nested.extend(
                _polylines_from_entity(
                    doc,
                    child,
                    included_layers,
                    combined,
                    depth=depth + 1,
                    curve_tolerance_mm=curve_tolerance_mm,
                    max_block_depth=max_block_depth,
                )
            )
        return nested

    if not hasattr(entity, "dxf") or not entity.dxf.hasattr("layer"):
        return []

    layer_name = entity.dxf.layer
    if layer_name not in included_layers:
        return []

    points = _flatten_entity_points(entity, transform, curve_tolerance_mm=curve_tolerance_mm)
    if len(points) < 2:
        return []

    is_open = False
    if hasattr(entity, "closed") or hasattr(entity, "is_closed"):
        closed_attrib = entity.closed if hasattr(entity, "closed") else entity.is_closed
        if not closed_attrib:
            x0, y0 = points[0]
            x1, y1 = points[-1]
            dist = math.hypot(x1 - x0, y1 - y0)
            if dist > 2.0:
                is_open = True

    return [{"layer": layer_name, "points": points, "is_open": is_open}]


def _flatten_entity_points(
    entity: object,
    transform: Matrix44,
    *,
    curve_tolerance_mm: float,
) -> list[list[float]]:
    try:
        path = make_path(entity)
    except (TypeError, ValueError):
        return []

    points: list[list[float]] = []
    for vertex in path.flattening(curve_tolerance_mm):
        point = transform.transform(Vec3(float(vertex.x), float(vertex.y), 0.0))
        points.append([float(point.x), float(point.y)])

    return _pin_curve_path_endpoints(entity, points, transform)


def _pin_curve_path_endpoints(
    entity: object,
    points: list[list[float]],
    transform: Matrix44,
) -> list[list[float]]:
    if len(points) < 2 or not hasattr(entity, "dxftype"):
        return points

    if entity.dxftype() == "ARC":
        start = transform.transform(Vec3(float(entity.start_point.x), float(entity.start_point.y), 0.0))
        end = transform.transform(Vec3(float(entity.end_point.x), float(entity.end_point.y), 0.0))
        points[0] = [float(start.x), float(start.y)]
        points[-1] = [float(end.x), float(end.y)]

    return points


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    if len(argv) < 1:
        print(json.dumps(_empty_preview()))
        return 0

    config = json.loads(argv[0])
    paths = [Path(p) for p in argv[1:]]
    file_configs = config.get("input_files")
    result = build_source_preview(
        paths,
        list(config.get("layer_names", [])),
        curve_tolerance_mm=float(config.get("curve_tolerance_mm", 0.25)),
        file_configs=list(file_configs) if file_configs else None,
    )
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
