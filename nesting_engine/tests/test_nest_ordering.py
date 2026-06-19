# [REQ-FIT-NEST-002] Multi-start ordering seed tests.
from __future__ import annotations

from shapely.geometry import box

from nesting_engine.nest_ordering import generate_seeds, order_by_area


def test_generate_seeds_is_deduplicated_and_capped() -> None:
    pieces = [box(0, 0, 10, 10), box(0, 0, 40, 5), box(0, 0, 5, 30)]
    seeds = generate_seeds(len(pieces), pieces, max_seeds=8)
    assert len(seeds) <= 8
    assert seeds[0].piece_order == order_by_area(pieces, descending=True)


def test_generate_seeds_thorough_profiles_produce_more_than_seven() -> None:
    """[REQ-FIT-NEST-002] Thorough mode with 3 profiles × orders must produce > 7 seeds."""
    pieces = [box(0, 0, i * 10, 10) for i in range(1, 6)]
    seeds = generate_seeds(len(pieces), pieces, max_seeds=21, enable_orientation_profiles=True)
    assert len(seeds) > 7


def test_generate_seeds_thorough_includes_cardinal_and_bar_profiles() -> None:
    """[REQ-FIT-NEST-002] Thorough seed pool must include cardinal_90 and bar_parallel_long_edge."""
    pieces = [box(0, 0, i * 10, 10) for i in range(1, 5)]
    seeds = generate_seeds(len(pieces), pieces, max_seeds=64, enable_orientation_profiles=True)
    profile_names = {seed.orientation_profile for seed in seeds}
    assert "cardinal_90" in profile_names
    assert "bar_parallel_long_edge" in profile_names
    assert "as_extracted" in profile_names


def test_generate_seeds_fast_mode_only_as_extracted() -> None:
    """Fast mode must only produce as_extracted profile seeds."""
    pieces = [box(0, 0, i * 10, 10) for i in range(1, 5)]
    seeds = generate_seeds(len(pieces), pieces, max_seeds=32, enable_orientation_profiles=False)
    assert all(seed.orientation_profile == "as_extracted" for seed in seeds)


def test_generate_seeds_shuffle_pool_configurable() -> None:
    """[REQ-FIT-NEST-002] shuffle_count controls how many shuffle seeds are added."""
    pieces = [box(0, 0, i * 5, 5) for i in range(1, 8)]
    seeds_4 = generate_seeds(
        len(pieces), pieces, max_seeds=64, shuffle_count=4, shuffle_seed_base=42
    )
    seeds_1 = generate_seeds(
        len(pieces), pieces, max_seeds=64, shuffle_count=1, shuffle_seed_base=42
    )
    # More shuffle seeds should appear with higher shuffle_count
    shuffle_names_4 = {s.name for s in seeds_4 if "shuffle" in s.name}
    shuffle_names_1 = {s.name for s in seeds_1 if "shuffle" in s.name}
    assert len(shuffle_names_4) >= len(shuffle_names_1)


def test_generate_seeds_deterministic_for_same_base() -> None:
    """Seeds generated with same parameters must be identical (deterministic)."""
    pieces = [box(0, 0, i * 8, 8) for i in range(1, 6)]
    seeds_a = generate_seeds(len(pieces), pieces, max_seeds=32, shuffle_seed_base=99)
    seeds_b = generate_seeds(len(pieces), pieces, max_seeds=32, shuffle_seed_base=99)
    assert [s.piece_order for s in seeds_a] == [s.piece_order for s in seeds_b]


def test_generate_seeds_empty_pieces() -> None:
    """Empty piece list returns a single empty seed."""
    seeds = generate_seeds(0, [], max_seeds=8, enable_orientation_profiles=True)
    assert len(seeds) == 1
    assert seeds[0].piece_order == ()
    assert seeds[0].orientation_profile == "as_extracted"
