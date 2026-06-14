import sys
from pathlib import Path
from shapely.geometry import box

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from nesting_engine.nest_libnest2d import nest_sheet

# Test 1: Negative coordinates
pieces1 = [
    box(-4600, -600, -4550, -550),
    box(-3700, -800, -3650, -750),
]
placements1 = nest_sheet(
    pieces1,
    bin_width_mm=200.0,
    bin_height_mm=200.0,
    margin_mm=5.0,
    kerf_mm=2.0,
)
print("TEST 1 (Negative coords):")
for i, (piece, placement) in enumerate(zip(pieces1, placements1)):
    from shapely.affinity import translate
    placed_poly = translate(piece, xoff=placement.x, yoff=placement.y)
    print(f"Piece {i}: placement={placement}, original_bounds={piece.bounds}, placed_bounds={placed_poly.bounds}")

# Test 2: Margin test
pieces2 = [box(0, 0, 10, 10), box(0, 0, 10, 10)]
placements2 = nest_sheet(
    pieces2,
    bin_width_mm=50.0,
    bin_height_mm=50.0,
    margin_mm=5.0,
    kerf_mm=0.0,
)
print("\nTEST 2 (Margin test):")
for i, (piece, placement) in enumerate(zip(pieces2, placements2)):
    from shapely.affinity import translate
    placed_poly = translate(piece, xoff=placement.x, yoff=placement.y)
    print(f"Piece {i}: placement={placement}, original_bounds={piece.bounds}, placed_bounds={placed_poly.bounds}")
