#!/usr/bin/env python3
"""animations.py — the animated explanatory diagrams in docs/images.

All CSS-animated SVG, so GitHub plays them inline in the README, and all
respect prefers-reduced-motion. Run from the repo root.
"""
BG, CARD, FG, DIM, RULE = "#0b0e14", "#161b22", "#e9ecef", "#8b949e", "#30363d"
LI, MET, POLY, DIFF, GOLD = "#4f8cff", "#b08cff", "#e5534b", "#3ddc97", "#ffd23f"
FONT = "font-family='Inter,Segoe UI,Helvetica,Arial,sans-serif'"
MONO = "font-family='JetBrains Mono,SFMono-Regular,Consolas,monospace'"

def svg(w, h, title, css, body):
    return (f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 {w} {h}' {FONT}><title>{title}</title>"
            f"<style>{css}@media (prefers-reduced-motion:reduce){{*{{animation:none!important}}}}</style>"
            f"<rect width='{w}' height='{h}' rx='16' fill='{BG}'/>{body}</svg>")

# ---------------------------------------------------------------- register file
def regfile():
    W, H, CW, CH = 1000, 470, 58, 40
    regs = [("x5", 0x1234ABCD), ("x6", 0x0FED5432), ("x7", 0xC0FFEE00), ("x8", 0x00BADA55)]
    rows, css = [], []
    x0, y0 = 250, 130
    css.append(f"@keyframes slide{{from{{transform:translateX(0)}}to{{transform:translateX(-{8*CW}px)}}}}"
               f".row{{animation:slide 8s steps(8) infinite}}")
    for r, (name, val) in enumerate(regs):
        y = y0 + r * (CH + 22)
        nibs = [(val >> (4 * k)) & 15 for k in range(8)] * 2      # nibble 0 first, twice for the wrap
        cells = "".join(
            f"<rect x='{x0 + i*CW}' y='{y}' width='{CW-6}' height='{CH}' rx='6' fill='{CARD}' stroke='{RULE}'/>"
            f"<text x='{x0 + i*CW + (CW-6)/2}' y='{y+27}' text-anchor='middle' fill='{FG}' font-size='20' {MONO}>{n:X}</text>"
            for i, n in enumerate(nibs))
        rows.append(f"<text x='{x0-24}' y='{y+27}' text-anchor='end' fill='{DIM}' font-size='18' {MONO}>{name}</text>"
                    f"<g clip-path='url(#clip{r})'><g class='row'>{cells}</g></g>"
                    f"<clipPath id='clip{r}'><rect x='{x0}' y='{y-2}' width='{8*CW}' height='{CH+4}'/></clipPath>")
    port = (f"<rect x='{x0-4}' y='{y0-10}' width='{CW+2}' height='{4*(CH+22)-2}' rx='9' fill='none' "
            f"stroke='{DIFF}' stroke-width='3'/>"
            f"<text x='{x0+CW/2-3}' y='{y0-20}' text-anchor='middle' fill='{DIFF}' font-size='14' font-weight='700'>read port</text>")
    ph = "".join(f"<text class='p{k}' x='{x0 + 8*CW + 70}' y='{y0+95}' fill='{GOLD}' font-size='56' font-weight='800' {MONO}>{k}</text>"
                 for k in range(8))
    css.append("".join(f"@keyframes q{k}{{0%,{k*12.5:.2f}%{{opacity:0}}{k*12.5+0.01:.2f}%,{(k+1)*12.5:.2f}%{{opacity:1}}{(k+1)*12.5+0.01:.2f}%,100%{{opacity:0}}}}"
                       f".p{k}{{animation:q{k} 8s infinite;opacity:0}}" for k in range(8)))
    body = (f"<text x='40' y='50' fill='{FG}' font-size='24' font-weight='800'>Why the register file is half the size</text>"
            f"<text x='40' y='78' fill='{DIM}' font-size='15'>Every register rotates by one nibble every clock, all 15 in lockstep. "
            f"The read port only ever looks at one 4-bit slot.</text>"
            + port + "".join(rows) + ph +
            f"<text x='{x0 + 8*CW + 70}' y='{y0+128}' fill='{DIM}' font-size='14'>phase counter</text>"
            f"<text x='{x0 + 8*CW + 70}' y='{y0+148}' fill='{DIM}' font-size='14'>at phase k, the port</text>"
            f"<text x='{x0 + 8*CW + 70}' y='{y0+168}' fill='{DIM}' font-size='14'>holds nibble k of every</text>"
            f"<text x='{x0 + 8*CW + 70}' y='{y0+188}' fill='{DIM}' font-size='14'>register, low nibble first</text>"
            f"<text x='40' y='{H-30}' fill='{DIM}' font-size='14'>Measured against the real sky130 library: 11,322 µm² this way, "
            f"21,837 µm² with conventional 32-bit read ports.</text>")
    open("docs/images/regfile_rotation.svg", "w").write(svg(W, H, "The rotating register file", "".join(css), body))

# ---------------------------------------------------------------- nibble adder
def adder():
    W, H = 1200, 420
    a, b = 0x1234ABCD, 0x0FED5432
    body, css, carry = [], [], 0
    body.append(f"<text x='600' y='44' text-anchor='middle' fill='{FG}' font-size='24' font-weight='800'>"
                f"A 32-bit add, 4 bits per clock</text>"
                f"<text x='600' y='70' text-anchor='middle' fill='{DIM}' font-size='14'>0x1234ABCD + 0x0FED5432 through one "
                f"4-bit adder. The carry waits in a flip-flop for the next clock.</text>")
    for k in range(8):
        x = 70 + (7 - k) * 135                          # most significant on the left, as written
        na, nb = (a >> 4*k) & 15, (b >> 4*k) & 15
        s = na + nb + carry; out, cout = s & 15, s >> 4
        t0 = 6 + k * 10.5
        css.append(f"@keyframes r{k}{{0%,{t0:.1f}%{{opacity:0}}{t0+3:.1f}%,93%{{opacity:1}}100%{{opacity:0}}}}"
                   f".r{k}{{animation:r{k} 9s infinite;opacity:0}}"
                   f"@keyframes h{k}{{0%,{t0:.1f}%{{stroke:{RULE}}}{t0+1:.1f}%,{t0+9:.1f}%{{stroke:{DIFF}}}{t0+10.5:.1f}%,100%{{stroke:{RULE}}}}}"
                   f".h{k}{{animation:h{k} 9s infinite}}")
        body.append(f"<rect class='h{k}' x='{x}' y='100' width='120' height='240' rx='12' fill='{CARD}' stroke='{RULE}' stroke-width='3'/>"
                    f"<text x='{x+60}' y='126' text-anchor='middle' fill='{DIM}' font-size='13'>clock {k}</text>"
                    f"<text x='{x+60}' y='168' text-anchor='middle' fill='{LI}' font-size='26' {MONO}>{na:X}</text>"
                    f"<text x='{x+60}' y='202' text-anchor='middle' fill='{MET}' font-size='26' {MONO}>+{nb:X}</text>"
                    f"<line x1='{x+22}' y1='218' x2='{x+98}' y2='218' stroke='{RULE}'/>"
                    f"<g class='r{k}'><text x='{x+60}' y='256' text-anchor='middle' fill='{FG}' font-size='32' font-weight='800' {MONO}>{out:X}</text>"
                    f"<text x='{x+60}' y='292' text-anchor='middle' fill='{POLY if cout else DIM}' font-size='13'>carry out {cout}</text>"
                    + (f"<text x='{x-10}' y='262' text-anchor='middle' fill='{POLY}' font-size='26'>‹</text>" if cout and k < 7 else "")
                    + "</g>")
        carry = cout
    res = (a + b) & 0xFFFFFFFF
    css.append(f"@keyframes fin{{0%,90%{{opacity:0}}92%,99%{{opacity:1}}100%{{opacity:0}}}}.fin{{animation:fin 9s infinite;opacity:0}}")
    body.append(f"<text class='fin' x='600' y='385' text-anchor='middle' fill='{DIFF}' font-size='20' font-weight='800' {MONO}>= 0x{res:08X}</text>")
    open("docs/images/nibble_add.svg", "w").write(svg(W, H, "Nibble-serial addition", "".join(css), "".join(body)))

# ---------------------------------------------------------------- deterministic timing
def timing():
    W, H = 1100, 400
    X0, X1 = 290, 1060
    dl = [0.14, 0.33, 0.52, 0.71, 0.90]
    jitter = [0.018, -0.004, 0.027, 0.009, 0.034]           # illustration only
    css = [f"@keyframes sweep{{from{{transform:translateX(0)}}to{{transform:translateX({X1-X0}px)}}}}"
           f".cur{{animation:sweep 7s linear infinite}}"]
    body = [f"<text x='40' y='46' fill='{FG}' font-size='24' font-weight='800'>Deterministic timing</text>"
            f"<text x='40' y='72' fill='{DIM}' font-size='15'>tp_wait(deadline) parks the core until the timebase reaches it. "
            f"Every wake-up lands the same number of clocks after its deadline.</text>"]
    rows = [(150, "TinyPulse", "measured: 32 clocks after every deadline", 0.004, [0.0]*5, DIFF),
            (270, "typical MCU", "illustration: interrupt latency varies", 0.004, jitter, POLY)]
    for y, name, note, off, jit, col in rows:
        body.append(f"<text x='40' y='{y+8}' fill='{FG}' font-size='16' font-weight='700'>{name}</text>"
                    f"<text x='40' y='{y+28}' fill='{DIM}' font-size='12'>{note}</text>"
                    f"<line x1='{X0}' y1='{y+40}' x2='{X1}' y2='{y+40}' stroke='{RULE}' stroke-width='2'/>")
        for i, d in enumerate(dl):
            xd = X0 + d * (X1 - X0)
            xp = X0 + (d + off + jit[i]) * (X1 - X0)
            t = (d + off + jit[i]) * 100
            k = f"{name[:2]}{i}"
            css.append(f"@keyframes {k}{{0%,{t:.1f}%{{opacity:0}}{t+1:.1f}%,97%{{opacity:1}}100%{{opacity:0}}}}"
                       f".{k}{{animation:{k} 7s infinite;opacity:0}}")
            body.append(f"<line x1='{xd}' y1='{y-18}' x2='{xd}' y2='{y+52}' stroke='{GOLD}' stroke-width='1.5' stroke-dasharray='4 4'/>"
                        f"<rect class='{k}' x='{xp}' y='{y+4}' width='14' height='36' fill='{col}'/>")
    body.append(f"<text x='{X0}' y='350' fill='{GOLD}' font-size='13'>- - - deadlines</text>"
                f"<g class='cur'><line x1='{X0}' y1='118' x2='{X0}' y2='330' stroke='{FG}' stroke-width='2' opacity='.6'/></g>"
                f"<text x='40' y='385' fill='{DIM}' font-size='12'>TinyPulse numbers are from `make run PROG=../sw/examples/hello.c`. "
                f"The lower row is a qualitative illustration, not a measurement.</text>")
    open("docs/images/deterministic_timing.svg", "w").write(svg(W, H, "Deterministic timing", "".join(css), "".join(body)))

regfile(); adder(); timing()
import xml.dom.minidom as m
for f in ("regfile_rotation", "nibble_add", "deterministic_timing"):
    m.parse(f"docs/images/{f}.svg")
print("wrote regfile_rotation.svg, nibble_add.svg, deterministic_timing.svg (all well-formed)")
