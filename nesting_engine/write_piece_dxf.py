"""Write a single piece polygon to a DXF file (JSON config on argv[1])."""

from __future__ import annotations

import json
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent.parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from nesting_engine.dxf_output import write_piece_dxf  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    if len(argv) < 1:
        print("usage: write_piece_dxf.py CONFIG_JSON", file=sys.stderr)
        return 1

    config = json.loads(argv[0])
    write_piece_dxf(
        config["output_path"],
        config["rings"],
        layer_name=str(config.get("layer_name", "PIECES")),
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
