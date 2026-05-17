"""Emit sorted union of DXF layer names from one or more files (JSON array to stdout)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import ezdxf


def layer_names_from_file(path: Path) -> set[str]:
    doc = ezdxf.readfile(path)
    names = {layer.dxf.name for layer in doc.layers}
    for entity in doc.modelspace():
        if entity.dxf.hasattr("layer"):
            names.add(entity.dxf.layer)
    return names


def union_layer_names(paths: list[Path]) -> list[str]:
    names: set[str] = set()
    for path in paths:
        names |= layer_names_from_file(path)
    return sorted(names)


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    if not argv:
        print("[]")
        return 0
    result = union_layer_names([Path(p) for p in argv])
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
