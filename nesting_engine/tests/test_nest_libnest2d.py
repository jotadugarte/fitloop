# [REQ-FIT-NEST-001] Production capabilities and nest_libnest2d adapter.
from __future__ import annotations

from nesting_engine.nest_libnest2d import capabilities


def test_capabilities_reports_libnest2d_production() -> None:
    caps = capabilities()

    assert caps.spike_only is False
    assert "libnest2d" in caps.library.lower()
