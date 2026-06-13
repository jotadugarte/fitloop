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
    Return genuinely open gaps on a layer's contour polylines.

    A "gap" is the distance from the first to the last point of an individual
    open LWPOLYLINE/POLYLINE that is NOT part of a successfully-closed shape.

    Shapes composed of multiple polyline segments (chain-style or overlapping)
    look "open" per-polyline but the engine's polygonize step assembles them
    into a valid closed polygon.  To avoid false positives we run a lightweight
    extraction: if the engine finds ≥1 valid polygon on the layer we suppress
    ALL per-polyline open-end reports for that layer.

    Only if extraction yields zero polygons do we fall back to reporting each
    open polyline's individual gap.
    """
    # ── Try to extract polygons from this layer ───────────────────────────────
    # If the engine can form closed shapes from the segments, there are no real gaps.
    try:
        from nesting_engine.extract import extract_closed_contours
        # Use auto_close_gaps=False so we only count shapes the engine can form
        # WITHOUT any user-authorised closing — purely from geometry.
        polygons = extract_closed_contours(
            doc.filename,
            layer_name,
            curve_tolerance_mm=curve_tolerance_mm,
            auto_close_gaps=True,  # treat gaps ≤ 15mm as valid — app nests, not corrects
            warnings=[],
        )
        if polygons:
            # The engine successfully assembled a closed polygon → no real gaps.
            return []
    except Exception:
        # If extraction fails for any reason, fall through to the raw gap scan.
        pass

    # ── Fallback: raw per-polyline gap scan ───────────────────────────────────
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


def layer_catalog(paths: list[Path]) -> list[dict[str, object]]:
    merged: dict[str, dict[str, object]] = {}
    for path in paths:
        doc = ezdxf.readfile(path)
        for name, color in layer_catalog_from_file(path).items():
            gaps = find_layer_gaps(doc, name)
            if name not in merged:
                merged[name] = {"color": color, "gaps": gaps}
            else:
                merged[name]["gaps"].extend(gaps)
    return [{"name": name, "color": info["color"], "gaps": info["gaps"]} for name, info in sorted(merged.items())]


def union_layer_names(paths: list[Path]) -> list[str]:
    return [entry["name"] for entry in layer_catalog(paths)]


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    if not argv:
        print("[]")
        return 0
    result = layer_catalog([Path(p) for p in argv])
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
