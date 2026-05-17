"""Tests for extractable piece counting (pre-flight)."""

from __future__ import annotations

import json
from pathlib import Path

from nesting_engine.count_pieces import count_extractable_pieces

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "sample_piece.dxf"


def test_counts_pieces_on_pieces_layer() -> None:
    count = count_extractable_pieces([FIXTURE], ["PIECES"])
    assert count >= 1


def test_returns_zero_for_unknown_layer() -> None:
    count = count_extractable_pieces([FIXTURE], ["NO_SUCH_LAYER"])
    assert count == 0
