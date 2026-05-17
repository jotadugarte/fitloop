# [REQ-FIT-NEST-001] libnest2d binding spike: native import, holes, any-angle rotation.
from __future__ import annotations

from shapely.geometry import Polygon, box

from nesting_engine.nest_libnest2d import binding_spike_nest, libnest2d_binding_name


def test_libnest2d_native_binding_imports() -> None:
    name = libnest2d_binding_name()

    assert name
    assert "nest2d" in name.lower()


def test_binding_spike_places_piece_with_hole() -> None:
    outer = box(0, 0, 80, 40)
    hole = box(20, 10, 60, 30)
    piece = Polygon(outer.exterior.coords, [list(hole.exterior.coords)])

    result = binding_spike_nest([piece], bin_width_mm=200.0, bin_height_mm=200.0)

    assert result.all_placed is True
    assert len(result.placements) == 1
    assert result.placements[0].rotation_deg >= 0.0


def test_binding_spike_uses_non_zero_rotation_when_required() -> None:
    # 90×20 mm — does not fit at 0° in 50×100; binding must rotate.
    piece = box(0, 0, 90, 20)

    result = binding_spike_nest([piece], bin_width_mm=50.0, bin_height_mm=100.0)

    assert result.all_placed is True
    assert result.placements[0].rotation_deg != 0.0
    assert result.placements[0].rotation_deg >= 5.0
