# [REQ-FIT-DXF-002] [REQ-FIT-SPLIT-001] Split planner partitions composite decorations per child.
from __future__ import annotations

import pytest
from shapely.geometry import LineString, box

from nesting_engine.composite_extract import CompositePiece, DecorationEntity, partition_decorations
from nesting_engine.nest_types import SheetStockSpec
from nesting_engine.split_planner import plan_split

GRABADO = "GRABADO"
CORTE = "CORTE"


def _line_length(decoration: DecorationEntity) -> float:
    coords = decoration.payload["coordinates"]
    line = LineString(coords)
    return float(line.length)


def test_plan_split_partitions_grabado_line_across_two_children() -> None:
    mother_polygon = box(0, 0, 200, 80)
    mother = CompositePiece(
        polygon=mother_polygon,
        primary_layer_name=CORTE,
        decorations=[
            DecorationEntity(
                layer_name=GRABADO,
                geometry_type="line",
                payload={"coordinates": [(10.0, 40.0), (190.0, 40.0)]},
            )
        ],
    )
    stocks = [SheetStockSpec(width_mm=100, height_mm=100, quantity=None, sort_order=0)]

    split_result = plan_split(mother.polygon, stocks, margin_mm=0.0)
    assert split_result.feasible is True
    assert len(split_result.children) == 2

    children = partition_decorations(
        mother,
        split_result.children,
        split_result.cut_segments,
    )

    assert len(children) == 2
    assert all(child.primary_layer_name == CORTE for child in children)
    assert all(len(child.decorations) == 1 for child in children)
    assert all(deco.layer_name == GRABADO for child in children for deco in child.decorations)
    assert all(deco.geometry_type == "line" for child in children for deco in child.decorations)

    lengths = sorted(_line_length(child.decorations[0]) for child in children)
    assert lengths[0] == pytest.approx(90.0, abs=2.0)
    assert lengths[1] == pytest.approx(90.0, abs=2.0)
    assert sum(lengths) == pytest.approx(180.0, abs=3.0)


def test_partition_decorations_clips_on_child_boundary_not_mother_span() -> None:
    left = box(0, 0, 100, 80)
    right = box(100, 0, 200, 80)
    mother = CompositePiece(
        polygon=box(0, 0, 200, 80),
        primary_layer_name=CORTE,
        decorations=[
            DecorationEntity(
                layer_name=GRABADO,
                geometry_type="line",
                payload={"coordinates": [(10.0, 40.0), (190.0, 40.0)]},
            )
        ],
    )

    from nesting_engine.split_planner import SplitChild

    children = partition_decorations(
        mother,
        [
            SplitChild(label="a", polygon=left),
            SplitChild(label="b", polygon=right),
        ],
        [((100.0, 0.0), (100.0, 80.0))],
    )

    left_line = LineString(children[0].decorations[0].payload["coordinates"])
    right_line = LineString(children[1].decorations[0].payload["coordinates"])

    assert left_line.bounds[2] <= 100.5
    assert right_line.bounds[0] >= 99.5
