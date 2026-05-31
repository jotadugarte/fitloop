# [REQ-FIT-CLI-001] Config job parameter validation.
from __future__ import annotations

import pytest

from nesting_engine.nesting_config import parse_job_parameters_from_config


def test_parse_job_parameters_from_config_defaults():
    params = parse_job_parameters_from_config({})

    assert params.kerf_mm == 0.0
    assert params.margin_mm == 0.0
    assert params.curve_tolerance_mm == 0.1
    assert params.sheet_gap_mm == 15.0
    assert params.time_limit_sec == 600


def test_parse_job_parameters_from_config_rejects_negative_kerf():
    with pytest.raises(ValueError, match="kerf_mm"):
        parse_job_parameters_from_config({"kerf_mm": -0.1})


def test_parse_job_parameters_from_config_rejects_fractional_time_limit():
    with pytest.raises(ValueError, match="integer"):
        parse_job_parameters_from_config({"time_limit_sec": 300.5})


def test_parse_job_parameters_from_config_rejects_non_positive_curve_tolerance():
    with pytest.raises(ValueError, match="curve_tolerance_mm"):
        parse_job_parameters_from_config({"curve_tolerance_mm": 0.0})


def test_parse_job_parameters_from_config_accepts_valid_payload():
    params = parse_job_parameters_from_config(
        {
            "kerf_mm": 2.0,
            "margin_mm": 5.0,
            "curve_tolerance_mm": 0.2,
            "sheet_gap_mm": 10.0,
            "time_limit_sec": 300,
        }
    )

    assert params.kerf_mm == 2.0
    assert params.margin_mm == 5.0
    assert params.curve_tolerance_mm == 0.2
    assert params.sheet_gap_mm == 10.0
    assert params.time_limit_sec == 300
