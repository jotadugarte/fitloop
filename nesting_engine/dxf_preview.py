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
) -> dict[str, object]:
    included = {name for name in layer_names if name}
    if not included or not dxf_paths:
        return _empty_preview()

    layers: dict[str, dict[str, object]] = {}
    min_x = math.inf
    min_y = math.inf
    max_x = -math.inf
    max_y = -math.inf
    cursor_max_x: float | None = None

    for path in dxf_paths:
        doc = ezdxf.readfile(path)
        colors = layer_catalog_from_file(path)
        file_min_x = math.inf
        file_min_y = math.inf
        file_max_x = -math.inf
        file_max_y = -math.inf
        file_layers: dict[str, list[list[list[float]]]] = {name: [] for name in included}

        for polyline in _iter_layer_polylines(
            doc,
            included,
            curve_tolerance_mm=curve_tolerance_mm,
            max_block_depth=max_block_depth,
        ):
            layer_name = polyline["layer"]
            points = polyline["points"]
            file_layers.setdefault(layer_name, []).append(points)
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

    return points


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    if len(argv) < 1:
        print(json.dumps(_empty_preview()))
        return 0

    config = json.loads(argv[0])
    paths = [Path(p) for p in argv[1:]]
    result = build_source_preview(
        paths,
        list(config.get("layer_names", [])),
        curve_tolerance_mm=float(config.get("curve_tolerance_mm", 0.25)),
    )
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
