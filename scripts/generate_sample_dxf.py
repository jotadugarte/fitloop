#!/usr/bin/env python3
"""Regenerate nesting_engine/tests/fixtures/sample_piece.dxf (needs ezdxf)."""
from pathlib import Path

import ezdxf

OUT = Path(__file__).resolve().parents[1] / "nesting_engine" / "tests" / "fixtures" / "sample_piece.dxf"
LAYER = "PIECES"


def main() -> None:
  OUT.parent.mkdir(parents=True, exist_ok=True)
  doc = ezdxf.new("R2010")
  msp = doc.modelspace()
  msp.add_lwpolyline(
    [(0, 0), (100, 0), (100, 50), (0, 50)],
    close=True,
    dxfattribs={"layer": LAYER},
  )
  doc.saveas(OUT)
  print(f"wrote {OUT}")


if __name__ == "__main__":
  main()
