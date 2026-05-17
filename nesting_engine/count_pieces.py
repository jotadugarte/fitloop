"""Count extractable closed contours for selected layers across DXF files."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from nesting_engine.extract import extract_closed_contours


def count_extractable_pieces(dxf_paths: list[Path], layer_names: list[str]) -> int:
    total = 0
    for path in dxf_paths:
        for layer_name in layer_names:
            total += len(extract_closed_contours(path, layer_name))
    return total


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    if len(argv) < 1:
        print(json.dumps({"piece_count": 0}))
        return 0

    layer_names = json.loads(argv[0])
    paths = [Path(p) for p in argv[1:]]
    count = count_extractable_pieces(paths, layer_names)
    print(json.dumps({"piece_count": count}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
