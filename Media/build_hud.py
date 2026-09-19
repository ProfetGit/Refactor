#!/usr/bin/env python3
"""Turn the greyscale HUD mask sheets into white + alpha TGAs the addon can tint."""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

SRC = Path("hud")
OUT = Path("/mnt/user-data/outputs/Refactor-FarmHUD")


def to_alpha(im):
    """Luminance to alpha, using the sheet's own paper tone as the white point."""
    a = np.array(im.convert("L")).astype(np.float32)
    white = np.percentile(a, 97)          # sheets are not pure white, so measure it
    return np.clip((white - a) / max(1.0, white), 0, 1)


def blobs(alpha, thresh=0.04, close=21, min_area=400):
    m = ndimage.binary_closing(alpha > thresh, np.ones((close, close)))
    lab, _ = ndimage.label(m)
    out = []
    for sl in ndimage.find_objects(lab):
        y0, y1, x0, x1 = sl[0].start, sl[0].stop, sl[1].start, sl[1].stop
        if (x1 - x0) * (y1 - y0) >= min_area:
            out.append((y0, x0, y1, x1))
    return out


def save(alpha, box, size, name, normalise=True):
    y0, x0, y1, x1 = box
    a = Image.fromarray((alpha[y0:y1, x0:x1] * 255).astype(np.uint8)).resize(size, Image.LANCZOS)
    a = np.array(a).astype(np.float32)
    if normalise and a.max() > 0:
        a *= 255.0 / a.max()          # full alpha range, the addon sets opacity
    rgba = np.dstack([np.full(a.shape, 255.0)] * 3 + [np.clip(a, 0, 255)]).astype(np.uint8)
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, "RGBA").save(OUT / f"{name}.tga", compression=None)
    print(f"  {name}.tga {size[0]}x{size[1]}")
    return Image.fromarray(rgba, "RGBA")


pieces = {}

# backdrop: one big soft smudge
al = to_alpha(Image.open(SRC / "122039.png"))
b = max(blobs(al, 0.06, 31, 5000), key=lambda r: (r[2] - r[0]) * (r[3] - r[1]))
pieces["HudBackdrop"] = save(al, b, (256, 128), "HudBackdrop")

# meter: two bars, top is the track, bottom is the fill
al = to_alpha(Image.open(SRC / "122043.png"))
bars = sorted(blobs(al, 0.08, 9, 2000))
pieces["MeterTrack"] = save(al, bars[0], (256, 8), "MeterTrack")
pieces["MeterFill"] = save(al, bars[1], (256, 8), "MeterFill")

# drag grip
al = to_alpha(Image.open(SRC / "122109.png"))
bs = blobs(al, 0.10, 15, 300)
y0 = min(r[0] for r in bs); x0 = min(r[1] for r in bs)
y1 = max(r[2] for r in bs); x1 = max(r[3] for r in bs)
pieces["DragGrip"] = save(al, (y0, x0, y1, x1), (32, 32), "DragGrip")

# stat icons, 2x2 sheet
al = to_alpha(Image.open(SRC / "122301.png"))
H, W = al.shape
names = {(0, 0): "IconClock", (0, 1): "IconCoins", (1, 0): "IconBag", (1, 1): "IconTrend"}
cells = {}
for r in blobs(al, 0.15, 15, 2000):
    key = (0 if (r[0] + r[2]) / 2 < H / 2 else 1, 0 if (r[1] + r[3]) / 2 < W / 2 else 1)
    c = cells.get(key)
    cells[key] = (min(c[0], r[0]), min(c[1], r[1]), max(c[2], r[2]), max(c[3], r[3])) if c else r
for key, name in names.items():
    y0, x0, y1, x1 = cells[key]
    s = max(y1 - y0, x1 - x0)                      # pad to square so icons match in size
    cy, cx = (y0 + y1) // 2, (x0 + x1) // 2
    box = (cy - s // 2 - 8, cx - s // 2 - 8, cy + s // 2 + 8, cx + s // 2 + 8)
    pieces[name] = save(al, box, (32, 32), name)

# ---- preview -------------------------------------------------------------
bg = Image.open("out/Panel.tga").convert("RGBA").resize((460, 260))
bg = Image.eval(bg, lambda v: min(255, int(v * 2.0)))


def tint(im, size, rgb, alpha=1.0):
    s = im.resize(size, Image.LANCZOS)
    a = s.split()[3].point(lambda v: int(v * alpha))
    o = Image.new("RGBA", size, rgb + (255,)); o.putalpha(a); return o


GOLD = (230, 200, 120); TEXT = (216, 201, 168); MUTED = (140, 126, 106)
bg.alpha_composite(tint(pieces["HudBackdrop"], (250, 120), (12, 9, 7), 0.9), (24, 22))
bg.alpha_composite(tint(pieces["DragGrip"], (16, 16), (150, 135, 110), 0.5), (140, 28))
d = ImageDraw.Draw(bg)
d.text((44, 44), "142g / hr", fill=GOLD)
d.text((44, 62), "1h 12m   178g   Auctionator", fill=MUTED)
bg.alpha_composite(tint(pieces["MeterTrack"], (200, 4), (120, 105, 85), 0.6), (44, 84))
bg.alpha_composite(tint(pieces["MeterFill"], (128, 4), (198, 106, 58), 0.95), (44, 84))
for i, (n, label) in enumerate((("IconClock", "1h12"), ("IconCoins", "178g"), ("IconBag", "94"), ("IconTrend", "+12%"))):
    x = 44 + i * 52
    bg.alpha_composite(tint(pieces[n], (14, 14), (150, 135, 110), 0.85), (x, 100))
    d.text((x + 17, 102), label, fill=TEXT)
bg.resize((bg.width * 2, bg.height * 2), Image.LANCZOS).save(OUT / "preview_hud.png")
print("preview written")
