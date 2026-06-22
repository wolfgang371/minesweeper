#!/usr/bin/env python3
"""Generate a clean classic-minesweeper tile set (32x32) for src/resources/.
All artwork is original (basic shapes + DejaVu Sans Bold digits), so it is
freely redistributable. Rendered at 8x and downscaled (LANCZOS) for smooth AA.
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "src/resources"
SS  = 8                 # supersample factor
S   = 32               # final cell size
B   = S * SS           # big canvas size
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# Classic number colors.
NUM_COLORS = {
    1: (0,   0,   238),   # blue
    2: (0,   132, 0),     # green
    3: (216, 27,  27),    # red
    4: (0,   0,   128),   # navy
    5: (128, 0,   0),     # maroon
    6: (0,   131, 131),   # teal
    7: (33,  33,  33),    # near-black
    8: (110, 110, 110),   # gray
}

BASE      = (200, 200, 200)
HILIGHT   = (255, 255, 255)
SHADOW    = (122, 122, 122)
GRID      = (160, 160, 160)
RED_BG    = (211, 47, 47)
RED_BG_GD = (150, 28, 28)
BOMB      = (28, 28, 28)
FLAG_RED  = (211, 47, 47)
POLE      = (40, 40, 40)
XRED      = (200, 16, 16)

def canvas():
    return Image.new("RGBA", (B, B), (0, 0, 0, 0))

def grad_fill(img, top, bot):
    """Subtle vertical gradient base fill."""
    d = ImageDraw.Draw(img)
    for y in range(B):
        t = y / (B - 1)
        c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (B, y)], fill=c + (255,))

def raised(img):
    """Classic 3D raised button: gradient + light top/left, dark bottom/right."""
    grad_fill(img, (216, 216, 216), (190, 190, 190))
    d = ImageDraw.Draw(img)
    w = 3 * SS
    W = H = B
    d.polygon([(0, 0), (W, 0), (W - w, w), (w, w)], fill=HILIGHT)          # top
    d.polygon([(0, 0), (w, w), (w, H - w), (0, H)], fill=HILIGHT)          # left
    d.polygon([(0, H), (w, H - w), (W - w, H - w), (W, H)], fill=SHADOW)   # bottom
    d.polygon([(W, 0), (W, H), (W - w, H - w), (W - w, w)], fill=SHADOW)   # right

def revealed(img, fill=BASE, grid=GRID):
    """Flat sunken cell with a thin top/left grid line."""
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, B, B], fill=fill + (255,))
    g = max(1, int(1.25 * SS))
    d.rectangle([0, 0, B, g], fill=grid + (255,))
    d.rectangle([0, 0, g, B], fill=grid + (255,))

def draw_digit(img, n):
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, int(B * 0.66))
    ch = str(n)
    bb = d.textbbox((0, 0), ch, font=font)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    pos = ((B - tw) / 2 - bb[0], (B - th) / 2 - bb[1])
    d.text(pos, ch, font=font, fill=NUM_COLORS[n] + (255,))

def draw_bomb(img):
    d = ImageDraw.Draw(img)
    cx = cy = B / 2
    r = B * 0.255
    sp = r * 1.62
    lw = int(2.4 * SS)
    # 8 spikes
    import math
    for a in range(0, 360, 45):
        rad = math.radians(a)
        dx, dy = math.cos(rad) * sp, math.sin(rad) * sp
        d.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], fill=BOMB + (255,), width=lw)
    # body
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=BOMB + (255,))
    # shine
    hr = r * 0.32
    hx, hy = cx - r * 0.34, cy - r * 0.34
    d.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=(235, 235, 235, 255))

def draw_flag(img):
    d = ImageDraw.Draw(img)
    def P(x, y):  # 0..32 coords -> big
        return (x * SS, y * SS)
    # base stand
    d.polygon([P(9, 27), P(23, 27), P(26, 29.5), P(6, 29.5)], fill=POLE + (255,))
    d.polygon([P(13, 24.5), P(19, 24.5), P(23, 27), P(9, 27)], fill=POLE + (255,))
    # pole
    d.rectangle([P(19.2, 5)[0], P(19.2, 5)[1], P(21, 25.5)[0], P(21, 25.5)[1]], fill=POLE + (255,))
    # flag
    d.polygon([P(20, 5), P(20, 15.5), P(7.5, 10.2)], fill=FLAG_RED + (255,))

def draw_x(img):
    d = ImageDraw.Draw(img)
    m = 6 * SS
    lw = int(2.6 * SS)
    d.line([(m, m), (B - m, B - m)], fill=XRED + (255,), width=lw)
    d.line([(B - m, m), (m, B - m)], fill=XRED + (255,), width=lw)

def save(img, name):
    small = img.resize((S, S), Image.LANCZOS)
    small.save(os.path.join(OUT, name + ".png"))

os.makedirs(OUT, exist_ok=True)

# numbers 0..8 (0 = empty revealed cell)
for n in range(9):
    img = canvas(); revealed(img)
    if n > 0:
        draw_digit(img, n)
    save(img, str(n))

# unknown (covered)
img = canvas(); raised(img); save(img, "unknown")

# marker (flag on a covered cell)
img = canvas(); raised(img); draw_flag(img); save(img, "marker")

# bomb (revealed, safe-coloured background)
img = canvas(); revealed(img); draw_bomb(img); save(img, "bomb")

# bomb_triggered (the detonated mine: red background)
img = canvas(); revealed(img, fill=RED_BG, grid=RED_BG_GD); draw_bomb(img); save(img, "bomb_triggered")

# marker_wrong (flagged a non-bomb: bomb with a red X)
img = canvas(); revealed(img); draw_bomb(img); draw_x(img); save(img, "marker_wrong")

print("wrote 14 tiles to", OUT)
