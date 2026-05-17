# [REQ-FIT-NEST-001] Nesting library spike: holes, any-angle rotation, ADR 0001.
from __future__ import annotations

from pathlib import Path

from shapely.geometry import Polygon, box

from nesting_engine.nest_spike import capabilities, run_spike_nest

ADR_PATH = Path(__file__).resolve().parents[2] / "docs" / "core" / "ADRs" / "0001-nesting-library.md"


def test_capabilities_report_holes_and_rotation() -> None:
    caps = capabilities()

    assert caps.supports_holes is True
    assert caps.supports_any_angle_rotation is True
    assert "libnest2d" in caps.library.lower()


def test_spike_places_piece_with_hole() -> None:
    outer = box(0, 0, 80, 40)
    hole = box(20, 10, 60, 30)
    piece = Polygon(outer.exterior.coords, [list(hole.exterior.coords)])

    result = run_spike_nest([piece], bin_width=200, bin_height=200)

    assert result.all_placed is True
    assert len(result.placements) == 1
    assert result.placements[0].rotation_deg >= 0


def test_spike_uses_non_zero_rotation_when_required() -> None:
    # 90×20 mm — only fits in 50×100 bin when rotated 90° (20×90).
    piece = box(0, 0, 90, 20)

    result = run_spike_nest([piece], bin_width=50, bin_height=100)

    assert result.all_placed is True
    assert result.placements[0].rotation_deg == 90.0


def test_adr_0001_documents_library_decision() -> None:
    assert ADR_PATH.is_file(), f"missing ADR: {ADR_PATH}"

    text = ADR_PATH.read_text(encoding="utf-8")

    assert "Accepted" in text
    assert "libnest2d" in text.lower()
    assert "hole" in text.lower()
    assert "rotation" in text.lower()
    assert "REQ-FIT-NEST-001" in text
