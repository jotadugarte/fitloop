"""Tests for DXF layer name and color discovery."""

from __future__ import annotations

from pathlib import Path

import pytest

from nesting_engine.read_layers import (
    filter_gaps_resolved_by_extraction,
    gap_is_ignored,
    gap_needs_authorization,
    layer_catalog,
    layer_gaps_for_composite_file,
    layer_gaps_for_file,
    union_layer_names,
)

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
    assert gap_needs_authorization(1.5) is False
    assert gap_needs_authorization(14.8) is True
    assert gap_is_ignored(75.0) is True


@pytest.mark.slow
def test_layer_gaps_for_composite_file_filters_008_absorbed_micro_gaps() -> None:
    """[REQ-FIT-DXF-002] 008 crossbar end caps stitch in extraction; raw gaps are false positives."""
    dxf_008 = Path(__file__).resolve().parent / "fixtures" / "individuals" / "008.dxf"
    raw_gaps = layer_gaps_for_file(dxf_008, "CORTE")
    assert any(2.0 < gap["distance_mm"] <= 15.0 for gap in raw_gaps)

    filtered = layer_gaps_for_composite_file(dxf_008, "CORTE")
    auth_gaps = [gap for gap in filtered if gap_needs_authorization(gap["distance_mm"])]
    assert auth_gaps == []


@pytest.mark.slow
def test_layer_gaps_for_composite_file_keeps_015_real_open_gap() -> None:
    """[REQ-FIT-DXF-002] Genuine orphan open contours must survive composite filtering."""
    dxf_015 = Path(__file__).resolve().parent / "fixtures" / "individuals" / "015.dxf"
    filtered = layer_gaps_for_composite_file(dxf_015, "CORTE")
    assert any(gap["distance_mm"] > 10.0 for gap in filtered)
