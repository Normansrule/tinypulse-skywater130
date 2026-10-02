#!/usr/bin/env python3
"""figures.py — regenerate the SVG diagrams in docs/images from the design's
facts. Run from the repo root: python3 docs/tools/figures.py"""
import json, os
os.makedirs("docs/images", exist_ok=True)
BG, FG, DIM, CARD = "#0b0e14", "#e9ecef", "#8b949e", "#161b22"
FONT = "font-family='Inter,Segoe UI,Helvetica,Arial,sans-serif'"
C = dict(gpio="#4f8cff", uart="#c77dff", time="#ff5d73", qspi="#ff9f1c",
         status="#3ddc97", core="#8a5cff", reg="#4f8cff", bus="#adb5bd", per="#90be6d")

def svg(w, h, body, title):
    return (f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 {w} {h}' {FONT}>"
            f"<title>{title}</title><rect width='{w}' height='{h}' rx='16' fill='{BG}'/>{body}</svg>")

# ------------------------------------------------------------------ pinout
ui = [("ui[0]","IN0 · CAP0","gpio","QSPI latency bit 0 at reset"),
      ("ui[1]","IN1 · CAP1","gpio","QSPI latency bit 1 at reset"),
      ("ui[2]","IN2 · CAP2","gpio","QSPI latency bit 2 at reset"),
      ("ui[3]","UART RX · CAP3","uart","from the demo board RP2040"),
      ("ui[4]","IN4 · CAP4","gpio",""),("ui[5]","IN5 · CAP5","gpio",""),
      ("ui[6]","IN6 · CAP6","gpio",""),("ui[7]","IN7 · CAP7 · BOOT","uart","high at reset: UART bootloader")]
uo = [("uo[0]","OUT0 / TRIG0","time","deadline trigger 0"),
      ("uo[1]","OUT1 / TRIG1","time","deadline trigger 1"),
      ("uo[2]","OUT2 / EVT","status","event waiting"),
      ("uo[3]","OUT3 / OVF","status","event queue overflowed"),
      ("uo[4]","OUT4 / UART TX","uart","to the demo board RP2040"),
      ("uo[5]","OUT5 / HALT","status","ECALL / EBREAK reached"),
      ("uo[6]","OUT6 / ILLEGAL","status","bad instruction seen"),
      ("uo[7]","OUT7 / HEARTBEAT","status","~3 Hz blink at 50 MHz")]
uio = [("uio[0]","CS0 flash"),("uio[1]","SD0"),("uio[2]","SD1"),("uio[3]","SCK"),
       ("uio[4]","SD2"),("uio[5]","SD3"),("uio[6]","CS1 RAM A"),("uio[7]","CS2 RAM B")]
W, H = 1200, 760
b = [f"<text x='600' y='48' fill='{FG}' font-size='28' font-weight='700' text-anchor='middle'>TinyPulse pinout — 24 signals</text>",
     f"<text x='600' y='76' fill='{DIM}' font-size='15' text-anchor='middle'>8 inputs · 8 outputs (GPIO or built-in function, per pin) · 8 to the QSPI Pmod</text>"]
cx, cy, cw, ch = 430, 120, 340, 440
b.append(f"<rect x='{cx}' y='{cy}' width='{cw}' height='{ch}' rx='18' fill='{CARD}' stroke='#30363d' stroke-width='3'/>")
b.append(f"<text x='600' y='{cy+190}' fill='{FG}' font-size='30' font-weight='800' text-anchor='middle'>TinyPulse</text>")
b.append(f"<text x='600' y='{cy+222}' fill='{DIM}' font-size='15' text-anchor='middle'>RV32E microcontroller</text>")
b.append(f"<text x='600' y='{cy+246}' fill='{DIM}' font-size='15' text-anchor='middle'>sky130 · 2×2 tiles · 50 MHz</text>")
for i,(p,n,k,note) in enumerate(ui):
    y = cy + 34 + i*52
    b.append(f"<line x1='{cx-70}' y1='{y}' x2='{cx}' y2='{y}' stroke='{C[k]}' stroke-width='4'/>")
    b.append(f"<circle cx='{cx-70}' cy='{y}' r='7' fill='{C[k]}'/>")
    b.append(f"<text x='{cx+14}' y='{y+5}' fill='{DIM}' font-size='13'>{p}</text>")
    b.append(f"<text x='{cx-84}' y='{y+1}' fill='{FG}' font-size='16' font-weight='600' text-anchor='end'>{n}</text>")
    if note: b.append(f"<text x='{cx-84}' y='{y+19}' fill='{DIM}' font-size='12' text-anchor='end'>{note}</text>")
for i,(p,n,k,note) in enumerate(uo):
    y = cy + 34 + i*52
    b.append(f"<line x1='{cx+cw}' y1='{y}' x2='{cx+cw+70}' y2='{y}' stroke='{C[k]}' stroke-width='4'/>")
    b.append(f"<circle cx='{cx+cw+70}' cy='{y}' r='7' fill='{C[k]}'/>")
    b.append(f"<text x='{cx+cw-14}' y='{y+5}' fill='{DIM}' font-size='13' text-anchor='end'>{p}</text>")
    b.append(f"<text x='{cx+cw+84}' y='{y+1}' fill='{FG}' font-size='16' font-weight='600'>{n}</text>")
    b.append(f"<text x='{cx+cw+84}' y='{y+19}' fill='{DIM}' font-size='12'>{note}</text>")
for i,(p,n) in enumerate(uio):
    x = cx + 22 + i*42
    b.append(f"<line x1='{x}' y1='{cy+ch}' x2='{x}' y2='{cy+ch+60}' stroke='{C['qspi']}' stroke-width='4'/>")
    b.append(f"<circle cx='{x}' cy='{cy+ch+60}' r='7' fill='{C['qspi']}'/>")
    b.append(f"<text transform='translate({x+5},{cy+ch+74}) rotate(55)' fill='{FG}' font-size='13' font-weight='600'>{n} <tspan fill='{DIM}' font-weight='400' font-size='11'>{p}</tspan></text>")
b.append(f"<text x='600' y='{H-22}' fill='{C['qspi']}' font-size='15' text-anchor='middle'>uio: Tiny Tapeout QSPI Pmod — 16 MB flash + 2 × 8 MB RAM (released while in reset so the RP2040 can flash it)</text>")
leg = [("gpio","GPIO / timestamp capture"),("uart","UART"),("time","deadline trigger"),("status","status")]
for i,(k,t) in enumerate(leg):
    b.append(f"<rect x='{40+i*220}' y='96' width='14' height='14' rx='3' fill='{C[k]}'/><text x='{60+i*220}' y='108' fill='{DIM}' font-size='13'>{t}</text>")
open("docs/images/pinout.svg","w").write(svg(W,H,"".join(b),"TinyPulse pinout"))

# ------------------------------------------------------------------ block diagram
W, H = 1200, 560
def box(x,y,w,h,col,title,sub):
    return (f"<rect x='{x}' y='{y}' width='{w}' height='{h}' rx='14' fill='{CARD}' stroke='{col}' stroke-width='3'/>"
            f"<text x='{x+w/2}' y='{y+h/2-4}' fill='{FG}' font-size='18' font-weight='700' text-anchor='middle'>{title}</text>"
            f"<text x='{x+w/2}' y='{y+h/2+20}' fill='{DIM}' font-size='13' text-anchor='middle'>{sub}</text>")
def arrow(x1,y1,x2,y2,col=DIM,label=""):
    s = f"<line x1='{x1}' y1='{y1}' x2='{x2}' y2='{y2}' stroke='{col}' stroke-width='3' marker-end='url(#a)'/>"
    if label: s += f"<text x='{(x1+x2)/2+6}' y='{(y1+y2)/2-6}' fill='{DIM}' font-size='12'>{label}</text>"
    return s
b = [f"<defs><marker id='a' viewBox='0 0 10 10' refX='9' refY='5' markerWidth='7' markerHeight='7' orient='auto-start-reverse'><path d='M0,0L10,5L0,10z' fill='{DIM}'/></marker></defs>",
     f"<text x='600' y='44' fill='{FG}' font-size='26' font-weight='700' text-anchor='middle'>Inside TinyPulse</text>",
     box(60,90,300,150,C['core'],"CPU core","RV32E · 4 bits per clock · 8-clock ALU op"),
     box(60,300,300,110,C['reg'],"Register file","15 × 32 bits, rotating, 2 × 4-bit ports"),
     box(450,90,300,150,C['bus'],"Bus","address decode · data port has priority"),
     box(840,60,300,110,C['qspi'],"QSPI controller","flash + 2 RAMs · streaming fetch"),
     box(840,200,300,110,C['time'],"Timing unit","timebase · 2 triggers · 8 captures · queue"),
     box(840,340,300,110,C['per'],"GPIO + UART","8 in · 8 out · SET/CLR/XOR · 8N1"),
     arrow(210,240,210,298,label="nibbles"), arrow(360,165,448,165,label="fetch / load / store"),
     arrow(750,130,838,115), arrow(750,190,838,390),
     "<path d='M360 200 C 600 330, 700 255, 838 255' stroke='#ff5d73' stroke-width='3' fill='none' marker-end='url(#a)'/>",
     f"<text x='540' y='300' fill='{C['time']}' font-size='13'>Xpulse instructions (direct port)</text>",
     f"<text x='600' y='515' fill='{DIM}' font-size='14' text-anchor='middle'>0x0000_0000 flash · 0x1000_0000 RAM A · 0x1080_0000 RAM B · 0x3000_0000 GPIO/UART</text>"]
open("docs/images/block_diagram.svg","w").write(svg(W,H,"".join(b),"TinyPulse block diagram"))

# ------------------------------------------------------------------ scale
W, H = 1200, 460
s = 1.1   # px per um
b = [f"<text x='600' y='44' fill='{FG}' font-size='26' font-weight='700' text-anchor='middle'>How small is it?</text>",
     f"<text x='600' y='72' fill='{DIM}' font-size='15' text-anchor='middle'>everything drawn to the same scale · 100 µm = 110 px</text>"]
x0, base = 90, 390
tw, th = 334.88*s, 225.76*s
b.append(f"<rect x='{x0}' y='{base-th}' width='{tw}' height='{th}' fill='#1f2a44' stroke='{C['core']}' stroke-width='3'/>")
b.append(f"<text x='{x0+tw/2}' y='{base-th/2}' fill='{FG}' font-size='17' font-weight='700' text-anchor='middle'>TinyPulse</text>")
b.append(f"<text x='{x0+tw/2}' y='{base-th/2+22}' fill='{DIM}' font-size='13' text-anchor='middle'>0.335 × 0.226 mm</text>")
b.append(f"<text x='{x0+tw/2}' y='{base-th/2+40}' fill='{DIM}' font-size='13' text-anchor='middle'>≈ 5,000 logic cells</text>")
hx = x0+tw+80
b.append(f"<rect x='{hx}' y='{base-250}' width='{70*s}' height='250' fill='#b08968' opacity='.85'/>")
b.append(f"<text x='{hx+35*s}' y='{base+22}' fill='{FG}' font-size='14' text-anchor='middle'>human hair</text><text x='{hx+35*s}' y='{base+40}' fill='{DIM}' font-size='12' text-anchor='middle'>~70 µm wide</text>")
sx = hx+170; sw = 300*s
b.append(f"<rect x='{sx}' y='{base-sw}' width='{sw}' height='{sw}' rx='14' fill='#e9ecef' opacity='.9' transform='rotate(-4 {sx+sw/2} {base-sw/2})'/>")
b.append(f"<text x='{sx+sw/2}' y='{base+22}' fill='{FG}' font-size='14' text-anchor='middle'>grain of table salt</text><text x='{sx+sw/2}' y='{base+40}' fill='{DIM}' font-size='12' text-anchor='middle'>~0.3 mm</text>")
rx = sx+sw+70
b.append(f"<circle cx='{rx}' cy='{base-8}' r='{7.5*s/2+1}' fill='#ff5d73'/>")
b.append(f"<text x='{rx}' y='{base+22}' fill='{FG}' font-size='14' text-anchor='middle'>red blood cell</text><text x='{rx}' y='{base+40}' fill='{DIM}' font-size='12' text-anchor='middle'>~7.5 µm</text>")
b.append(f"<line x1='{x0}' y1='{base+60}' x2='{x0+110}' y2='{base+60}' stroke='{FG}' stroke-width='3'/><text x='{x0+120}' y='{base+65}' fill='{DIM}' font-size='13'>100 µm</text>")
open("docs/images/scale.svg","w").write(svg(W,H,"".join(b),"TinyPulse size comparison"))

# (the nibble adder is animated now: see animations.py)
print("wrote pinout.svg, block_diagram.svg, scale.svg")
