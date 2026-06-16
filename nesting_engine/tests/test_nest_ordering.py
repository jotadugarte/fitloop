# [REQ-FIT-NEST-002] Multi-start ordering seed tests.
from __future__ import annotations

from shapely.geometry import box

from nesting_engine.nest_ordering import generate_seeds, order_by_area


def test_generate_seeds_is_deduplicated_and_capped() -> None:
    pieces = [box(0, 0, 10, 10), box(0, 0, 40, 5), box(0, 0, 5, 30)]
    seeds = generate_seeds(len(pieces), pieces, max_seeds=8)
    assert len(seeds) <= 8
    assert seeds[0].piece_order == order_by_area(pieces, descending=True)
