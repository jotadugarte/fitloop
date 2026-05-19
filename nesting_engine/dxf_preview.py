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
    min_x = math.inf
    min_y = math.inf
    max_x = -math.inf
    max_y = -math.inf
    cursor_max_x: float | None = None

    for file_index, path in enumerate(dxf_paths):
        file_config = _file_config_at(file_configs, file_index)
        doc = ezdxf.readfile(path)
        colors = layer_catalog_from_file(path)
        file_min_x = math.inf
        file_min_y = math.inf
        file_max_x = -math.inf
        file_max_y = -math.inf
        file_layers = _file_layer_polylines(
            path,
            doc,
            layer_names,
            file_config=file_config,
            curve_tolerance_mm=curve_tolerance_mm,
            max_block_depth=max_block_depth,
        )
        if not file_layers:
            continue

        for layer_name, polylines in file_layers.items():
            for points in polylines:
                for x, y in points:
                    file_min_x = min(file_min_x, x)
                    file_min_y = min(file_min_y, y)
                    file_max_x = max(file_max_x, x)
                    file_max_y = max(file_max_y, y)

        if file_min_x is math.inf:
            continue

        if cursor_max_x is None:
            place_offset_x = 0.0
        else:
            place_offset_x = cursor_max_x + _FILE_GAP_MM - file_min_x

        for layer_name, polylines in file_layers.items():
            if not polylines:
                continue
            shifted = [[[_shift_x(x, place_offset_x), y] for x, y in line] for line in polylines]
            entry = layers.setdefault(
                layer_name,
                {"name": layer_name, "color": colors.get(layer_name, "#808080"), "polylines": []},
            )
            if layer_name in colors:
                entry["color"] = colors[layer_name]
            cast_polylines = entry["polylines"]
            assert isinstance(cast_polylines, list)
            cast_polylines.extend(shifted)

        placed_min_x = file_min_x + place_offset_x
        placed_max_x = file_max_x + place_offset_x
        min_x = min(min_x, placed_min_x)
        min_y = min(min_y, file_min_y)
        max_x = max(max_x, placed_max_x)
        max_y = max(max_y, file_max_y)
        cursor_max_x = placed_max_x

    if min_x is math.inf:
        return _empty_preview()

    ordered_layers = [
        {
            "name": name,
            "color": layers[name]["color"],
            "polylines": layers[name]["polylines"],
        }
        for name in sorted(layers)
    ]

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
) -> dict[str, list[list[list[float]]]]:
    primary_layer = file_config.get("primary_layer")
    if isinstance(primary_layer, str) and primary_layer.strip():
        return _composite_file_layer_polylines(
            path,
            doc,
            primary_layer.strip(),
            list(file_config.get("auxiliary_layers") or []),
            curve_tolerance_mm=curve_tolerance_mm,
            max_block_depth=max_block_depth,
        )

    included = {name for name in list(file_config.get("layer_names") or default_layer_names) if name}
    if not included:
        return {}

    file_layers: dict[str, list[list[list[float]]]] = {name: [] for name in included}
    for polyline in _iter_layer_polylines(
        doc,
        included,
        curve_tolerance_mm=curve_tolerance_mm,
        max_block_depth=max_block_depth,
    ):
        layer_name = str(polyline["layer"])
        points = polyline["points"]
        file_layers.setdefault(layer_name, []).append(points)
    return file_layers


def _composite_file_layer_polylines(
    path: Path,
    doc: ezdxf.document.Drawing,
    primary_layer: str,
    auxiliary_layers: list[str],
    *,
    curve_tolerance_mm: float,
    max_block_depth: int,
) -> dict[str, list[list[list[float]]]]:
    from nesting_engine.composite_extract import load_composite_pieces

    included = {primary_layer}
    file_layers: dict[str, list[list[list[float]]]] = {primary_layer: []}
    for polyline in _iter_layer_polylines(
        doc,
        included,
        curve_tolerance_mm=curve_tolerance_mm,
        max_block_depth=max_block_depth,
    ):
        file_layers[primary_layer].append(polyline["points"])

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
                file_layers.setdefault(decoration.layer_name, []).append(points)

    return {name: polylines for name, polylines in file_layers.items() if polylines}


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

    return [{"layer": layer_name, "points": points}]


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
