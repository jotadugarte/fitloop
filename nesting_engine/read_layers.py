"""Emit sorted DXF layer catalog (name + color) from one or more files (JSON to stdout)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import ezdxf
from ezdxf import colors


def layer_color_hex(layer) -> str:
    aci = layer.dxf.color
    if aci in (0, 256):
        aci = 7
    red, green, blue = colors.aci2rgb(aci)
    return f"#{red:02x}{green:02x}{blue:02x}"


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
            layer = doc.layers.get(name)
            catalog[name] = layer_color_hex(layer) if layer is not None else "#808080"
    return catalog


def layer_catalog(paths: list[Path]) -> list[dict[str, str]]:
    merged: dict[str, str] = {}
    for path in paths:
        for name, color in layer_catalog_from_file(path).items():
            merged.setdefault(name, color)
    return [{"name": name, "color": color} for name, color in sorted(merged.items())]


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
