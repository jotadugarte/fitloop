# [REQ-FIT-NEST-002] Piece ordering generators for multi-start nesting seeds.
from __future__ import annotations

import random
from dataclasses import dataclass

from nesting_engine.nest_orientation import orientation_profiles
from nesting_engine.piece_loader import piece_polygon
from shapely.geometry import Polygon


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
) -> list[OrderingSeed]:
    assert piece_count >= 0
    if piece_count == 0:
        return [OrderingSeed(name="empty", piece_order=(), orientation_profile="as_extracted")]

    orders = _unique_orders(piece_count, pieces)
    profiles = ("as_extracted",)
    seeds: list[OrderingSeed] = []
    for order_name, order in orders:
        for profile in profiles:
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


def _unique_orders(
    piece_count: int,
    pieces: list[Polygon] | None,
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
    shuffled = list(indices)
    rng = random.Random(42)
    rng.shuffle(shuffled)
    orders.append(("shuffle_42", tuple(shuffled)))

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
