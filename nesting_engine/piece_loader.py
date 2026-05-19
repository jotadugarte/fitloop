"""Load extractable piece polygons from config input DXFs."""

from __future__ import annotations

from pathlib import Path

from shapely.geometry import Polygon

from nesting_engine.composite_extract import CompositePiece, load_composite_pieces
from nesting_engine.extract import extract_closed_contours
from nesting_engine.nest_placement import Placement
from nesting_engine.nest_types import PlacedPiece


def load_pieces(
    input_dxf_paths: list[str],
    included_layers: list[str],
    *,
    curve_tolerance_mm: float,
    warnings: list[str],
) -> list:
    assert curve_tolerance_mm > 0, "curve_tolerance_mm must be positive"

    pieces: list = []
    for path_str in input_dxf_paths:
        path = Path(path_str)
        for layer_name in included_layers:
            contours = extract_closed_contours(
                path,
                layer_name,
                curve_tolerance_mm=curve_tolerance_mm,
                warnings=warnings,
            )
            pieces.extend(contours)

    assert isinstance(pieces, list)
    return pieces


def load_pieces_from_config(config: dict, *, warnings: list[str]) -> list:
    curve_tolerance_mm = float(config.get("curve_tolerance_mm", 0.1))
    input_files = config.get("input_files")
    if input_files:
        pieces = _pieces_from_input_files(
            input_files,
            curve_tolerance_mm=curve_tolerance_mm,
            warnings=warnings,
        )
    else:
        pieces = load_pieces(
            config.get("input_dxf_paths", []),
            config.get("included_layers", []),
            curve_tolerance_mm=curve_tolerance_mm,
            warnings=warnings,
        )

    pieces = _without_excluded_pieces(pieces, config)
    pieces.extend(_derived_pieces_from_config(config))
    return pieces


def piece_polygon(piece: Polygon | CompositePiece) -> Polygon:
    if isinstance(piece, CompositePiece):
        return piece.polygon
    return piece


def placed_piece_from_source(
    piece_index: int,
    piece: Polygon | CompositePiece,
    placement: Placement,
) -> PlacedPiece:
    polygon = piece_polygon(piece)
    if isinstance(piece, CompositePiece):
        return PlacedPiece(
            piece_index=piece_index,
            polygon=polygon,
            placement=placement,
            primary_layer_name=piece.primary_layer_name,
            decorations=tuple(piece.decorations),
        )
    return PlacedPiece(piece_index=piece_index, polygon=polygon, placement=placement)


def _pieces_from_input_files(
    input_files: list[dict],
    *,
    curve_tolerance_mm: float,
    warnings: list[str],
) -> list:
    pieces: list = []
    for entry in input_files:
        path = Path(entry["path"])
        primary_layer = entry.get("primary_layer")
        if primary_layer:
            auxiliary_layers = list(entry.get("auxiliary_layers") or [])
            composite_pieces = load_composite_pieces(
                path,
                primary_layer=str(primary_layer),
                auxiliary_layers=auxiliary_layers,
                curve_tolerance_mm=curve_tolerance_mm,
                warnings=warnings,
            )
            pieces.extend(composite_pieces)
            continue

        for layer_name in entry.get("included_layers", []):
            contours = extract_closed_contours(
                path,
                layer_name,
                curve_tolerance_mm=curve_tolerance_mm,
                warnings=warnings,
            )
            pieces.extend(contours)

    return pieces


def _without_excluded_pieces(pieces: list, config: dict) -> list:
    excluded = {str(key) for key in config.get("excluded_piece_keys") or []}
    if not excluded:
        return pieces

    return [piece for index, piece in enumerate(pieces) if str(index) not in excluded]


def _derived_pieces_from_config(config: dict) -> list:
    derived: list = []
    for entry in config.get("derived_pieces") or []:
        rings = entry.get("rings") or []
        if not rings:
            continue
        exterior = rings[0]
        holes = rings[1:] if len(rings) > 1 else []
        polygon = Polygon(exterior, holes)
        if not polygon.is_empty:
            derived.append(polygon)
    return derived
