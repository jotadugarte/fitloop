# [REQ-FIT-NEST-002] Nesting CLI: read config.json, write nested.dxf + placements.json + report.json.
from __future__ import annotations

import json
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent.parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from shapely.affinity import rotate  # noqa: E402

from nesting_engine.dxf_output import write_nested_dxf  # noqa: E402
from nesting_engine.nest_bin import MultiBinResult, PlacedPiece, SheetStockSpec, nest_multi_bin  # noqa: E402
from nesting_engine.piece_loader import load_pieces  # noqa: E402


def _piece_placement_dict(placed: PlacedPiece) -> dict:
    rotated = rotate(placed.polygon, placed.placement.rotation_deg, origin="centroid")
    minx, miny, maxx, maxy = rotated.bounds
    return {
        "piece_index": placed.piece_index,
        "x_mm": placed.placement.x,
        "y_mm": placed.placement.y,
        "rotation_deg": placed.placement.rotation_deg,
        "width_mm": float(maxx - minx),
        "height_mm": float(maxy - miny),
    }


def run_from_config(config: dict) -> MultiBinResult:
    output_dir = Path(config["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)

    warnings: list[str] = list(config.get("warnings") or [])
    pieces = load_pieces(
        config.get("input_dxf_paths", []),
        config.get("included_layers", []),
        curve_tolerance_mm=float(config.get("curve_tolerance_mm", 0.1)),
        warnings=warnings,
    )

    stocks = [
        SheetStockSpec(
            width_mm=float(row["width_mm"]),
            height_mm=float(row["height_mm"]),
            quantity=row["quantity"],
            sort_order=int(row["sort_order"]),
        )
        for row in config.get("sheet_stocks", [])
    ]

    if not pieces:
        report = {"status": "failed", "orphans": [], "warnings": warnings + ["no_extractable_pieces"]}
        _write_outputs(output_dir, MultiBinResult(sheets=[], orphans=[], warnings=warnings), report)
        return MultiBinResult(sheets=[], orphans=[], warnings=warnings)

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=float(config.get("margin_mm", 0.0)),
        kerf_mm=float(config.get("kerf_mm", 0.0)),
        sheet_gap_mm=float(config.get("sheet_gap_mm", 15.0)),
    )
    merged_warnings = warnings + list(result.warnings)
    result = MultiBinResult(
        sheets=result.sheets,
        orphans=result.orphans,
        warnings=merged_warnings,
    )

    status = "completed" if not result.orphans else "partial"
    report = {
        "status": status,
        "orphans": [{"piece_index": o.piece_index, "reason": o.reason} for o in result.orphans],
        "warnings": merged_warnings,
    }
    _write_outputs(output_dir, result, report)
    return result


def _write_outputs(output_dir: Path, result: MultiBinResult, report: dict) -> None:
    write_nested_dxf(output_dir / "nested.dxf", result.sheets)
    placements = {
        "sheets": [
            {
                "stock_sort_order": sheet.stock_sort_order,
                "sheet_index": sheet.sheet_index,
                "width_mm": sheet.width_mm,
                "height_mm": sheet.height_mm,
                "offset_x_mm": sheet.offset_x_mm,
                "pieces": [_piece_placement_dict(placed) for placed in sheet.pieces],
            }
            for sheet in result.sheets
        ],
        "orphans": report.get("orphans", []),
    }
    (output_dir / "placements.json").write_text(json.dumps(placements, indent=2), encoding="utf-8")
    (output_dir / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    if len(argv) != 1:
        print("usage: nest.py CONFIG_JSON_PATH", file=sys.stderr)
        return 1

    config_path = Path(argv[0])
    config = json.loads(config_path.read_text(encoding="utf-8"))
    run_from_config(config)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
