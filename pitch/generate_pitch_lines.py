#!/usr/bin/env python3
"""Generate a 4K high-resolution field-line mask texture for the pitch shader.
Resolution: 2836 (width) x 4096 (length).
Covers: X in [-45, 45] m, Z in [-65, 65] m.
Resolution density: ~31.5 pixels per metre (~3.1 cm per pixel).
"""
from PIL import Image, ImageDraw
import math, os

OUT = os.path.dirname(os.path.abspath(__file__))

PLAY_L = 105.0        # along Z
PLAY_W = 68.0         # along X
MARGIN = 12.5         # margin around play area

X0, X1 = -45.0, 45.0            # 90 m across (X)
Z0, Z1 = -(PLAY_L / 2 + MARGIN), (PLAY_L / 2 + MARGIN)  # -65 .. 65 (Z)
FULL_X = X1 - X0
FULL_Z = Z1 - Z0

RES_LONG = 4096       # 4K resolution along Z
SCALE = RES_LONG / FULL_Z
RES_ACROSS = int(round(FULL_X * SCALE))

W, H = RES_ACROSS, RES_LONG
SS = 2                # 2x supersampling for smooth antialiased rasterization
LINE_W = 0.12         # 12 cm crisp regulation lines
LW = LINE_W * SCALE * SS

img = Image.new("L", (W * SS, H * SS), 0)
d = ImageDraw.Draw(img)

def px(x):
    return (x - X0) * SCALE * SS

def pz(z):
    return (z - Z0) * SCALE * SS

def line(x1, z1, x2, z2):
    d.line([px(x1), pz(z1), px(x2), pz(z2)], fill=255, width=int(round(LW)))

def ring(cx, cz, r):
    rr = r * SCALE * SS
    d.ellipse([px(cx) - rr, pz(cz) - rr, px(cx) + rr, pz(cz) + rr],
              outline=255, width=int(round(LW)))

def dot(cx, cz, r=0.12):
    rr = r * SCALE * SS
    d.ellipse([px(cx) - rr, pz(cz) - rr, px(cx) + rr, pz(cz) + rr], fill=255)

def polyline(pts):
    if len(pts) > 1:
        d.line([(px(a), pz(b)) for (a, b) in pts], fill=255, width=int(round(LW)))

HL = PLAY_L / 2.0   # +/- 52.5 m
HW = PLAY_W / 2.0   # +/- 34.0 m

# Outer Boundary
line(-HW, -HL, HW, -HL)
line(-HW, HL, HW, HL)
line(-HW, -HL, -HW, HL)
line(HW, -HL, HW, HL)

# Halfway Line across width
line(-HW, 0, HW, 0)

# Center Circle & Center Spot
ring(0, 0, 9.15)
dot(0, 0)

# Penalty & Goal Areas + Spots + D Arcs
for sgn in (-1, 1):
    goal_z = sgn * HL
    pa_z = goal_z - sgn * 16.5
    ga_z = goal_z - sgn * 5.5
    line(-20.16, goal_z, -20.16, pa_z)
    line(20.16, goal_z, 20.16, pa_z)
    line(-20.16, pa_z, 20.16, pa_z)
    line(-9.16, goal_z, -9.16, ga_z)
    line(9.16, goal_z, 9.16, ga_z)
    line(-9.16, ga_z, 9.16, ga_z)
    ps_z = goal_z - sgn * 11.0
    dot(0, ps_z)

    # D Arc
    pts = []
    steps = 240
    for i in range(steps + 1):
        a = 2 * math.pi * i / steps
        x = 9.15 * math.cos(a)
        z = ps_z + 9.15 * math.sin(a)
        outside = (z < pa_z) if sgn > 0 else (z > pa_z)
        if outside:
            pts.append((x, z))
    polyline(pts)

# Corner Arcs (r = 1.0 m) - drawn perfectly flush connecting the touchline and goal line
for cx in (-HW, HW):
    for cz in (-HL, HL):
        # Direction from corner along the touchline (towards x = 0, z = cz)
        ang_touch = math.atan2(0, -cx)
        # Direction from corner along the goal line (towards x = cx, z = 0)
        ang_goal = math.atan2(-cz, 0)
        # Normalize the angle difference to sweep exactly 90 degrees inside the pitch
        diff = ang_goal - ang_touch
        if diff > math.pi:
            diff -= 2 * math.pi
        elif diff < -math.pi:
            diff += 2 * math.pi
        pts = []
        steps = 32
        for i in range(steps + 1):
            a = ang_touch + diff * i / steps
            pts.append((cx + 1.0 * math.cos(a), cz + 1.0 * math.sin(a)))
        polyline(pts)

img = img.resize((W, H), Image.LANCZOS)

rgba = Image.new("RGBA", (W, H), (0, 0, 0, 0))
white = Image.new("RGB", (W, H), (255, 255, 255))
rgba.paste(white, (0, 0), img)

out_path = os.path.join(OUT, "pitch_lines_mask.png")
rgba.save(out_path, "PNG")
print(f"Generated 4K line mask: {out_path} ({W}x{H})")
