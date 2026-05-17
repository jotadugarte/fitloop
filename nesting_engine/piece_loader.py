"""Load extractable piece polygons from config input DXFs."""

from __future__ import annotations

from pathlib import Path

from nesting_engine.extract import extract_closed_contours


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
