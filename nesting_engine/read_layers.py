"""Emit sorted DXF layer catalog (name + color) from one or more files (JSON to stdout)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import ezdxf
from ezdxf import colors


import math
from ezdxf.path import make_path


def layer_color_hex(layer) -> str:
    aci = layer.dxf.color
    if aci in (0, 256):
        aci = 7
    red, green, blue = colors.aci2rgb(aci)
    return f"#{red:02x}{green:02x}{blue:02x}"


def find_layer_gaps(doc: ezdxf.document.Drawing, layer_name: str, curve_tolerance_mm: float = 0.25) -> list[dict[str, object]]:
    """
    Return open-end gaps on explicitly open LWPOLYLINE/POLYLINE entities.

    [REQ-FIT-DXF-002] Report per-entity gaps even when other closed contours exist
    on the same layer (e.g. 015.dxf: three closed pieces plus one open cut outline).
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


GAP_SILENT_MM = 2.0
GAP_AUTH_MAX_MM = 15.0


def gap_needs_authorization(distance_mm: float) -> bool:
    """Return True for gaps in the 2–15 mm range that need user auto-close authorization."""
    value = float(distance_mm)
    return GAP_SILENT_MM < value <= GAP_AUTH_MAX_MM


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


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
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
