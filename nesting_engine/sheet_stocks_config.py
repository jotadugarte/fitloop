# [REQ-FIT-NEST-002] [REQ-FIT-CLI-001] Validate sheet_stocks from nesting CLI config.json.
from __future__ import annotations

from nesting_engine.nest_types import SheetStockSpec


def validate_sheet_stocks(rows: list[dict]) -> None:
    assert isinstance(rows, list), "sheet_stocks must be a list"

    unlimited_rows = [row for row in rows if row.get("quantity") is None]
    if len(unlimited_rows) > 1:
        raise ValueError("at most one unlimited sheet stock is allowed per job")

    if len(unlimited_rows) == 1 and len(rows) > 1:
        unlimited_sort_order = int(unlimited_rows[0]["sort_order"])
        max_sort_order = max(int(row["sort_order"]) for row in rows)
        if unlimited_sort_order != max_sort_order:
            raise ValueError("unlimited sheet stock must have the highest sort_order")


def parse_sheet_stocks_from_config(config: dict) -> list[SheetStockSpec]:
    rows = list(config.get("sheet_stocks") or [])
    validate_sheet_stocks(rows)
    return [
        SheetStockSpec(
            width_mm=float(row["width_mm"]),
            height_mm=float(row["height_mm"]),
            quantity=row["quantity"],
            sort_order=int(row["sort_order"]),
        )
        for row in rows
    ]
