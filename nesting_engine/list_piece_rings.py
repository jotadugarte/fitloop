"""List extractable piece ring coordinates for selected layers across DXF files."""

from __future__ import annotations

import json
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent.parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from nesting_engine.extract import extract_closed_contours  # noqa: E402


def _ring_coords(linear_ring) -> list[list[float]]:
    return [
        [round(float(x), 3), round(float(y), 3)]
        for x, y in linear_ring.coords[:-1]
    ]


def _polygon_rings(polygon) -> list[list[list[float]]]:
    rings = [_ring_coords(polygon.exterior)]
    rings.extend(_ring_coords(interior) for interior in polygon.interiors)
    return rings


def list_piece_rings(dxf_paths: list[Path], layer_names: list[str]) -> list[list[list[list[float]]]]:
    pieces: list[list[list[list[float]]]] = []
    for path in dxf_paths:
        for layer_name in layer_names:
            for polygon in extract_closed_contours(path, layer_name):
                if polygon.is_empty:
                    continue
                pieces.append(_polygon_rings(polygon))
    return pieces


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    if len(argv) < 1:
        print(json.dumps({"pieces": []}))
        return 0

    layer_names = json.loads(argv[0])
    paths = [Path(p) for p in argv[1:]]
    pieces = list_piece_rings(paths, layer_names)
    print(json.dumps({"pieces": pieces}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
