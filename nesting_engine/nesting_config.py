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

    return JobParameters(
        kerf_mm=kerf_mm,
        margin_mm=margin_mm,
        curve_tolerance_mm=curve_tolerance_mm,
        sheet_gap_mm=sheet_gap_mm,
        time_limit_sec=time_limit_sec,
    )
