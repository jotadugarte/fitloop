#!/usr/bin/env python3
"""
diagnose_dxf.py — Visual diagnostics for DXF shape extraction.

Usage:
    # Step 1 — Analyze layers only (no extraction)
    python diagnose_dxf.py <file.dxf>

    # Step 2 — Extract with explicit layer declaration
    python diagnose_dxf.py <file.dxf> --primary LAYER_NAME
    python diagnose_dxf.py <file.dxf> --primary CORTE --aux GRABADO --aux TEXTO

    # Optional
    --out output.png     Override output PNG path
    --tol 0.1            curve_tolerance_mm (default: 0.1)

Generates a side-by-side PNG:
  LEFT  — Raw DXF entities drawn as-is on the primary layer (what’s in the file)
  RIGHT — Extracted polygons from the engine (what we recognized)

Also prints a text report: entity counts, polygon count, area, holes, warnings.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import ezdxf
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import PathPatch
from matplotlib.path import Path as MplPath
import numpy as np

# Make sure nesting_engine package is importable when run from its directory
sys.path.insert(0, str(Path(__file__).parent.parent))
from nesting_engine.composite_extract import load_composite_pieces
from ezdxf.path import make_path


# ── Entity type sets for layer heuristics ─────────────────────────────────────
# Types that typically carry closed contours (primary layer candidates)
_CONTOUR_TYPES = {"LWPOLYLINE", "POLYLINE", "CIRCLE", "ELLIPSE", "SPLINE", "ARC"}
# Types that typically carry decorations (auxiliary layer candidates)
_DECORATION_TYPES = {"LINE", "TEXT", "MTEXT", "INSERT", "HATCH", "ATTRIB"}


# ── Palette ──────────────────────────────────────────────────────────────────
COLORS = [
    "#4C9BE8", "#E8724C", "#4CE87A", "#E8D04C", "#A04CE8",
    "#4CE8D4", "#E84CA0", "#8BE84C", "#E8A04C", "#4C4CE8",
]
HOLE_COLOR = "#FFFFFF"
RAW_LINE_COLOR = "#2ECC71"
RAW_FILL_COLOR = "#2ECC71"
BACKGROUND = "#1A1A2E"
PANEL_BG = "#16213E"
TEXT_COLOR = "#E0E0E0"
GRID_COLOR = "#2A2A4A"


# ── Raw DXF rendering ────────────────────────────────────────────────────────

def _draw_raw_dxf(ax, dxf_path: Path, layer_name: str, curve_tolerance: float) -> dict:
    """Draw raw entities from the DXF file onto ax. Returns a stats dict."""
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
            m = entity.matrix44()
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


def _draw_extracted_polygons(ax, polygons, all_x, all_y, decorations_per_poly=None):
    """Draw extracted polygons onto ax, including internal decoration lines."""
    for i, polygon in enumerate(polygons):
        color = COLORS[i % len(COLORS)]
        patch = _polygon_to_patch(polygon, facecolor=color)
        ax.add_patch(patch)

        # Label each polygon
        cx, cy = polygon.centroid.x, polygon.centroid.y
        ax.text(
            cx, cy, str(i + 1),
            ha="center", va="center",
            fontsize=9, fontweight="bold",
            color="white",
            zorder=10,
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


# ── Layout helpers ────────────────────────────────────────────────────────────

def _set_ax_bounds(ax, all_x, all_y, margin_frac=0.05):
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


def _style_ax(ax, title):
    ax.set_facecolor(PANEL_BG)
    ax.tick_params(colors=TEXT_COLOR, labelsize=7)
    ax.spines[:].set_color(GRID_COLOR)
    ax.grid(True, color=GRID_COLOR, linewidth=0.5, alpha=0.5)
    ax.set_title(title, color=TEXT_COLOR, fontsize=11, fontweight="bold", pad=8)
    ax.set_xlabel("X (mm)", color=TEXT_COLOR, fontsize=8)
    ax.set_ylabel("Y (mm)", color=TEXT_COLOR, fontsize=8)


# ── Extraction ────────────────────────────────────────────────────────────────────

def run_extraction(dxf_path, primary_layer, aux_layers, tol, warnings):
    """Run the correct engine path based on layer config.
    Returns (polygons, mode, decorations_per_poly).
    decorations_per_poly: list[list[dict]] — one entry per polygon.
    """
    from nesting_engine.extract import extract_pieces_with_internal_lines

    if aux_layers:
        # Composite mode: primary contours + auxiliary decorations
        pieces = load_composite_pieces(
            dxf_path,
            primary_layer=primary_layer,
            auxiliary_layers=aux_layers,
            curve_tolerance_mm=tol,
            warnings=warnings,
        )
        polygons = [p.polygon for p in pieces]
        decorations_per_poly = [p.decorations for p in pieces]
        mode = f"COMPOSITE  (primary='{primary_layer}', aux={aux_layers})"
    else:
        # Flat mode: use extract_pieces_with_internal_lines to preserve inner cut lines
        pieces = extract_pieces_with_internal_lines(
            dxf_path,
            layer_name=primary_layer,
            curve_tolerance_mm=tol,
            warnings=warnings,
        )
        polygons = [p.polygon for p in pieces]
        decorations_per_poly = [p.decorations for p in pieces]
        mode = f"FLAT  (primary='{primary_layer}', sin auxiliares)"
    return polygons, mode, decorations_per_poly


# ── Text report ───────────────────────────────────────────────────────────────

def _print_report(dxf_path, mode, raw_stats, polygons, warnings):
    print()
    print("=" * 60)
    print(f"  DXF EXTRACTION REPORT")
    print(f"  File : {dxf_path.name}")
    print(f"  Mode : {mode}")
    print("=" * 60)

    print(f"\n\u2712 RAW ENTITIES (primary layer):")
    if raw_stats:
        for etype, count in sorted(raw_stats.items()):
            print(f"   {etype:<20} \u00d7 {count}")
    else:
        print("   (none found — check layer name!)")

    print(f"\n\U0001f537 EXTRACTED POLYGONS: {len(polygons)}")
    for i, poly in enumerate(polygons):
        holes = len(list(poly.interiors))
        print(
            f"   [{i+1}] area={poly.area:.2f} mm\u00b2  "
            f"bbox=({poly.bounds[0]:.1f},{poly.bounds[1]:.1f})\u2192"
            f"({poly.bounds[2]:.1f},{poly.bounds[3]:.1f})  "
            f"holes={holes}  valid={poly.is_valid}"
        )

    if warnings:
        print(f"\n\u26a0\ufe0f  WARNINGS ({len(warnings)}):")
        for w in warnings:
            print(f"   \u2022 {w}")

    print()


# ── Legend ────────────────────────────────────────────────────────────────────

def _add_raw_legend(ax):
    handles = [
        mpatches.Patch(color=RAW_LINE_COLOR, label="LWPOLYLINE / POLYLINE / CIRCLE"),
        mpatches.Patch(color="#F0A500", label="LINE"),
        mpatches.Patch(color="#E84CA0", label="ARC / ELLIPSE / SPLINE"),
        mpatches.Patch(color="#AAAAAA", label="Other"),
    ]
    ax.legend(handles=handles, loc="upper right", fontsize=7,
              facecolor=BACKGROUND, edgecolor=GRID_COLOR, labelcolor=TEXT_COLOR)


def _add_poly_legend(ax, polygons, has_internal_lines=False):
    handles = []
    for i, poly in enumerate(polygons):
        holes = len(list(poly.interiors))
        label = f"Poly {i+1}  area={poly.area:.0f}mm²"
        if holes:
            label += f"  ({holes} hole{'s' if holes>1 else ''})"
        handles.append(mpatches.Patch(color=COLORS[i % len(COLORS)], label=label))
    if has_internal_lines:
        handles.append(
            mpatches.Patch(
                color="#FFE066", label="Internal cut lines (preserved in output DXF)",
                linestyle="--", fill=False,
            )
        )
    ax.legend(handles=handles, loc="upper right", fontsize=7,
              facecolor=BACKGROUND, edgecolor=GRID_COLOR, labelcolor=TEXT_COLOR)


# ── Layer analysis ───────────────────────────────────────────────────────────

def _analyze_layers(dxf_path: Path) -> dict[str, dict]:
    """Return {layer_name: {entity_type: count, ...}} for all entities in modelspace."""
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
    """Heuristically suggest primary and auxiliary layers."""
    primary_scores: dict[str, int] = {}
    auxiliary_candidates: list[str] = []

    for layer, counts in layer_stats.items():
        contour_count = sum(counts.get(t, 0) for t in _CONTOUR_TYPES)
        deco_count = sum(counts.get(t, 0) for t in _DECORATION_TYPES)
        total = contour_count + deco_count

        if total == 0:
            continue

        contour_ratio = contour_count / total if total > 0 else 0
        # A good primary layer has mostly closed-contour entities
        if contour_ratio >= 0.6 and contour_count > 0:
            primary_scores[layer] = contour_count
        elif deco_count > 0:
            auxiliary_candidates.append(layer)

    primary = max(primary_scores, key=lambda k: primary_scores[k]) if primary_scores else None
    # Remove primary from auxiliary candidates
    auxiliaries = [l for l in auxiliary_candidates if l != primary]
    return primary, auxiliaries


def _print_layer_analysis(layer_stats: dict[str, dict], primary: str | None, auxiliaries: list[str]) -> None:
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


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Visualize DXF shape extraction (contour recognition only)"
    )
    parser.add_argument("dxf", help="Path to the DXF file")
    parser.add_argument(
        "--primary", default=None, metavar="LAYER",
        help="Primary layer name (contornos de corte). If omitted, only layer analysis is shown."
    )
    parser.add_argument(
        "--aux", action="append", default=[], metavar="LAYER",
        help="Auxiliary layer(s) (decoraciones internas). Repeat for multiple: --aux GRABADO --aux TEXTO"
    )
    parser.add_argument("--out", default=None, help="Output PNG path (default: <dxf_name>_diag.png)")
    parser.add_argument("--tol", type=float, default=0.1, help="curve_tolerance_mm (default: 0.1)")
    args = parser.parse_args()

    dxf_path = Path(args.dxf).resolve()
    if not dxf_path.is_file():
        print(f"ERROR: File not found: {dxf_path}")
        sys.exit(1)

    # ── Always: analyze layers and print recommendation ────────────────────────
    layer_stats = _analyze_layers(dxf_path)
    primary_rec, aux_rec = _recommend_layers(layer_stats)
    _print_layer_analysis(layer_stats, primary_rec, aux_rec)

    if not args.primary:
        print("\u2139\ufe0f  Declara la capa principal con --primary NOMBRE_LAYER para ver el diagnóstico visual.")
        if primary_rec:
            print(f"   Sugerencia del auto-análisis: --primary '{primary_rec}'", end="")
            if aux_rec:
                print(" " + " ".join(f"--aux '{a}'" for a in aux_rec), end="")
            print()
        return

    # ── Run extraction with the declared layers ──────────────────────────────────
    warnings: list[str] = []
    polygons, mode, decorations_per_poly = run_extraction(dxf_path, args.primary, args.aux, args.tol, warnings)

    out_path = Path(args.out) if args.out else dxf_path.with_name(dxf_path.stem + "_diag.png")

    # ── Figure ───────────────────────────────────────────────────────────────
    fig, (ax_raw, ax_ext) = plt.subplots(
        1, 2, figsize=(16, 8), facecolor=BACKGROUND
    )
    fig.suptitle(
        f"{dxf_path.name}  ·  {mode}  ·  tol: {args.tol} mm",
        color=TEXT_COLOR, fontsize=11, fontweight="bold", y=0.98,
    )

    # ── LEFT: raw DXF (primary layer) ────────────────────────────────────────
    raw_x, raw_y = [], []
    raw_stats, raw_x, raw_y = _draw_raw_dxf(ax_raw, dxf_path, args.primary, args.tol)
    _style_ax(ax_raw, f"① RAW DXF  (primary layer: '{args.primary}')")
    _set_ax_bounds(ax_raw, raw_x, raw_y)
    _add_raw_legend(ax_raw)

    # ── RIGHT: extracted polygons ─────────────────────────────────────────────
    ext_x, ext_y = [], []
    _draw_extracted_polygons(ax_ext, polygons, ext_x, ext_y, decorations_per_poly=decorations_per_poly)
    n = len(polygons)
    _style_ax(ax_ext, f"② EXTRACTED  ({n} polygon{'s' if n != 1 else ''} recognized)")
    if ext_x and ext_y:
        _set_ax_bounds(ax_ext, ext_x, ext_y)
    elif raw_x and raw_y:
        _set_ax_bounds(ax_ext, raw_x, raw_y)
    _add_poly_legend(
        ax_ext, polygons,
        has_internal_lines=any(
            any(d.geometry_type == "line" for d in decos)
            for decos in decorations_per_poly
        ),
    )

    plt.tight_layout(rect=[0, 0, 1, 0.96])
    plt.savefig(out_path, dpi=150, bbox_inches="tight", facecolor=BACKGROUND)
    plt.close()

    # ── Text report ───────────────────────────────────────────────────────────
    _print_report(dxf_path, mode, raw_stats, polygons, warnings)
    print(f"✅  Image saved → {out_path}")


if __name__ == "__main__":
    main()
