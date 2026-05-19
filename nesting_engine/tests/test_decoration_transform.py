# [REQ-FIT-DXF-002] Decorations follow the same placement transform as the primary polygon.
from __future__ import annotations

import pytest
from shapely.geometry import LineString, Point, Polygon

from nesting_engine.composite_extract import DecorationEntity
from nesting_engine.decoration_transform import transform_decorations
from nesting_engine.nest_placement import Placement, placed_polygon


def _offset_from_centroid(polygon: Polygon, point: Point) -> tuple[float, float]:
    centroid = polygon.centroid
    return (point.x - centroid.x, point.y - centroid.y)


def test_transform_decorations_preserves_relative_offset_to_primary_centroid() -> None:
    primary = Polygon([(0, 0), (40, 0), (40, 40), (0, 40)])
    source_line = LineString([(25, 20), (30, 20)])
    decoration = DecorationEntity(
        layer_name="GRABADO",
        geometry_type="line",
        payload={"coordinates": list(source_line.coords)},
    )
    placement = Placement(x=12.0, y=8.0, rotation_deg=90.0)

    placed_primary = placed_polygon(primary, placement)
    transformed = transform_decorations([decoration], primary, placement)

    assert len(transformed) == 1
    placed_line = LineString(transformed[0].payload["coordinates"])
    midpoint = placed_line.interpolate(0.5, normalized=True)

    source_midpoint = source_line.interpolate(0.5, normalized=True)
    before_offset = _offset_from_centroid(primary, source_midpoint)
    after_offset = _offset_from_centroid(placed_primary, midpoint)

    assert before_offset[0] == pytest.approx(after_offset[0], abs=1e-6)
    assert before_offset[1] == pytest.approx(after_offset[1], abs=1e-6)
    assert source_midpoint.distance(primary.centroid) == pytest.approx(
        midpoint.distance(placed_primary.centroid),
        abs=1e-6,
    )


def test_transform_decorations_rotates_text_insert_point() -> None:
    primary = Polygon([(0, 0), (40, 0), (40, 40), (0, 40)])
    decoration = DecorationEntity(
        layer_name="GRABADO",
        geometry_type="text",
        payload={"text": "MARK", "insert": [20.0, 25.0]},
    )
    placement = Placement(x=5.0, y=10.0, rotation_deg=45.0)

    placed_primary = placed_polygon(primary, placement)
    transformed = transform_decorations([decoration], primary, placement)

    assert len(transformed) == 1
    insert = transformed[0].payload["insert"]
    placed_insert = Point(insert[0], insert[1])
    source_insert = Point(20.0, 25.0)

    before_offset = _offset_from_centroid(primary, source_insert)
    after_offset = _offset_from_centroid(placed_primary, placed_insert)
    assert before_offset[0] == pytest.approx(after_offset[0], abs=1e-6)
    assert before_offset[1] == pytest.approx(after_offset[1], abs=1e-6)
