# [REQ-FIT-NEST-001] ADR / libnest2d parity (migrated off nest_spike placement sweep).
from __future__ import annotations

from pathlib import Path

from shapely.geometry import Polygon, box

import nesting_engine.nest_spike as nest_spike
from nesting_engine.nest_libnest2d import binding_spike_nest, capabilities

ADR_PATH = Path(__file__).resolve().parents[2] / "docs" / "core" / "ADRs" / "0001-nesting-library.md"


def test_nest_spike_no_longer_exposes_placement_sweep() -> None:
    assert not hasattr(nest_spike, "run_spike_nest")
    assert not hasattr(nest_spike, "_place_with_rotation")


def test_capabilities_report_holes_and_rotation() -> None:
    caps = capabilities()

    assert caps.supports_holes is True
    assert caps.supports_any_angle_rotation is True
    assert "libnest2d" in caps.library.lower()
    assert caps.spike_only is False


def test_adr_0001_documents_library_decision() -> None:
    assert ADR_PATH.is_file(), f"missing ADR: {ADR_PATH}"

    text = ADR_PATH.read_text(encoding="utf-8")

    assert "Accepted" in text
    assert "libnest2d" in text.lower()
    assert "hole" in text.lower()
    assert "rotation" in text.lower()
    assert "REQ-FIT-NEST-001" in text
