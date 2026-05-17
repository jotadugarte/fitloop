# [REQ-FIT-EXT-001] Sample DXF yields at least one closed contour on selected layer.
from __future__ import annotations

from pathlib import Path

from nesting_engine.extract import extract_closed_contours

FIXTURES = Path(__file__).parent / "fixtures"
SAMPLE_DXF = FIXTURES / "sample_piece.dxf"
LAYER = "PIECES"


def test_extract_at_least_one_closed_contour_on_selected_layer() -> None:
  assert SAMPLE_DXF.is_file(), f"missing fixture: {SAMPLE_DXF}"

  contours = extract_closed_contours(SAMPLE_DXF, layer_name=LAYER)

  assert len(contours) >= 1
  polygon = contours[0]
  assert polygon.is_valid
  assert not polygon.is_empty
  assert polygon.area > 0
