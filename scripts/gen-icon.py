#!/usr/bin/env python3
"""Generate an original Minesweeper app icon (multi-size .ico + 256 .png).
A black bomb on a beveled, rounded steel-gray tile. All original artwork."""
import sys, math
from PIL import Image, ImageDraw

OUT_ICO = sys.argv[1] if len(sys.argv) > 1 else "resources/minesweeper.ico"
OUT_PNG = sys.argv[2] if len(sys.argv) > 2 else "resources/minesweeper.png"
SIZES = [16, 24, 32, 48, 64, 128, 256]
SS = 8

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def render(S):
    B = S * SS
    img = Image.new("RGBA", (B, B), (0, 0, 0, 0))

    # rounded-rect tile with a vertical gradient, via an alpha mask
    grad = Image.new("RGBA", (B, B))
    gd = ImageDraw.Draw(grad)
    top, bot = (226, 230, 235), (170, 177, 187)
    for y in range(B):
        gd.line([(0, y), (B, y)], fill=lerp(top, bot, y / (B - 1)) + (255,))
    mask = Image.new("L", (B, B), 0)
    md = ImageDraw.Draw(mask)
    pad = int(B * 0.045)
    rad = int(B * 0.20)
    md.rounded_rectangle([pad, pad, B - pad, B - pad], radius=rad, fill=255)
    img.paste(grad, (0, 0), mask)

    d = ImageDraw.Draw(img)
    # soft top gloss
    gloss = Image.new("RGBA", (B, B), (0, 0, 0, 0))
    gld = ImageDraw.Draw(gloss)
    gld.rounded_rectangle([pad, pad, B - pad, int(B * 0.5)], radius=rad,
                          fill=(255, 255, 255, 46))
    img.alpha_composite(gloss)
    # border
    bw = max(SS, int(B * 0.022))
    d.rounded_rectangle([pad, pad, B - pad, B - pad], radius=rad,
                        outline=(110, 118, 130, 255), width=bw)

    # bomb
    cx = cy = B / 2
    r = B * 0.275
    sp = r * 1.55
    lw = max(SS, int(B * 0.055))
    for a in range(0, 360, 45):
        rad2 = math.radians(a)
        dx, dy = math.cos(rad2) * sp, math.sin(rad2) * sp
        d.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], fill=(22, 22, 22, 255), width=lw)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(22, 22, 22, 255))
    hr = r * 0.34
    hx, hy = cx - r * 0.36, cy - r * 0.36
    d.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=(238, 238, 238, 255))

    return img.resize((S, S), Image.LANCZOS)

frames = [render(s) for s in SIZES]
big = frames[-1]  # 256
big.save(OUT_PNG)
big.save(OUT_ICO, format="ICO", sizes=[(s, s) for s in SIZES])
print("wrote", OUT_ICO, "and", OUT_PNG, "sizes:", SIZES)
