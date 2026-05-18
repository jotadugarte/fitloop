# [REQ-FIT-NEST-002] [REQ-FIT-CLI-001] CLI config validation for sheet_stocks.
from __future__ import annotations

import pytest

from nesting_engine.sheet_stocks_config import validate_sheet_stocks


def test_validate_sheet_stocks_rejects_two_unlimited_entries() -> None:
    rows = [
        {"width_mm": 1000.0, "height_mm": 2000.0, "quantity": None, "sort_order": 0},
        {"width_mm": 800.0, "height_mm": 1600.0, "quantity": None, "sort_order": 1},
    ]

    with pytest.raises(ValueError, match="at most one unlimited"):
        validate_sheet_stocks(rows)


def test_parse_sheet_stocks_from_config_rejects_two_unlimited_entries() -> None:
    config = {
        "sheet_stocks": [
            {"width_mm": 1000.0, "height_mm": 2000.0, "quantity": None, "sort_order": 0},
            {"width_mm": 800.0, "height_mm": 1600.0, "quantity": None, "sort_order": 1},
        ],
    }

    from nesting_engine.sheet_stocks_config import parse_sheet_stocks_from_config

    with pytest.raises(ValueError, match="at most one unlimited"):
        parse_sheet_stocks_from_config(config)
