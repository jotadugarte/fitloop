import sys
from pathlib import Path
from shapely.geometry import Polygon

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from nesting_engine.extract import extract_pieces_with_internal_lines

files = ["001.dxf", "002.dxf", "003.dxf", "005.dxf", "006.dxf"]
fixtures_dir = Path(__file__).resolve().parent / "tests" / "fixtures" / "individuals"

for filename in files:
    path = fixtures_dir / filename
    pieces = extract_pieces_with_internal_lines(
        path,
        "CORTE",
        curve_tolerance_mm=0.25,
        auto_close_gaps=True,
        use_image_extraction=True
    )
    print(f"\n=== {filename} ===")
    print(f"Extracted {len(pieces)} pieces:")
    for i, p in enumerate(pieces):
        poly = p.polygon
        print(f"  [{i}] centroid=({poly.centroid.x:.2f}, {poly.centroid.y:.2f}) area={poly.area:.2f} bounds={poly.bounds}")
        print(f"      decorations: {len(p.decorations)}")
        for j, d in enumerate(p.decorations):
            coords = d.payload.get("coordinates", [])
            print(f"        deco[{j}]: {d.geometry_type} on layer {d.layer_name} with {len(coords)} coords")
            if coords:
                # Calculate bounding box of coordinates
                xs = [pt[0] for pt in coords]
                ys = [pt[1] for pt in coords]
                print(f"                  bounds: ({min(xs):.2f}, {min(ys):.2f}) -> ({max(xs):.2f}, {max(ys):.2f})")
