# [REQ-FIT-CLI-001] Validate nesting job numeric parameters from config.json.
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class JobParameters:
    kerf_mm: float
    margin_mm: float
    curve_tolerance_mm: float
    sheet_gap_mm: float
    time_limit_sec: int
    optimization_mode: str
    max_seeds: int
    max_local_search_iterations: int


_VALID_OPTIMIZATION_MODES = frozenset({"fast", "thorough"})


def parse_job_parameters_from_config(config: dict) -> JobParameters:
    assert isinstance(config, dict), "config must be a dict"

    kerf_mm = float(config.get("kerf_mm", 0.0))
    margin_mm = float(config.get("margin_mm", 0.0))
    curve_tolerance_mm = float(config.get("curve_tolerance_mm", 0.1))
    sheet_gap_mm = float(config.get("sheet_gap_mm", 15.0))
    raw_time_limit = float(config.get("time_limit_sec", 600))
    if raw_time_limit != int(raw_time_limit):
        raise ValueError("time_limit_sec must be an integer")
    time_limit_sec = int(raw_time_limit)

    if kerf_mm < 0:
        raise ValueError("kerf_mm must be non-negative")
    if margin_mm < 0:
        raise ValueError("margin_mm must be non-negative")
    if curve_tolerance_mm <= 0:
        raise ValueError("curve_tolerance_mm must be positive")
    if sheet_gap_mm < 0:
        raise ValueError("sheet_gap_mm must be non-negative")
    if time_limit_sec <= 0:
        raise ValueError("time_limit_sec must be positive")

    optimization_mode = str(config.get("optimization_mode", "fast"))
    if optimization_mode not in _VALID_OPTIMIZATION_MODES:
        raise ValueError("optimization_mode must be fast or thorough")
    max_seeds = int(config.get("max_seeds", 16))
    max_local_search_iterations = int(config.get("max_local_search_iterations", 12))
    if max_seeds <= 0:
        raise ValueError("max_seeds must be positive")
    if max_local_search_iterations < 0:
        raise ValueError("max_local_search_iterations must be non-negative")

    return JobParameters(
        kerf_mm=kerf_mm,
        margin_mm=margin_mm,
        curve_tolerance_mm=curve_tolerance_mm,
        sheet_gap_mm=sheet_gap_mm,
        time_limit_sec=time_limit_sec,
        optimization_mode=optimization_mode,
        max_seeds=max_seeds,
        max_local_search_iterations=max_local_search_iterations,
    )
