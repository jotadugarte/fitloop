#!/usr/bin/env python3
"""
diagnose_dxf.py — Visual diagnostics for DXF shape extraction.

Usage (desde la raíz del proyecto):
    # Opción A — con el venv del proyecto (recomendado):
    .venv/bin/python nesting_engine/diagnose_dxf.py <file.dxf>
    .venv/bin/python nesting_engine/diagnose_dxf.py <file.dxf> --primary CORTE

    # Opción B — con python3 del sistema (si tiene las dependencias):
    python3 nesting_engine/diagnose_dxf.py <file.dxf>
    python3 nesting_engine/diagnose_dxf.py <file.dxf> --primary CORTE

    # Opción C — capa + auxiliares:
    .venv/bin/python nesting_engine/diagnose_dxf.py <file.dxf> --primary CORTE --aux GRABADO

    # Opcional
    --out output.png     Ruta del PNG de salida (default: <nombre_dxf>_diag.png)
    --tol 0.1            curve_tolerance_mm (default: 0.1)

Generates a multi-panel PNG:
  [1] RAW DXF      — All entities in the primary layer as stored in the file
  [2] RECOGNIZED   — Polygons the engine extracted (closed contours)
  [3] OPEN SHAPES  — Contours with gaps; gap size annotated in mm
  [4] AUTO-CLOSE <2mm  — Gaps silently closed by the engine (always)
  [5] NEEDS AUTH 2–15mm — Gaps closed only when the user authorises the layer

Thresholds:
  gap < 2 mm    → closed automatically (no user action needed)
  2 ≤ gap ≤ 15  → closed when layer is marked auto_close (user authorisation)
  gap > 15 mm   → contour is ignored / skipped entirely

Also prints a text report: entity counts, polygon count, area, holes, gap analysis.
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import NamedTuple

import ezdxf
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import PathPatch, FancyArrowPatch
from matplotlib.path import Path as MplPath
import numpy as np

# Make sure nesting_engine package is importable when run from its directory
sys.path.insert(0, str(Path(__file__).parent.parent))
from nesting_engine.composite_extract import load_composite_pieces
from ezdxf.path import make_path


# ─── Gap thresholds ──────────────────────────────────────────────────────────
GAP_SILENT_MM  = 2.0   # < this → auto-closed silently
GAP_AUTH_MM    = 15.0  # < this (and ≥ silent) → auto-closed with user auth
# > GAP_AUTH_MM → ignored entirely


# ── Entity type sets for layer heuristics ─────────────────────────────────────
_CONTOUR_TYPES   = {"LWPOLYLINE", "POLYLINE", "CIRCLE", "ELLIPSE", "SPLINE", "ARC"}
_DECORATION_TYPES = {"LINE", "TEXT", "MTEXT", "INSERT", "HATCH", "ATTRIB"}


# ── Palette ──────────────────────────────────────────────────────────────────
COLORS = [
    "#4C9BE8", "#E8724C", "#4CE87A", "#E8D04C", "#A04CE8",
    "#4CE8D4", "#E84CA0", "#8BE84C", "#E8A04C", "#4C4CE8",
]
HOLE_COLOR      = "#FFFFFF"
RAW_LINE_COLOR  = "#2ECC71"
RAW_FILL_COLOR  = "#2ECC71"
BACKGROUND      = "#1A1A2E"
PANEL_BG        = "#16213E"
TEXT_COLOR      = "#E0E0E0"
GRID_COLOR      = "#2A2A4A"

# Gap colours
COL_OPEN      = "#FF4444"   # open contour outline
COL_GAP_MARK  = "#FF6B6B"   # gap endpoint dot
COL_SILENT    = "#44FF99"   # < 2 mm — silent auto-close line
COL_AUTH      = "#FFD700"   # 2–15 mm — needs user auth
COL_IGNORED   = "#888888"   # > 15 mm — ignored


# ─── Gap data structures ──────────────────────────────────────────────────────

class GapInfo(NamedTuple):
    start: tuple[float, float]
    end: tuple[float, float]
    distance_mm: float
    category: str  # "silent" | "auth" | "ignored"


def _classify_gap(dist: float) -> str:
    if dist < GAP_SILENT_MM:
        return "silent"
    if dist <= GAP_AUTH_MM:
        return "auth"
    return "ignored"


def _gap_color(category: str) -> str:
    return {
        "silent":  COL_SILENT,
        "auth":    COL_AUTH,
        "ignored": COL_IGNORED,
    }[category]


# ── Raw DXF rendering ────────────────────────────────────────────────────────

def _draw_raw_dxf(ax, dxf_path: Path, layer_name: str, curve_tolerance: float) -> tuple[dict, list, list]:
    """Draw raw entities from the DXF file onto ax. Returns (stats, all_x, all_y)."""
    doc = ezdxf.readfile(dxf_path)
    stats: dict[str, int] = {}
    all_x, all_y = [], []

    for entity in doc.modelspace():
        if entity.dxf.layer != layer_name:
            continue
        etype = entity.dxftype()
        stats[etype] = stats.get(etype, 0) + 1
        _render_entity(ax, entity, doc, curve_tolerance, all_x, all_y, depth=0)

    return stats, all_x, all_y


def _render_entity(ax, entity, doc, curve_tolerance, all_x, all_y, depth):
    if depth > 8:
        return
    etype = entity.dxftype()

    if etype == "INSERT":
        block = doc.blocks.get(entity.dxf.name)
        if block:
            for sub in block:
                _render_entity(ax, sub, doc, curve_tolerance, all_x, all_y, depth + 1)
        return

    try:
        path = make_path(entity)
        pts = [(float(v.x), float(v.y)) for v in path.flattening(curve_tolerance)]
    except Exception:
        return

    if len(pts) < 2:
        return

    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    all_x.extend(xs)
    all_y.extend(ys)

    if etype == "CIRCLE":
        ax.plot(xs, ys, color=RAW_LINE_COLOR, linewidth=1.2, alpha=0.85)
    elif etype in ("LWPOLYLINE", "POLYLINE"):
        closed = getattr(entity, "closed", False) or getattr(entity, "is_closed", False)
        if closed and xs[0] != xs[-1]:
            xs.append(xs[0])
            ys.append(ys[0])
        ax.plot(xs, ys, color=RAW_LINE_COLOR, linewidth=1.2, alpha=0.85)
    elif etype == "LINE":
        ax.plot(xs, ys, color="#F0A500", linewidth=1.0, alpha=0.85)
    elif etype in ("ARC", "ELLIPSE", "SPLINE"):
        ax.plot(xs, ys, color="#E84CA0", linewidth=1.2, alpha=0.85, linestyle="--")
    else:
        ax.plot(xs, ys, color="#AAAAAA", linewidth=0.8, alpha=0.7)


# ── Polygon rendering ─────────────────────────────────────────────────────────

def _polygon_to_patch(polygon, facecolor, alpha=0.75):
    """Convert a Shapely Polygon (with possible holes) to a matplotlib PathPatch."""
    codes, verts = [], []

    def ring_to_verts(ring):
        coords = list(ring.coords)
        codes.extend([MplPath.MOVETO] + [MplPath.LINETO] * (len(coords) - 2) + [MplPath.CLOSEPOLY])
        verts.extend(coords)

    ring_to_verts(polygon.exterior)
    for interior in polygon.interiors:
        ring_to_verts(interior)

    path = MplPath(verts, codes)
    return PathPatch(path, facecolor=facecolor, edgecolor="white", linewidth=1.5, alpha=alpha)


def _draw_extracted_polygons(ax, polygons, all_x, all_y, decorations_per_poly=None,
                             alpha: float = 0.75):
    """Draw extracted polygons onto ax, including internal decoration lines."""
    for i, polygon in enumerate(polygons):
        color = COLORS[i % len(COLORS)]
        patch = _polygon_to_patch(polygon, facecolor=color, alpha=alpha)
        ax.add_patch(patch)

        # Label each polygon
        cx, cy = polygon.centroid.x, polygon.centroid.y
        ax.text(
            cx, cy, str(i + 1),
            ha="center", va="center",
            fontsize=9, fontweight="bold",
            color="white", zorder=10,
        )

        # Draw internal decoration lines on top of the filled polygon
        if decorations_per_poly and i < len(decorations_per_poly):
            for deco in decorations_per_poly[i]:
                if deco.geometry_type == "line":
                    coords = deco.payload.get("coordinates", [])
                    if len(coords) >= 2:
                        xs = [p[0] for p in coords]
                        ys = [p[1] for p in coords]
                        ax.plot(
                            xs, ys,
                            color="#FFE066", linewidth=1.5, alpha=0.9,
                            linestyle="--", zorder=8,
                        )
                        all_x.extend(xs)
                        all_y.extend(ys)

        # Collect coords for auto-bounds
        ext = list(polygon.exterior.coords)
        all_x.extend(p[0] for p in ext)
        all_y.extend(p[1] for p in ext)


# ── Open-shape gap analysis ───────────────────────────────────────────────────

def _collect_open_entities(dxf_path: Path, layer_name: str, curve_tolerance: float) -> list[GapInfo]:
    """
    Walk every LWPOLYLINE/POLYLINE on the layer and return gap info for those
    that are NOT closed.  Also returns raw point lists for drawing them.
    """
    doc = ezdxf.readfile(dxf_path)
    gaps: list[GapInfo] = []
    for entity in doc.modelspace():
        if entity.dxf.layer != layer_name:
            continue
        etype = entity.dxftype()
        if etype not in ("LWPOLYLINE", "POLYLINE"):
            continue

        is_closed = getattr(entity, "closed", False) or getattr(entity, "is_closed", False)
        if is_closed:
            continue

        try:
            path = make_path(entity)
            pts = [(float(v.x), float(v.y)) for v in path.flattening(curve_tolerance)]
        except Exception:
            continue

        if len(pts) < 2:
            continue

        x0, y0 = pts[0]
        x1, y1 = pts[-1]
        dist = math.hypot(x1 - x0, y1 - y0)
        if dist <= curve_tolerance:
            # Practically closed — skip
            continue

        category = _classify_gap(dist)
        gaps.append(GapInfo(start=(x0, y0), end=(x1, y1), distance_mm=dist, category=category))

    return gaps


def _draw_layer_non_polyline_entities(ax, doc, layer_name: str, curve_tolerance: float,
                                      all_x: list, all_y: list) -> None:
    """
    Draw all non-polyline entities on the layer (LINE, ARC, SPLINE, etc.).
    These are the 'loose lines' / 'pedacidos' that live alongside the main contours.
    """
    for entity in doc.modelspace():
        if entity.dxf.layer != layer_name:
            continue
        etype = entity.dxftype()
        if etype in ("LWPOLYLINE", "POLYLINE", "INSERT", "CIRCLE"):
            continue  # handled separately
        try:
            path = make_path(entity)
            pts = [(float(v.x), float(v.y)) for v in path.flattening(curve_tolerance)]
        except Exception:
            continue
        if len(pts) < 2:
            continue
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        all_x.extend(xs)
        all_y.extend(ys)
        if etype == "LINE":
            ax.plot(xs, ys, color="#FFD700", linewidth=2.0, alpha=0.95, zorder=12)
        else:
            ax.plot(xs, ys, color="#FF69B4", linewidth=1.5, alpha=0.90,
                    linestyle="--", zorder=12)


def _draw_open_shapes(ax, dxf_path: Path, layer_name: str, curve_tolerance: float,
                      gaps: list[GapInfo], all_x: list, all_y: list,
                      show_categories: set[str] | None = None) -> None:
    """
    Draw open polylines in dim colour + highlight their gap endpoints.
    Also draws any loose LINE/ARC entities on the same layer.
    show_categories: if given, only annotate gaps of those categories.
    """
    doc = ezdxf.readfile(dxf_path)

    # Draw all open polyline contours in a muted colour
    for entity in doc.modelspace():
        if entity.dxf.layer != layer_name:
            continue
        etype = entity.dxftype()
        if etype not in ("LWPOLYLINE", "POLYLINE"):
            continue
        is_closed = getattr(entity, "closed", False) or getattr(entity, "is_closed", False)
        if is_closed:
            continue

        try:
            path = make_path(entity)
            pts = [(float(v.x), float(v.y)) for v in path.flattening(curve_tolerance)]
        except Exception:
            continue

        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        all_x.extend(xs)
        all_y.extend(ys)
        ax.plot(xs, ys, color="#7EC8E3", linewidth=1.2, alpha=0.8, linestyle="-")

    # Also draw loose LINE / ARC / etc. entities that live on the same layer
    _draw_layer_non_polyline_entities(ax, doc, layer_name, curve_tolerance, all_x, all_y)

    # Overlay gap markers and labels
    for g in gaps:
        if show_categories is not None and g.category not in show_categories:
            continue
        col = _gap_color(g.category)
        sx, sy = g.start
        ex, ey = g.end
        all_x.extend([sx, ex])
        all_y.extend([sy, ey])
        # Connecting line
        ax.plot([sx, ex], [sy, ey], color=col, linewidth=2.0, alpha=0.95,
                linestyle="--", zorder=6)
        # Endpoint dots
        ax.plot([sx, ex], [sy, ey], "o", color=col, markersize=7, zorder=7)
        # Label in the middle
        mx, my = (sx + ex) / 2, (sy + ey) / 2
        ax.annotate(
            f"{g.distance_mm:.1f}mm",
            xy=(mx, my),
            fontsize=7, color=col, fontweight="bold", zorder=9,
            ha="center",
            bbox=dict(boxstyle="round,pad=0.2", facecolor=BACKGROUND, edgecolor=col,
                      linewidth=0.8, alpha=0.85),
        )


def _draw_close_line(ax, g: GapInfo) -> None:
    """Draw the proposed closing segment for a gap."""
    col = _gap_color(g.category)
    sx, sy = g.start
    ex, ey = g.end
    ax.annotate(
        "",
        xy=(ex, ey), xytext=(sx, sy),
        arrowprops=dict(
            arrowstyle="-|>", color=col, lw=2.0,
            connectionstyle="arc3,rad=0.0",
        ),
        zorder=8,
    )
    ax.plot([sx, ex], [sy, ey], color=col, linewidth=2.5, linestyle="-", alpha=0.95, zorder=7)
    ax.plot([sx, ex], [sy, ey], "o", color=col, markersize=8, zorder=8)
    mx, my = (sx + ex) / 2, (sy + ey) / 2
    ax.annotate(
        f"✔ {g.distance_mm:.1f}mm",
        xy=(mx, my),
        fontsize=7, color=col, fontweight="bold", zorder=10,
        ha="center",
        bbox=dict(boxstyle="round,pad=0.2", facecolor=BACKGROUND, edgecolor=col,
                  linewidth=0.8, alpha=0.90),
    )


# ── Layout helpers ────────────────────────────────────────────────────────────

def _set_ax_bounds(ax, all_x, all_y, margin_frac=0.08):
    if not all_x or not all_y:
        return
    xmin, xmax = min(all_x), max(all_x)
    ymin, ymax = min(all_y), max(all_y)
    w = max(xmax - xmin, 1)
    h = max(ymax - ymin, 1)
    margin = max(w, h) * margin_frac
    ax.set_xlim(xmin - margin, xmax + margin)
    ax.set_ylim(ymin - margin, ymax + margin)
    ax.set_aspect("equal")


def _style_ax(ax, title, subtitle: str = "", title_color: str | None = None):
    ax.set_facecolor(PANEL_BG)
    ax.tick_params(colors=TEXT_COLOR, labelsize=7)
    ax.spines[:].set_color(GRID_COLOR)
    ax.grid(True, color=GRID_COLOR, linewidth=0.5, alpha=0.5)
    full = title if not subtitle else f"{title}\n{subtitle}"
    ax.set_title(full, color=title_color or TEXT_COLOR, fontsize=10, fontweight="bold", pad=6)
    ax.set_xlabel("X (mm)", color=TEXT_COLOR, fontsize=7)
    ax.set_ylabel("Y (mm)", color=TEXT_COLOR, fontsize=7)


# ── Extraction ────────────────────────────────────────────────────────────────

def run_extraction(dxf_path, primary_layer, aux_layers, tol, warnings,
                   auto_close_gaps: bool = False, use_image_extraction: bool = True):
    """
    Run the engine extraction.
    Returns (polygons, mode, decorations_per_poly).
    """
    from nesting_engine.extract import extract_pieces_with_internal_lines

    if aux_layers:
        pieces = load_composite_pieces(
            dxf_path,
            primary_layer=primary_layer,
            auxiliary_layers=aux_layers,
            curve_tolerance_mm=tol,
            warnings=warnings,
            auto_close_gaps=auto_close_gaps,
            use_image_extraction=use_image_extraction,
        )
        polygons = [p.polygon for p in pieces]
        decorations_per_poly = [p.decorations for p in pieces]
        mode = f"COMPOSITE  (primary='{primary_layer}', aux={aux_layers})"
    else:
        pieces = extract_pieces_with_internal_lines(
            dxf_path,
            layer_name=primary_layer,
            curve_tolerance_mm=tol,
            warnings=warnings,
            auto_close_gaps=auto_close_gaps,
            use_image_extraction=use_image_extraction,
        )
        polygons = [p.polygon for p in pieces]
        decorations_per_poly = [p.decorations for p in pieces]
        mode = f"FLAT  (primary='{primary_layer}', sin auxiliares)"
    return polygons, mode, decorations_per_poly


# ── Legend helpers ────────────────────────────────────────────────────────────

def _add_raw_legend(ax):
    handles = [
        mpatches.Patch(color=RAW_LINE_COLOR, label="LWPOLYLINE / POLYLINE / CIRCLE"),
        mpatches.Patch(color="#F0A500", label="LINE"),
        mpatches.Patch(color="#E84CA0", label="ARC / ELLIPSE / SPLINE"),
        mpatches.Patch(color="#AAAAAA", label="Other"),
    ]
    ax.legend(handles=handles, loc="upper right", fontsize=6,
              facecolor=BACKGROUND, edgecolor=GRID_COLOR, labelcolor=TEXT_COLOR)


def _add_poly_legend(ax, polygons, has_internal_lines=False):
    handles = []
    for i, poly in enumerate(polygons):
        holes = len(list(poly.interiors))
        label = f"Poly {i+1}  area={poly.area:.0f}mm²"
        if holes:
            label += f"  ({holes} hole{'s' if holes > 1 else ''})"
        handles.append(mpatches.Patch(color=COLORS[i % len(COLORS)], label=label))
    if has_internal_lines:
        handles.append(
            mpatches.Patch(
                color="#FFE066", label="Internal cut lines (in output DXF)",
                linestyle="--", fill=False,
            )
        )
    ax.legend(handles=handles, loc="upper right", fontsize=6,
              facecolor=BACKGROUND, edgecolor=GRID_COLOR, labelcolor=TEXT_COLOR)


def _add_gap_legend(ax, gaps: list[GapInfo], title: str = ""):
    counts = {"silent": 0, "auth": 0, "ignored": 0}
    for g in gaps:
        counts[g.category] += 1
    handles = [
        mpatches.Patch(color="#7EC8E3", label="Open contour"),
        mpatches.Patch(color=COL_SILENT, label=f"Gap <{GAP_SILENT_MM}mm — auto (silent) [{counts['silent']}]"),
        mpatches.Patch(color=COL_AUTH,   label=f"Gap {GAP_SILENT_MM}–{GAP_AUTH_MM}mm — needs auth [{counts['auth']}]"),
        mpatches.Patch(color=COL_IGNORED,label=f"Gap >{GAP_AUTH_MM}mm — ignored [{counts['ignored']}]"),
    ]
    ax.legend(handles=handles, loc="upper right", fontsize=6,
              facecolor=BACKGROUND, edgecolor=GRID_COLOR, labelcolor=TEXT_COLOR, title=title,
              title_fontsize=6)


def _add_close_legend(ax, category: str, gaps: list[GapInfo]):
    col = _gap_color(category)
    n = len([g for g in gaps if g.category == category])
    handles = [
        mpatches.Patch(color="#7EC8E3", label="Open contour"),
        mpatches.Patch(color=col, label=f"Closing segment ({n} gap{'s' if n != 1 else ''})"),
    ]
    ax.legend(handles=handles, loc="upper right", fontsize=6,
              facecolor=BACKGROUND, edgecolor=GRID_COLOR, labelcolor=TEXT_COLOR)


# ── Layer analysis ───────────────────────────────────────────────────────────

def _analyze_layers(dxf_path: Path) -> dict[str, dict]:
    doc = ezdxf.readfile(dxf_path)
    layers: dict[str, dict] = {}
    for entity in doc.modelspace():
        layer = entity.dxf.layer
        etype = entity.dxftype()
        if layer not in layers:
            layers[layer] = {}
        layers[layer][etype] = layers[layer].get(etype, 0) + 1
    return layers


def _recommend_layers(layer_stats: dict[str, dict]) -> tuple[str | None, list[str]]:
    primary_scores: dict[str, int] = {}
    auxiliary_candidates: list[str] = []

    for layer, counts in layer_stats.items():
        contour_count = sum(counts.get(t, 0) for t in _CONTOUR_TYPES)
        deco_count = sum(counts.get(t, 0) for t in _DECORATION_TYPES)
        total = contour_count + deco_count
        if total == 0:
            continue
        contour_ratio = contour_count / total if total > 0 else 0
        if contour_ratio >= 0.6 and contour_count > 0:
            primary_scores[layer] = contour_count
        elif deco_count > 0:
            auxiliary_candidates.append(layer)

    primary = max(primary_scores, key=lambda k: primary_scores[k]) if primary_scores else None
    auxiliaries = [l for l in auxiliary_candidates if l != primary]
    return primary, auxiliaries


def _print_layer_analysis(layer_stats, primary, auxiliaries):
    print()
    print("=" * 60)
    print("  LAYER ANALYSIS")
    print("=" * 60)
    print()
    for layer, counts in sorted(layer_stats.items()):
        contour_count = sum(counts.get(t, 0) for t in _CONTOUR_TYPES)
        deco_count = sum(counts.get(t, 0) for t in _DECORATION_TYPES)
        marker = ""
        if layer == primary:
            marker = "  ◄── PRIMARY (contornos de corte)"
        elif layer in auxiliaries:
            marker = "  ◄── AUXILIARY (decoraciones internas)"
        print(f"  Layer: '{layer}'{marker}")
        for etype, count in sorted(counts.items()):
            tag = "[contorno]"
            if etype in _DECORATION_TYPES:
                tag = "[decoración]"
            elif etype not in _CONTOUR_TYPES:
                tag = "[otro]"
            print(f"    {etype:<20} × {count}  {tag}")
        print(f"    → contornos:{contour_count}  decoraciones:{deco_count}")
        print()

    print("📌 RECOMENDACIÓN:")
    if primary:
        print(f"   primary_layer   = '{primary}'")
    else:
        print("   primary_layer   = (ninguno claro — revisar manualmente)")
    if auxiliaries:
        for a in auxiliaries:
            print(f"   auxiliary_layer = '{a}'")
    else:
        print("   auxiliary_layers = (ninguno — modo flat)")
    print()


# ── Text report ───────────────────────────────────────────────────────────────

def _print_report(dxf_path, mode, raw_stats, polygons, gaps: list[GapInfo], warnings, cluster_count=None):
    print()
    print("=" * 60)
    print("  DXF EXTRACTION REPORT")
    print(f"  File : {dxf_path.name}")
    print(f"  Mode : {mode}")
    if cluster_count is not None:
        print(f"  Clusters : {cluster_count} local rasterization canvases")
    print("=" * 60)

    print("\n✎ RAW ENTITIES (primary layer):")
    if raw_stats:
        for etype, count in sorted(raw_stats.items()):
            print(f"   {etype:<20} × {count}")
    else:
        print("   (none found — check layer name!)")

    print(f"\n🔷 EXTRACTED POLYGONS: {len(polygons)}")
    for i, poly in enumerate(polygons):
        holes = len(list(poly.interiors))
        print(
            f"   [{i+1}] area={poly.area:.2f} mm²  "
            f"bbox=({poly.bounds[0]:.1f},{poly.bounds[1]:.1f})→"
            f"({poly.bounds[2]:.1f},{poly.bounds[3]:.1f})  "
            f"holes={holes}  valid={poly.is_valid}"
        )

    # Gap analysis
    silent_gaps  = [g for g in gaps if g.category == "silent"]
    auth_gaps    = [g for g in gaps if g.category == "auth"]
    ignored_gaps = [g for g in gaps if g.category == "ignored"]

    print(f"\n⚠️  OPEN CONTOURS / GAPS: {len(gaps)} total")
    if silent_gaps:
        print(f"\n  ✅ AUTO-CLOSED (< {GAP_SILENT_MM}mm) — {len(silent_gaps)} gap(s), closed silently:")
        for g in silent_gaps:
            print(f"     • {g.distance_mm:.3f}mm  {g.start} → {g.end}")
    else:
        print(f"\n  ✅ No gaps < {GAP_SILENT_MM}mm")

    if auth_gaps:
        print(f"\n  🔑 NEEDS USER AUTHORISATION ({GAP_SILENT_MM}–{GAP_AUTH_MM}mm) — {len(auth_gaps)} gap(s):")
        for g in auth_gaps:
            print(f"     • {g.distance_mm:.3f}mm  {g.start} → {g.end}")
    else:
        print(f"\n  🔑 No gaps in the {GAP_SILENT_MM}–{GAP_AUTH_MM}mm range")

    if ignored_gaps:
        print(f"\n  ❌ IGNORED (> {GAP_AUTH_MM}mm) — {len(ignored_gaps)} contour(s) skipped entirely:")
        for g in ignored_gaps:
            print(f"     • {g.distance_mm:.3f}mm  {g.start} → {g.end}")
    else:
        print(f"\n  ❌ No gaps > {GAP_AUTH_MM}mm")

    if warnings:
        print(f"\n⚠️  ENGINE WARNINGS ({len(warnings)}):")
        for w in warnings:
            print(f"   • {w}")

    print()


# ── Figure construction ───────────────────────────────────────────────────────

def _build_figure(dxf_path: Path, args, raw_stats, raw_x, raw_y,
                  legacy_polygons, legacy_decorations,
                  image_polygons, image_decorations,
                  gaps: list[GapInfo],
                  nesting_polygons=None, nesting_decorations=None):
    """
    Create the multi-panel PNG.
    Shows only the RAW DXF and the final shape output sent to the nesting engine.
    """
    nesting_polygons    = nesting_polygons    or []
    nesting_decorations = nesting_decorations or []

    ncols = 2
    fig_w = 7 * ncols
    fig, axes = plt.subplots(1, ncols, figsize=(fig_w, 9), facecolor=BACKGROUND)

    fig.suptitle(
        f"{dxf_path.name}  ·  tol: {args.tol} mm",
        color=TEXT_COLOR, fontsize=12, fontweight="bold", y=0.99,
    )

    ax_raw  = axes[0]   # ① RAW DXF
    ax_nest = axes[1]   # ② MOTOR DE ANIDADO

    # ── ① RAW DXF ────────────────────────────────────────────────────────────
    _, rraw_x, rraw_y = _draw_raw_dxf(ax_raw, dxf_path, args.primary, args.tol)
    _style_ax(ax_raw, f"① RAW DXF", f"layer: '{args.primary}'")
    _set_ax_bounds(ax_raw, rraw_x, rraw_y)
    _add_raw_legend(ax_raw)

    # ── ② MOTOR DE ANIDADO ───────────────────────────────────────────────────
    nest_x, nest_y = [], []
    _draw_extracted_polygons(ax_nest, nesting_polygons, nest_x, nest_y,
                             nesting_decorations, alpha=0.70)
    _doc_nest = ezdxf.readfile(dxf_path)
    _draw_layer_non_polyline_entities(ax_nest, _doc_nest, args.primary, args.tol, nest_x, nest_y)

    from nesting_engine.image_extract import _cluster_entities
    clusters = _cluster_entities(_doc_nest, args.primary, args.tol)
    for cluster_idx, (entities, bounds) in enumerate(clusters):
        rect = mpatches.Rectangle(
            (bounds.min_x, bounds.min_y),
            bounds.width,
            bounds.height,
            linewidth=1.0,
            edgecolor="#4CE87A",
            facecolor="none",
            linestyle="--",
            alpha=0.6,
            zorder=2,
        )
        ax_nest.add_patch(rect)
        ax_nest.text(
            bounds.min_x + 2, bounds.max_y - 8,
            f"C{cluster_idx+1}",
            color="#4CE87A", fontsize=6, alpha=0.8,
            zorder=3
        )

    n_nest = len(nesting_polygons)
    _style_ax(ax_nest,
              "🔧 MOTOR DE ANIDADO (OUTPUT FINAL)",
              f"{n_nest} forma{'s' if n_nest != 1 else ''} → va al anidado",
              title_color="#00E5FF")
    if nest_x and nest_y:
        _set_ax_bounds(ax_nest, nest_x, nest_y)
    elif rraw_x and rraw_y:
        _set_ax_bounds(ax_nest, rraw_x, rraw_y)
    _add_poly_legend(
        ax_nest, nesting_polygons,
        has_internal_lines=any(
            any(d.geometry_type == "line" for d in decos)
            for decos in nesting_decorations
        ),
    )
    if not nesting_polygons:
        ax_nest.text(
            0.5, 0.5, "❌ Sin formas reconocidas\n(no se puede anidar)",
            transform=ax_nest.transAxes,
            ha="center", va="center", fontsize=12,
            color="#FF4444", alpha=0.85,
        )
    # Add prominent border to highlight this is the key panel
    for spine in ax_nest.spines.values():
        spine.set_edgecolor("#00E5FF")
        spine.set_linewidth(2.5)

    plt.tight_layout(rect=[0, 0, 1, 0.97])
    return fig


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Visualize DXF shape extraction — gap analysis & auto-close preview"
    )
    parser.add_argument("dxf", help="Path to the DXF file")
    parser.add_argument(
        "--primary", default=None, metavar="LAYER",
        help="Primary layer name (contornos de corte). If omitted, only layer analysis is shown.",
    )
    parser.add_argument(
        "--aux", action="append", default=[], metavar="LAYER",
        help="Auxiliary layer(s) (decoraciones internas). Repeat: --aux GRABADO --aux TEXTO",
    )
    parser.add_argument("--out", default=None, help="Output PNG path (default: <dxf_name>_diag.png)")
    parser.add_argument("--tol", type=float, default=0.1, help="curve_tolerance_mm (default: 0.1)")
    args = parser.parse_args()

    dxf_path = Path(args.dxf).resolve()
    if not dxf_path.is_file():
        print(f"ERROR: File not found: {dxf_path}")
        sys.exit(1)

    # ── Always: analyze layers and print recommendation ────────────────────
    layer_stats = _analyze_layers(dxf_path)
    primary_rec, aux_rec = _recommend_layers(layer_stats)
    _print_layer_analysis(layer_stats, primary_rec, aux_rec)

    if not args.primary:
        print("ℹ️  Declara la capa principal con --primary NOMBRE_LAYER para ver el diagnóstico visual.")
        if primary_rec:
            print(f"   Sugerencia del auto-análisis: --primary '{primary_rec}'", end="")
            if aux_rec:
                print(" " + " ".join(f"--aux '{a}'" for a in aux_rec), end="")
            print()
        return

    # ── Gap analysis ────────────────────────────────────────────────────────
    gaps = _collect_open_entities(dxf_path, args.primary, args.tol)

    # ── Extraction: legacy entity-based without auto_close ──────────────────
    warnings_legacy: list[str] = []
    legacy_polygons, legacy_mode, legacy_decorations = run_extraction(
        dxf_path, args.primary, args.aux, args.tol, warnings_legacy, auto_close_gaps=False, use_image_extraction=False
    )

    # ── Extraction: new image-based without auto_close ──────────────────────
    warnings_image: list[str] = []
    image_polygons, image_mode, image_decorations = run_extraction(
        dxf_path, args.primary, args.aux, args.tol, warnings_image, auto_close_gaps=False, use_image_extraction=True
    )

    # ── Extraction: new image-based with auto_close=True (what the nesting engine ACTUALLY uses) ──
    warnings_nest: list[str] = []
    nesting_polygons, _, nesting_decorations = run_extraction(
        dxf_path, args.primary, args.aux, args.tol, warnings_nest, auto_close_gaps=True, use_image_extraction=True
    )

    out_path = Path(args.out) if args.out else dxf_path.with_name(dxf_path.stem + "_diag.png")

    # Raw stats (for report)
    raw_stats, raw_x, raw_y = _draw_raw_dxf(
        plt.figure().add_subplot(111),  # scratch axes — not saved
        dxf_path, args.primary, args.tol
    )
    plt.close()

    # ── Build multi-panel figure ────────────────────────────────────────────
    fig = _build_figure(dxf_path, args, raw_stats, raw_x, raw_y,
                        legacy_polygons, legacy_decorations,
                        image_polygons, image_decorations, gaps,
                        nesting_polygons=nesting_polygons,
                        nesting_decorations=nesting_decorations)
    fig.savefig(out_path, dpi=150, bbox_inches="tight", facecolor=BACKGROUND)
    plt.close(fig)

    # ── Text report ─────────────────────────────────────────────────────────
    from nesting_engine.image_extract import _cluster_entities
    doc = ezdxf.readfile(dxf_path)
    clusters = _cluster_entities(doc, args.primary, args.tol)
    cluster_count = len(clusters)

    _print_report(dxf_path, image_mode, raw_stats, image_polygons, gaps, warnings_image, cluster_count=cluster_count)
    print(f"✅  Image saved → {out_path}")


if __name__ == "__main__":
    main()
