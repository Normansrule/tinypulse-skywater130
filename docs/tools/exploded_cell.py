#!/usr/bin/env python3
"""exploded_cell.py — one real flip-flop, layer by layer, as an animated SVG.

Reads the sky130_fd_sc_hd__dfxtp_1 cell (the D flip-flop the register file is
made of, 480 times) from the SkyWater standard-cell GDS, merges each
manufacturing layer's polygons, and draws them as an isometric stack that
separates and rejoins on a loop.

    python3 docs/tools/exploded_cell.py <sky130_fd_sc_hd dir>  ->  docs/images/flipflop_exploded.svg
"""
import math, sys
import klayout.db as db

CELL = "sky130_fd_sc_hd__dfxtp_1"
LAYERS = [  # (gds layer, name, what it is, colour) bottom to top
    ((64, 20), "N-well",              "where the PMOS transistors sit",         "#3a4a6b"),
    ((65, 20), "Diffusion",           "doped silicon: transistor channels",     "#2a9d5c"),
    ((66, 20), "Polysilicon",         "transistor gates",                       "#d6453d"),
    ((66, 44), "Contacts",            "silicon up to local interconnect",       "#f4f1de"),
    ((67, 20), "Local interconnect",  "wiring inside the cell",                 "#4f8cff"),
    ((67, 44), "Vias",                "local interconnect up to metal 1",       "#ffd23f"),
    ((68, 20), "Metal 1",             "power rails and cell pins",              "#b08cff"),
]
S = 58.0                              # px per micron
COS, SIN = math.cos(math.radians(30)), math.sin(math.radians(30))
GAP_CLOSED, GAP_OPEN = 7, 62          # vertical spacing between layers, px

lib = db.Layout()
lib.read(f"{sys.argv[1]}/gds/sky130_fd_sc_hd.gds")
cell = lib.cell(CELL)
bbox = cell.dbbox()
w_um, h_um = bbox.width(), bbox.height()

def iso(x, y):
    x -= bbox.left; y -= bbox.bottom
    return ((x - y) * COS * S, -(x + y) * SIN * S)

corners = [iso(x, y) for x, y in ((bbox.left, bbox.bottom), (bbox.right, bbox.bottom),
                                  (bbox.right, bbox.top), (bbox.left, bbox.top))]
minx, maxx = min(c[0] for c in corners), max(c[0] for c in corners)
top_extra = GAP_OPEN * (len(LAYERS) - 1)
W = int(maxx - minx + 480); H = int(-min(c[1] for c in corners) + top_extra + 190)
ox, oy = -minx + 40, H - 70

groups, labels, keyframes = [], [], []
for k, ((ln, dt), name, what, col) in enumerate(LAYERS):
    li = lib.find_layer(ln, dt)
    if li is None:
        continue
    region = db.Region(cell.begin_shapes_rec(li)).merged()
    paths = []
    for poly in region.each():
        pts = [iso(p.x * lib.dbu, p.y * lib.dbu) for p in poly.to_simple_polygon().each_point()]
        paths.append("M" + " L".join(f"{x + ox:.1f},{y + oy:.1f}" for x, y in pts) + "Z")
    lift_closed, lift_open = k * GAP_CLOSED, k * GAP_OPEN
    op = "0.55" if k == 0 else "0.9"
    groups.append(f'<g class="L{k}"><path d="{" ".join(paths)}" fill="{col}" fill-opacity="{op}" '
                  f'stroke="{col}" stroke-width="0.6"/></g>')
    keyframes.append(
        f"@keyframes e{k}{{0%,12%{{transform:translateY(-{lift_closed}px)}}"
        f"40%,72%{{transform:translateY(-{lift_open}px)}}100%{{transform:translateY(-{lift_closed}px)}}}}"
        f".L{k}{{animation:e{k} 9s ease-in-out infinite;transform:translateY(-{lift_closed}px)}}")
    lx = maxx - minx + 70
    ly = 130 + (len(LAYERS) - 1 - k) * 58          # evenly spaced, top layer first
    labels.append(f'<g class="T"><line x1="{lx - 26 + ox - 40:.0f}" y1="{ly:.0f}" x2="{lx + ox - 44:.0f}" y2="{ly:.0f}" '
                  f'stroke="{col}" stroke-width="2"/><text x="{lx + ox - 36:.0f}" y="{ly - 2:.0f}" fill="#e9ecef" '
                  f'font-size="15" font-weight="700">{name}</text><text x="{lx + ox - 36:.0f}" y="{ly + 15:.0f}" '
                  f'fill="#8b949e" font-size="12">{what}</text></g>')

css = ("".join(keyframes) +
       "@keyframes t{0%,30%{opacity:0}42%,70%{opacity:1}82%,100%{opacity:0}}.T{animation:t 9s ease-in-out infinite;opacity:0}"
       "@media (prefers-reduced-motion:reduce){" +
       "".join(f".L{k}{{animation:none;transform:translateY(-{k * GAP_OPEN}px)}}" for k in range(len(LAYERS))) +
       ".T{animation:none;opacity:1}}")
svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" '
       f'font-family="Inter,Segoe UI,Helvetica,Arial,sans-serif">'
       f'<title>One sky130 D flip-flop, exploded into its manufacturing layers</title>'
       f'<style>{css}</style><rect width="{W}" height="{H}" rx="16" fill="#0b0e14"/>'
       f'<text x="28" y="40" fill="#e9ecef" font-size="22" font-weight="800">One flip-flop, layer by layer</text>'
       f'<text x="28" y="64" fill="#8b949e" font-size="14">{CELL}: {w_um:.2f} × {h_um:.2f} µm. '
       f'The register file is 480 of these. Real SkyWater GDS geometry.</text>'
       + "".join(groups) + "".join(labels) + "</svg>")
open("docs/images/flipflop_exploded.svg", "w").write(svg)
print(f"docs/images/flipflop_exploded.svg: {CELL} {w_um:.2f} x {h_um:.2f} um, {len(svg) / 1024:.0f} KB")
