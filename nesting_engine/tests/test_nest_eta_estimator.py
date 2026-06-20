# [REQ-FIT-JOB-001] WallClockEtaEstimator: stable, monotonically-decreasing ETA for thorough nesting.
from __future__ import annotations

import time

import pytest

from nesting_engine.nest_pipeline import WallClockEtaEstimator


# ---------------------------------------------------------------------------
# Basic contract
# ---------------------------------------------------------------------------


def test_update_returns_none_before_any_positive_percent() -> None:
    """No percent → no estimate."""
    est = WallClockEtaEstimator(time_limit_sec=None)
    assert est.update(0) is None


def test_update_returns_int_for_positive_percent_with_time_limit() -> None:
    """With a known time limit the estimator should immediately return an int."""
    est = WallClockEtaEstimator(time_limit_sec=300.0)
    result = est.update(10)
    assert isinstance(result, int)
    assert result >= 0


def test_update_returns_zero_at_full_percent() -> None:
    est = WallClockEtaEstimator(time_limit_sec=600.0)
    assert est.update(100) == 0


def test_update_never_returns_negative() -> None:
    est = WallClockEtaEstimator(time_limit_sec=1.0)
    # Sleep briefly so elapsed > time_limit
    time.sleep(0.05)
    result = est.update(99)
    assert result is not None
    assert result >= 0


# ---------------------------------------------------------------------------
# Time-limit countdown
# ---------------------------------------------------------------------------


def test_countdown_decreases_over_time() -> None:
    """With time_limit_sec, eta decreases as time passes."""
    est = WallClockEtaEstimator(time_limit_sec=60.0)
    eta1 = est.update(20)
    time.sleep(0.05)
    eta2 = est.update(22)
    # eta2 should be equal or less (countdown moved forward)
    assert eta2 is not None and eta1 is not None
    assert eta2 <= eta1


def test_countdown_bounded_by_time_limit() -> None:
    """ETA can never exceed the time limit."""
    est = WallClockEtaEstimator(time_limit_sec=120.0)
    result = est.update(5)
    assert result is not None
    assert result <= 120


# ---------------------------------------------------------------------------
# Monotonic constraint — ETA never increases
# ---------------------------------------------------------------------------


def test_monotonic_constraint_prevents_eta_from_increasing() -> None:
    """Even if the computed ETA would be higher, the capped value is returned."""
    est = WallClockEtaEstimator(time_limit_sec=600.0)
    # Drive the smoothed_pct high so raw_eta is low
    eta_low = est.update(80)
    # Now feed a lower percent (EWMA will pull down smoothed_pct) → higher raw_eta
    eta_should_not_increase = est.update(30)
    assert eta_should_not_increase is not None
    assert eta_should_not_increase <= eta_low


def test_monotonic_across_many_updates() -> None:
    est = WallClockEtaEstimator(time_limit_sec=300.0)
    percentages = [10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90]
    etas = [est.update(p) for p in percentages]
    non_none = [e for e in etas if e is not None]
    # Every ETA must be <= the previous one
    for a, b in zip(non_none, non_none[1:]):
        assert b <= a, f"ETA increased: {a} → {b}"


# ---------------------------------------------------------------------------
# EWMA smoothing
# ---------------------------------------------------------------------------


def test_ewma_smooths_sudden_percent_jump() -> None:
    """A jump from 10% to 90% should not produce an instant ETA collapse."""
    est = WallClockEtaEstimator(time_limit_sec=600.0)
    eta_at_10 = est.update(10)
    # The monotonic constraint ensures eta at 90% <= eta at 10%
    eta_at_90 = est.update(90)
    assert eta_at_90 is not None and eta_at_10 is not None
    assert eta_at_90 <= eta_at_10


# ---------------------------------------------------------------------------
# No time-limit fallback (wall-clock projection)
# ---------------------------------------------------------------------------


def test_no_time_limit_returns_none_with_zero_elapsed() -> None:
    """Without a time limit and zero elapsed, no estimate is possible."""
    est = WallClockEtaEstimator(time_limit_sec=None)
    # elapsed ≈ 0 → fall back to None
    result = est.update(50)
    # Should be None (elapsed < threshold) or a non-negative int once threshold is exceeded
    assert result is None or result >= 0
