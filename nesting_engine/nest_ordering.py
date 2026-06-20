# [REQ-FIT-NEST-002] Piece ordering generators for multi-start nesting seeds.
from __future__ import annotations

import os
import random
from dataclasses import dataclass

from nesting_engine.nest_orientation import orientation_profiles
from nesting_engine.piece_loader import piece_polygon
from shapely.geometry import Polygon

# Orientation profiles active in thorough mode (fast mode always uses as_extracted only).
_THOROUGH_PROFILES = ("as_extracted", "cardinal_90", "bar_parallel_long_edge")

# Default base for random shuffle seeds. Override via FITLOOP_NESTING_SHUFFLE_SEED_BASE.
_DEFAULT_SHUFFLE_SEED_BASE = 42
_DEFAULT_SHUFFLE_COUNT = 4


@dataclass(frozen=True)
class OrderingSeed:
    name: str
    piece_order: tuple[int, ...] | None
    orientation_profile: str


def generate_seeds(
    piece_count: int,
    pieces: list[Polygon] | None = None,
    *,
    max_seeds: int = 16,
    enable_orientation_profiles: bool = False,
    shuffle_seed_base: int | None = None,
    shuffle_count: int = _DEFAULT_SHUFFLE_COUNT,
) -> list[OrderingSeed]:
    """[REQ-FIT-NEST-002] Generate a diverse pool of ordering seeds for multi-start nesting.

    When ``enable_orientation_profiles`` is True (thorough mode), seeds are paired with
    all three orientation profiles (as_extracted, cardinal_90, bar_parallel_long_edge)
    and augmented with additional random shuffle orders.

    Pre-condition: piece_count >= 0
    Post-condition: len(result) <= max_seeds; all piece_order entries are valid permutations
    """
    assert piece_count >= 0
    if piece_count == 0:
        return [OrderingSeed(name="empty", piece_order=(), orientation_profile="as_extracted")]

    seed_base = shuffle_seed_base if shuffle_seed_base is not None else _read_shuffle_seed_base_env()
    orders = _unique_orders(piece_count, pieces, shuffle_seed_base=seed_base, shuffle_count=shuffle_count)

    active_profiles = _THOROUGH_PROFILES if enable_orientation_profiles else ("as_extracted",)

    seeds: list[OrderingSeed] = []
    for order_name, order in orders:
        for profile in active_profiles:
            seeds.append(
                OrderingSeed(
                    name=f"{order_name}:{profile}",
                    piece_order=order,
                    orientation_profile=profile,
                )
            )
            if len(seeds) >= max_seeds:
                return seeds
    return seeds


def _read_shuffle_seed_base_env() -> int:
    """Read optional FITLOOP_NESTING_SHUFFLE_SEED_BASE from environment (default 42)."""
    raw = os.environ.get("FITLOOP_NESTING_SHUFFLE_SEED_BASE", "")
    if raw.strip().isdigit():
        return int(raw.strip())
    return _DEFAULT_SHUFFLE_SEED_BASE


def _unique_orders(
    piece_count: int,
    pieces: list[Polygon] | None,
    *,
    shuffle_seed_base: int = _DEFAULT_SHUFFLE_SEED_BASE,
    shuffle_count: int = _DEFAULT_SHUFFLE_COUNT,
) -> list[tuple[str, tuple[int, ...]]]:
    indices = list(range(piece_count))
    orders: list[tuple[str, tuple[int, ...]]] = []
    if pieces is not None and len(pieces) == piece_count:
        orders.append(("area_desc", order_by_area(pieces, descending=True)))
        orders.append(("area_asc", order_by_area(pieces, descending=False)))
        orders.append(
            (
                "max_width_desc",
                tuple(
                    sorted(
                        indices,
                        key=lambda i: piece_polygon(pieces[i]).bounds[2]
                        - piece_polygon(pieces[i]).bounds[0],
                        reverse=True,
                    )
                ),
            )
        )
        orders.append(
            (
                "bar_first",
                tuple(
                    sorted(
                        indices,
                        key=lambda i: _aspect_ratio(pieces[i]),
                        reverse=True,
                    )
                ),
            )
        )
    else:
        orders.append(("area_desc", tuple(sorted(indices, reverse=True))))
        orders.append(("area_asc", tuple(indices)))
    orders.append(("index_desc", tuple(reversed(indices))))
    orders.append(("index_asc", tuple(indices)))

    # Fixed shuffle seed (for reproducibility)
    shuffled = list(indices)
    rng = random.Random(shuffle_seed_base)
    rng.shuffle(shuffled)
    orders.append((f"shuffle_{shuffle_seed_base}", tuple(shuffled)))

    # Additional shuffle seeds from the configurable pool
    for i in range(1, shuffle_count):
        extra = list(indices)
        random.Random(shuffle_seed_base + i).shuffle(extra)
        orders.append((f"shuffle_{shuffle_seed_base + i}", tuple(extra)))

    unique: list[tuple[str, tuple[int, ...]]] = []
    seen: set[tuple[int, ...]] = set()
    for name, order in orders:
        if order in seen:
            continue
        seen.add(order)
        unique.append((name, order))
    return unique


def order_by_area(pieces: list[Polygon], *, descending: bool) -> tuple[int, ...]:
    ranked = sorted(
        range(len(pieces)),
        key=lambda index: piece_polygon(pieces[index]).area,
        reverse=descending,
    )
    return tuple(ranked)


def _aspect_ratio(piece: Polygon) -> float:
    geometry = piece_polygon(piece)
    minx, miny, maxx, maxy = geometry.bounds
    width = maxx - minx
    height = maxy - miny
    if width <= 0.0 or height <= 0.0:
        return 1.0
    return max(width, height) / min(width, height)
