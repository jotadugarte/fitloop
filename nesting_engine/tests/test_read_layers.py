"""Tests for DXF layer name and color discovery."""

from __future__ import annotations

from pathlib import Path

from nesting_engine.read_layers import layer_catalog, layer_gaps_for_file, union_layer_names

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "sample_piece.dxf"


def test_union_includes_pieces_layer() -> None:
    names = union_layer_names([FIXTURE])
    assert "PIECES" in names


def test_catalog_includes_hex_color() -> None:
    catalog = layer_catalog([FIXTURE])
    pieces = next(entry for entry in catalog if entry["name"] == "PIECES")
    assert pieces["color"].startswith("#")
    assert len(pieces["color"]) == 7


def test_catalog_omits_gap_scan_at_sync() -> None:
    dxf_006 = Path(__file__).resolve().parent / "fixtures" / "individuals" / "006.dxf"
    catalog = layer_catalog([dxf_006])
    corte = next(entry for entry in catalog if entry["name"] == "CORTE")
    assert corte["gaps"] == []


def test_layer_gaps_for_file_detects_open_contours_on_demand() -> None:
    dxf_015 = Path(__file__).resolve().parent / "fixtures" / "individuals" / "015.dxf"
    corte_gaps = layer_gaps_for_file(dxf_015, "CORTE")
    marcado_gaps = layer_gaps_for_file(dxf_015, "MARCADO")
    assert corte_gaps
    assert any(gap["distance_mm"] > 10.0 for gap in corte_gaps)
    assert marcado_gaps
    assert max(gap["distance_mm"] for gap in marcado_gaps) > 15.0


def test_gap_needs_authorization_matches_diagnose_thresholds() -> None:
    from nesting_engine.read_layers import gap_needs_authorization

    assert gap_needs_authorization(1.5) is False
    assert gap_needs_authorization(14.8) is True
    assert gap_needs_authorization(15.0) is True
    assert gap_needs_authorization(75.0) is False
