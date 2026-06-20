# [REQ-FIT-JOB-001] ThoroughEtaEstimator: rolling-window ETA for thorough nesting mode.
from __future__ import annotations

import pytest

from nesting_engine.nest_pipeline import ThoroughEtaEstimator


def test_eta_is_none_before_first_record() -> None:
    est = ThoroughEtaEstimator(total_iterations=5)
    assert est.eta_sec() is None


def test_eta_is_int_after_first_record() -> None:
    est = ThoroughEtaEstimator(total_iterations=5)
    est.record_iteration(10.0)  # 10s per iter, 4 remaining → 40s
    result = est.eta_sec()
    assert isinstance(result, int)
    assert result == 40


def test_eta_decreases_with_equal_spacing() -> None:
    est = ThoroughEtaEstimator(total_iterations=4)
    # After iter 1: avg=10s, remaining=3 → 30s
    est.record_iteration(10.0)
    eta1 = est.eta_sec()
    # After iter 2: avg=10s, remaining=2 → 20s
    est.record_iteration(10.0)
    eta2 = est.eta_sec()
    # After iter 3: avg=10s, remaining=1 → 10s
    est.record_iteration(10.0)
    eta3 = est.eta_sec()

    assert eta1 > eta2 > eta3 >= 0


def test_eta_is_zero_after_all_iterations() -> None:
    est = ThoroughEtaEstimator(total_iterations=2)
    est.record_iteration(5.0)
    est.record_iteration(5.0)
    assert est.eta_sec() == 0


def test_eta_uses_rolling_window_of_last_three() -> None:
    # Outlier first iteration (100s); next two iterations are 1s each.
    # Rolling window should suppress the outlier once 3 samples fill in.
    est = ThoroughEtaEstimator(total_iterations=6)
    est.record_iteration(100.0)  # window: [100]
    est.record_iteration(1.0)    # window: [100, 1]
    est.record_iteration(1.0)    # window: [100, 1, 1] → avg=34
    est.record_iteration(1.0)    # window: [1, 1, 1]   → avg=1, remaining=2 → eta=2
    eta = est.eta_sec()
    # Once the outlier falls out of the window, ETA is much smaller
    assert eta <= 5  # sanity: rolling window evicted the 100s outlier


def test_eta_never_negative() -> None:
    # total_iterations=1, already recorded 1 → 0 remaining
    est = ThoroughEtaEstimator(total_iterations=1)
    est.record_iteration(30.0)
    assert est.eta_sec() == 0
