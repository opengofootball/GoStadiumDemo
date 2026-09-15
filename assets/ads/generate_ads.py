#!/usr/bin/env python3
"""Generate simple LED perimeter ad banner PNGs for the CommonPitch ad boards.
Run: python3 assets/ads/generate_ads.py
You can also drop your own sponsor PNGs (ad_banner_0.png, ad_banner_1.png) into this folder.
"""
from PIL import Image, ImageDraw, ImageFont
import os

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

def make_font(size):
    # Try a common Linux font, else fall back to default
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ]
    for c in candidates:
        if os.path.exists(c):
            try:
                return ImageFont.truetype(c, size)
            except Exception:
                pass
    return ImageFont.load_default()

def banner(name, colors, texts, out="ad_banner_0.png"):
    W, H = 1024, 256
    img = Image.new("RGB", (W, H), colors[0])
    d = ImageDraw.Draw(img)
    # LED pixel-grid overlay (subtle vertical stripes for LED screen look)
    for x in range(0, W, 8):
        d.line([(x, 0), (x, H)], fill=(0, 0, 0), width=1)
    # Color block stripes for sponsor zones
    n = len(texts)
    seg = W // max(1, n)
    for i, txt in enumerate(texts):
        col = colors[i % len(colors)]
        d.rectangle([i*seg+4, 4, (i+1)*seg-4, H-4], fill=col)
        fnt = make_font(48)
        try:
            tb = d.textbbox((0, 0), txt, font=fnt)
            tw, th = tb[2]-tb[0], tb[3]-tb[1]
        except Exception:
            tw, th = d.textsize(txt, font=fnt)
        cx = i*seg + (seg - tw)//2
        cy = (H - th)//2
        # Draw text with white stroke and dark fill so it reads well on any color
        d.text((cx-2, cy-2), txt, fill=(0, 0, 0), font=fnt)
        d.text((cx+2, cy-2), txt, fill=(0, 0, 0), font=fnt)
        d.text((cx, cy+2), txt, fill=(0, 0, 0), font=fnt)
        d.text((cx, cy), txt, fill=(255, 255, 255), font=fnt)
    p = os.path.join(OUT_DIR, out)
    img.save(p, "PNG")
    print("Wrote", p, "(", W, "x", H, ")")

# ad_banner_0: vivid sponsor blocks
banner(
    "A",
    [(15, 30, 120), (200, 40, 40), (30, 130, 60), (220, 180, 30), (35, 35, 45)],
    ["CHAMPIONS", "SKYTECH", "GOSTADIUM", "VELOCITA", "PLAYMORE"],
    out="ad_banner_0.png",
)

# ad_banner_1: different palette & content
banner(
    "B",
    [(20, 90, 190), (180, 25, 55), (25, 150, 110), (170, 120, 30), (30, 30, 40)],
    ["GODOT ENGINE", "WIDZEW", "LODZ 1910", "TURBO ENERGY", "GOOOOAL"],
    out="ad_banner_1.png",
)
