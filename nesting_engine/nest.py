# [REQ-FIT-NEST-002] Nesting CLI: read config.json, write nested.dxf + placements.json + report.json.
from __future__ import annotations

import json
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent.parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from shapely.affinity import rotate, translate  # noqa: E402
from shapely.geometry import Polygon  # noqa: E402

from nesting_engine.dxf_output import write_nested_dxf  # noqa: E402
from nesting_engine.nest_bin import MultiBinResult, PlacedPiece, nest_multi_bin  # noqa: E402
from nesting_engine.piece_loader import load_pieces_from_config, piece_polygon  # noqa: E402
from nesting_engine.sheet_stocks_config import parse_sheet_stocks_from_config  # noqa: E402
from nesting_engine.composite_extract import (  # noqa: E402
    CompositePiece,
    DecorationEntity,
    partition_decorations,
)
from nesting_engine.decoration_transform import transform_decorations  # noqa: E402
from nesting_engine.split_planner import SplitPlanResult, plan_split  # noqa: E402
from nesting_engine.nesting_config import parse_job_parameters_from_config  # noqa: E402
from nesting_engine.nest_geometry_classify import (  # noqa: E402
    is_axis_aligned_on_sheet,
    is_orthogonal_for_cardinal_nesting,
)
from nesting_engine.nest_libnest2d import multi_bin_layout_has_significant_overlaps  # noqa: E402
from nesting_engine.progress_reporter import ProgressReporter  # noqa: E402

_PLAN_SPLITS_MODE = "plan_splits"
_MAX_PLAN_PIECES = 128


def _piece_bounds_dict(polygon: Polygon, *, piece_index: int, extra: dict | None = None) -> dict:
    minx, miny, maxx, maxy = polygon.bounds
    payload = {
        "piece_index": piece_index,
        "width_mm": float(maxx - minx),
        "height_mm": float(maxy - miny),
        "offset_x_mm": float(minx),
        "offset_y_mm": float(miny),
        "rings": _polygon_rings(polygon),
    }
    if extra:
        payload.update(extra)
    return payload


def _piece_placement_dict(placed: PlacedPiece, *, label: str | None = None) -> dict:
    world = _placed_world_polygon(placed)
    export_placement = placed.placement
    report_rotation_deg = placed.placement.rotation_deg
    if is_orthogonal_for_cardinal_nesting(placed.polygon):
        from nesting_engine.nest_libnest2d import (  # noqa: PLC0415
            _prepare_solver_piece,
            _restore_placement_to_source,
        )

        export_placement = _restore_placement_to_source(
            placed.polygon,
            placed.polygon,
            placed.placement,
            world_geometry=world,
        )
        prep = _prepare_solver_piece(placed.polygon)
        if prep.pre_align_deg is not None and abs(prep.pre_align_deg) > 1e-9:
            report_rotation_deg = (export_placement.rotation_deg + prep.pre_align_deg) % 360.0
        else:
            report_rotation_deg = export_placement.rotation_deg
        world = _placed_world_polygon(
            PlacedPiece(
                piece_index=placed.piece_index,
                polygon=placed.polygon,
                placement=export_placement,
                primary_layer_name=placed.primary_layer_name,
                decorations=placed.decorations,
            )
        )
    minx, miny, maxx, maxy = world.bounds
    orthogonal_export = is_orthogonal_for_cardinal_nesting(placed.polygon)
    payload = {
        "piece_index": placed.piece_index,
        "x_mm": float(minx),
        "y_mm": float(miny),
        "rotation_deg": report_rotation_deg,
        "width_mm": float(maxx - minx),
        "height_mm": float(maxy - miny),
        "rings": _polygon_rings(world, allow_simplify=not orthogonal_export),
    }
    if placed.primary_layer_name:
        payload["primary_layer_name"] = placed.primary_layer_name
    if placed.decorations:
        transformed = transform_decorations(
            list(placed.decorations),
            placed.polygon,
            export_placement,
        )
        payload["decorations"] = [_decoration_entity_dict(row) for row in transformed]
    if label:
        payload["label"] = label
    return payload


def _derived_piece_labels(config: dict, *, piece_count: int) -> dict[int, str]:
    derived = list(config.get("derived_pieces") or [])
    if not derived:
        return {}

    base_index = piece_count - len(derived)
    labels: dict[int, str] = {}
    for offset, entry in enumerate(derived):
        label = entry.get("label")
        if label:
            labels[base_index + offset] = str(label)
    return labels


def _orphan_piece_dict(orphan, polygon: Polygon) -> dict:
    return _piece_bounds_dict(
        polygon,
        piece_index=orphan.piece_index,
        extra={"reason": orphan.reason},
    )


def _placed_world_polygon(placed: PlacedPiece) -> Polygon:
    rotated = rotate(placed.polygon, placed.placement.rotation_deg, origin="centroid")
    return translate(rotated, xoff=placed.placement.x, yoff=placed.placement.y)


def _polygon_rings(
    polygon: Polygon,
    *,
    simplify_tolerance_mm: float = 0.5,
    allow_simplify: bool = True,
) -> list[list[list[float]]]:
    geometry = polygon
    # [REQ-FIT-NEST-002] Douglas-Peucker on dense orthogonal contours chamfers step vertices
    # and makes the preview SVG look tilted (~11°) even when rotation_deg is cardinal.
    if (
        allow_simplify
        and simplify_tolerance_mm > 0
        and len(polygon.exterior.coords) > 120
        and not is_axis_aligned_on_sheet(polygon)
    ):
        simplified = polygon.simplify(simplify_tolerance_mm, preserve_topology=True)
        if isinstance(simplified, Polygon) and not simplified.is_empty:
            geometry = simplified

    rings: list[list[list[float]]] = [_ring_coords(geometry.exterior)]
    rings.extend(_ring_coords(interior) for interior in geometry.interiors)
    return rings


def _ring_coords(linear_ring) -> list[list[float]]:
    return [
        [round(float(x), 3), round(float(y), 3)]
        for x, y in linear_ring.coords[:-1]
    ]


def run_from_config(config: dict) -> MultiBinResult | dict:
    if config.get("mode") == _PLAN_SPLITS_MODE:
        return run_plan_splits_from_config(config)

    output_dir = Path(config["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)
    progress = ProgressReporter(output_dir / "progress.json")
    job_params = parse_job_parameters_from_config(config)

    warnings: list[str] = list(config.get("warnings") or [])
    pieces = load_pieces_from_config(config, warnings=warnings)
    progress.report("extracting", 10, pieces_total=len(pieces))

    stocks = parse_sheet_stocks_from_config(config)

    if not pieces:
        report = {"status": "failed", "orphans": [], "warnings": warnings + ["no_extractable_pieces"]}
        progress.report("writing_outputs", 99)
        _write_outputs(
            output_dir,
            MultiBinResult(sheets=[], orphans=[], warnings=warnings),
            report,
            pieces=[],
            config=config,
        )
        return MultiBinResult(sheets=[], orphans=[], warnings=warnings)

    result = nest_multi_bin(
        pieces,
        stocks,
        margin_mm=job_params.margin_mm,
        kerf_mm=job_params.kerf_mm,
        sheet_gap_mm=job_params.sheet_gap_mm,
        time_limit_sec=job_params.time_limit_sec,
        progress_reporter=progress,
    )
    merged_warnings = warnings + list(result.warnings)
    result = MultiBinResult(
        sheets=result.sheets,
        orphans=result.orphans,
        warnings=merged_warnings,
    )

    if multi_bin_layout_has_significant_overlaps(
        result.sheets,
        pieces,
        kerf_mm=job_params.kerf_mm,
    ):
        merged_warnings.append("layout_overlap_detected")
        result = MultiBinResult(sheets=[], orphans=result.orphans, warnings=merged_warnings)
        report = {
            "status": "failed",
            "orphans": [{"piece_index": o.piece_index, "reason": o.reason} for o in result.orphans],
            "warnings": merged_warnings,
        }
        progress.report("writing_outputs", 96, pieces_total=len(pieces))
        (output_dir / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        progress.report("writing_outputs", 99, pieces_total=len(pieces))
        return result

    status = "completed" if not result.orphans else "partial"
    report = {
        "status": status,
        "orphans": [{"piece_index": o.piece_index, "reason": o.reason} for o in result.orphans],
        "warnings": merged_warnings,
    }
    progress.report("writing_outputs", 96, pieces_total=len(pieces))
    _write_outputs(output_dir, result, report, pieces=pieces, config=config)
    progress.report("writing_outputs", 99, pieces_total=len(pieces))
    return result


def run_plan_splits_from_config(config: dict) -> dict:
    """[REQ-FIT-SPLIT-001] Plan straight-cut splits; writes split_preview.json only."""
    output_dir = Path(config["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)

    warnings: list[str] = list(config.get("warnings") or [])
    pieces = load_pieces_from_config(config, warnings=warnings)
    stocks = parse_sheet_stocks_from_config(config)
    job_params = parse_job_parameters_from_config(config)
    margin_mm = job_params.margin_mm

    proposals: list[dict] = []
    plan_by_key = _plan_polygons_by_key(config)
    piece_keys = list(config.get("piece_keys") or [])[:_MAX_PLAN_PIECES]
    for piece_key in piece_keys:
        proposals.append(
            _plan_split_for_key(
                piece_key,
                pieces,
                stocks,
                margin_mm=margin_mm,
                plan_by_key=plan_by_key,
                config=config,
            )
        )

    preview = {"proposals": proposals, "warnings": warnings}
    (output_dir / "split_preview.json").write_text(json.dumps(preview, indent=2), encoding="utf-8")
    return preview


def _plan_polygons_by_key(config: dict) -> dict[str, Polygon]:
    """Orphan geometry from placements (plan_pieces); avoids wrong piece after index shifts."""
    polygons: dict[str, Polygon] = {}
    for entry in config.get("plan_pieces") or []:
        key = str(entry.get("piece_key", "")).strip()
        polygon = _polygon_from_plan_piece_entry(entry)
        if key and polygon is not None:
            polygons[key] = polygon
    return polygons


def _polygon_from_plan_piece_entry(entry: dict) -> Polygon | None:
    rings = entry.get("rings") or []
    if not rings:
        return None
    exterior = rings[0]
    holes = rings[1:] if len(rings) > 1 else []
    polygon = Polygon(exterior, holes)
    if polygon.is_empty:
        return None
    return polygon


def _composite_mother_for_plan_piece(
    piece_key: str,
    polygon: Polygon,
    pieces: list,
    config: dict,
) -> CompositePiece | None:
    for entry in config.get("plan_pieces") or []:
        if str(entry.get("piece_key", "")).strip() != piece_key:
            continue
        decorations = _decorations_from_plan_piece_entry(entry)
        if decorations:
            primary_layer = str(entry.get("primary_layer_name") or "")
            return CompositePiece(
                polygon=polygon,
                decorations=decorations,
                primary_layer_name=primary_layer,
            )

    index = _piece_index_from_key(piece_key)
    if index is None or index < 0 or index >= len(pieces):
        return None
    source = pieces[index]
    if not isinstance(source, CompositePiece) or not source.decorations:
        return None
    return CompositePiece(
        polygon=polygon,
        decorations=list(source.decorations),
        piece_index=index,
        primary_layer_name=source.primary_layer_name,
    )


def _decorations_from_plan_piece_entry(entry: dict) -> list[DecorationEntity]:
    decorations: list[DecorationEntity] = []
    for row in entry.get("decorations") or []:
        layer_name = row.get("layer_name")
        geometry_type = row.get("geometry_type")
        payload = row.get("payload")
        if not layer_name or not geometry_type or not isinstance(payload, dict):
            continue
        decorations.append(
            DecorationEntity(
                layer_name=str(layer_name),
                geometry_type=str(geometry_type),
                payload=dict(payload),
            )
        )
    return decorations


def _plan_split_for_key(
    piece_key: str,
    pieces: list,
    stocks: list,
    *,
    margin_mm: float,
    plan_by_key: dict[str, Polygon] | None = None,
    config: dict | None = None,
) -> dict:
    key = str(piece_key)
    plan_by_key = plan_by_key or {}
    config = config or {}
    if key in plan_by_key:
        polygon = plan_by_key[key]
        mother = _composite_mother_for_plan_piece(key, polygon, pieces, config)
        result = plan_split(polygon, stocks, margin_mm=margin_mm)
        composite_children = None
        if mother is not None and result.feasible:
            composite_children = partition_decorations(
                mother,
                result.children,
                result.cut_segments,
            )
        return _split_proposal_dict(key, result, composite_children=composite_children)

    index = _piece_index_from_key(piece_key)
    if index is None or index < 0 or index >= len(pieces):
        return _split_proposal_dict(piece_key, SplitPlanResult(False, "split_not_feasible", [], []))

    source = pieces[index]
    polygon = source.polygon if isinstance(source, CompositePiece) else source
    result = plan_split(polygon, stocks, margin_mm=margin_mm)
    composite_children = None
    if isinstance(source, CompositePiece) and result.feasible:
        composite_children = partition_decorations(
            source,
            result.children,
            result.cut_segments,
        )
    return _split_proposal_dict(piece_key, result, composite_children=composite_children)


def _piece_index_from_key(piece_key: str) -> int | None:
    text = str(piece_key).strip()
    if not text.isdigit():
        return None
    return int(text)


def _split_proposal_dict(
    piece_key: str,
    result: SplitPlanResult,
    *,
    composite_children: list[CompositePiece] | None = None,
) -> dict:
    children_payload: list[dict] = []
    for index, child in enumerate(result.children):
        entry: dict = {
            "label": child.label,
            "rings": _polygon_rings(child.polygon),
        }
        if composite_children is not None and index < len(composite_children):
            entry["decorations"] = [
                _decoration_entity_dict(decoration)
                for decoration in composite_children[index].decorations
            ]
        children_payload.append(entry)

    return {
        "piece_key": piece_key,
        "feasible": result.feasible,
        "reason": result.reason,
        "children": children_payload,
        "cut_segments": [
            [[float(start[0]), float(start[1])], [float(end[0]), float(end[1])]]
            for start, end in result.cut_segments
        ],
    }


def _decoration_entity_dict(decoration) -> dict:
    return {
        "layer_name": decoration.layer_name,
        "geometry_type": decoration.geometry_type,
        "payload": decoration.payload,
    }


def _write_outputs(
    output_dir: Path,
    result: MultiBinResult,
    report: dict,
    *,
    pieces: list,
    config: dict,
) -> None:
    piece_labels = _derived_piece_labels(config, piece_count=len(pieces))
    cut_segments = list(config.get("split_cut_segments") or [])
    if piece_labels or cut_segments:
        report["split"] = {
            "derived_labels": [piece_labels[index] for index in sorted(piece_labels)],
            "cut_segment_count": len(cut_segments),
        }

    # Manufacturing DXF: sheet outlines + piece contours only (no split cut guides or labels).
    write_nested_dxf(output_dir / "nested.dxf", result.sheets)
    placements = {
        "sheets": [
            {
                "stock_sort_order": sheet.stock_sort_order,
                "sheet_index": sheet.sheet_index,
                "width_mm": sheet.width_mm,
                "height_mm": sheet.height_mm,
                "offset_x_mm": sheet.offset_x_mm,
                "pieces": [
                    _piece_placement_dict(placed, label=piece_labels.get(placed.piece_index))
                    for placed in sheet.pieces
                ],
            }
            for sheet in result.sheets
        ],
        "orphans": [
            _orphan_piece_dict(orphan, piece_polygon(pieces[orphan.piece_index]))
            for orphan in result.orphans
        ],
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
    try:
        run_from_config(config)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
