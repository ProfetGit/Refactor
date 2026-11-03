#!/usr/bin/env python3
"""Draw Refactor's icon, its in-game TGAs, the README banner and the Ko-fi banner from one set of shapes.

Needs rsvg-convert (librsvg) and Pillow. Dev only: nothing here is packaged.

    python3 Tools/Branding/build.py            # everything
    python3 Tools/Branding/build.py --icons    # icons only
    python3 Tools/Branding/build.py --stills   # one PNG per banner beat in .preview/branding, no WebP
"""
import math
import random
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FPS = 30

# Plate palette, sampled from the theme's bronze and kept here so every output agrees.
RIM = "#24180d"
FACE = "#bb8e50"
GOLD_LIGHT = "#f4d99d"
GOLD = "#d6aa62"
GOLD_DARK = "#6e4b24"
CREAM = "#eadfc6"
MUTED = "#a8977a"
COPPER = "#d8743a"
KOFI_RED = "#ff5e5b"

OCTAGON = "M22 4H106L124 22V106L106 124H22L4 106V22Z"
PLATE_FACE = "M27.07 15H100.93L113 27.07V100.93L100.93 113H27.07L15 100.93V27.07Z"
PLATE_LINE = "M28.73 19H99.27L109 28.73V99.27L99.27 109H28.73L19 99.27V28.73Z"
# Bevel facets between the octagon and its face, lit from the top left.
FACETS = (
    ("#e6c485", "M10 25L25 10L27.07 15L15 27.07Z"),
    ("#d9b371", "M25 10H103L100.93 15H27.07Z"),
    ("#c99f60", "M103 10L118 25L113 27.07L100.93 15Z"),
    ("#a0743f", "M118 25V103L113 100.93V27.07Z"),
    ("#7c5730", "M118 103L103 118L100.93 113L113 100.93Z"),
    ("#8b6235", "M103 118H25L27.07 113H100.93Z"),
    ("#a77b45", "M25 118L10 103L15 100.93L27.07 113Z"),
    ("#cda362", "M10 103V25L15 27.07V100.93Z"),
)
# Raidho, the rune for R. Centred by eye, not by box: the stem carries most of the weight.
RUNE = '<path d="M49 25V103"/><path d="M49 33L78 50L49 67"/><path d="M53 66L84 102"/>'

# The wordmark is built from the rune's stroke: 12 units wide, cut flat at cap height 66.
LETTERS = {
    "R": (47, '<path d="M6 -8V74"/><path d="M6 2L35 19L6 36"/><path d="M10 35L41 71"/>'),
    "E": (38, '<path d="M6 -8V74"/><path d="M0 6H38"/><path d="M0 33H32"/><path d="M0 60H38"/>'),
    "F": (38, '<path d="M6 -8V74"/><path d="M0 6H38"/><path d="M0 33H32"/>'),
    "A": (52, '<path d="M4 74L26 -8L48 74"/><path d="M12 44H40"/>'),
    "C": (40, '<path d="M40 6H17L6 17V49L17 60H40"/>'),
    "T": (44, '<path d="M0 6H44"/><path d="M22 -8V74"/>'),
    "O": (50, '<path d="M17 6H33L44 17V49L33 60H17L6 49V17Z"/>'),
    "S": (40, '<path d="M40 6H17L6 17V22L17 33H29L40 44V49L29 60H0"/>'),
    "U": (48, '<path d="M6 -8V49L17 60H31L42 49V-8"/>'),
    "P": (47, '<path d="M6 -8V74"/><path d="M6 2L35 19L6 36"/>'),
    "N": (48, '<path d="M6 74V-8"/><path d="M42 -8V74"/><path d="M3 -6L45 72"/>'),
    "K": (46, '<path d="M6 -8V74"/><path d="M6 38L40 -6"/><path d="M17 25L44 72"/>'),
    "I": (12, '<path d="M6 -8V74"/>'),
    "-": (22, '<path d="M0 36H22"/>'),
    " ": (26, ""),
}
# Gaps set by eye for the pairs that need them; every other pair gets DEFAULT_GAP.
PAIR_GAPS = {"EF": 10, "FA": 4, "CT": 6, "TO": 4, "OR": 9, "PO": 6, "RT": 6, "O-": 6, "-F": 6}
DEFAULT_GAP = 8
CAP = 66


def text_width(text, size, spacing):
    """Width of a Noto Serif Display Medium line as rsvg sets it, for centring."""
    path = subprocess.run(["fc-match", "-f", "%{file}", "Noto Serif Display:style=Medium"],
                          capture_output=True, text=True, check=True).stdout
    return ImageFont.truetype(path, size).getlength(text) + spacing * (len(text) - 1)


def mix(a, b, t):
    a = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(a, b))


def ease(u):
    u = min(1.0, max(0.0, u))
    return u * u * (3 - 2 * u)


def svg(w, h, body, view=None):
    view = view or f"0 0 {w} {h}"
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}" width="{w}" height="{h}">'
            f'{body}</svg>')


def rasterise(doc, w, h):
    png = subprocess.run(["rsvg-convert", "-w", str(w), "-h", str(h)], input=doc.encode(),
                         capture_output=True, check=True).stdout
    return Image.open(BytesIO(png)).convert("RGBA")


def rune(p, glow=0.0):
    """The carved rune in icon units: lit lip below, shadowed top wall, floor that can glow."""
    floor = mix("#3d2914", "#f0883a", glow)
    out = (f'<defs><clipPath id="{p}cut"><rect x="0" y="31" width="128" height="66"/></clipPath>'
           f'<g id="{p}rune" fill="none" stroke-linejoin="miter" stroke-linecap="butt" '
           f'clip-path="url(#{p}cut)">{RUNE}</g>'
           f'<mask id="{p}ch" maskUnits="userSpaceOnUse" x="0" y="0" width="128" height="128">'
           f'<use href="#{p}rune" stroke="#fff" stroke-width="12"/></mask>'
           f'<filter id="{p}bloom" x="-50%" y="-50%" width="200%" height="200%">'
           f'<feGaussianBlur stdDeviation="6"/></filter>'
           f'<filter id="{p}soft" x="-20%" y="-20%" width="140%" height="140%">'
           f'<feGaussianBlur stdDeviation="1.4"/></filter></defs>'
           f'<use href="#{p}rune" stroke="#f3dca8" stroke-width="12" transform="translate(0 2)"/>'
           f'<use href="#{p}rune" stroke="#1e1309" stroke-width="12"/>'
           f'<g mask="url(#{p}ch)"><use href="#{p}rune" stroke="{floor}" stroke-width="12" '
           f'transform="translate(0 2.5)"/>')
    if glow > 0.01:
        out += (f'<use href="#{p}rune" stroke="#ffe1a8" stroke-width="4" opacity="{0.9 * glow:.3f}" '
                f'filter="url(#{p}soft)" transform="translate(0 1.5)"/>')
    out += "</g>"
    if glow > 0.01:
        out += (f'<use href="#{p}rune" stroke="#ff8f3a" stroke-width="12" opacity="{0.6 * glow:.3f}" '
                f'filter="url(#{p}bloom)"/>')
    return out


def plate(p, glow=0.0):
    facets = "".join(f'<path fill="{c}" d="{d}"/>' for c, d in FACETS)
    return (f'<path fill="{RIM}" d="{OCTAGON}"/>{facets}<path fill="{FACE}" d="{PLATE_FACE}"/>'
            f'<path d="{PLATE_LINE}" fill="none" stroke="#d6af6e" stroke-width="1.2" transform="translate(0 1.2)"/>'
            f'<path d="{PLATE_LINE}" fill="none" stroke="#7a5629" stroke-width="1.5"/>'
            + rune(p, glow))


def disc(p):
    """The minimap copy: the same face and rune on a coin, since the button is round."""
    return (f'<defs><linearGradient id="{p}bevel" x1="0" y1="0" x2="1" y2="1">'
            f'<stop offset="0" stop-color="#e6c485"/><stop offset="1" stop-color="#7c5730"/>'
            f'</linearGradient></defs>'
            f'<circle cx="64" cy="64" r="63" fill="{RIM}"/>'
            f'<circle cx="64" cy="64" r="58" fill="url(#{p}bevel)"/>'
            f'<circle cx="64" cy="64" r="52" fill="{FACE}"/>' + rune(p))


def word_geometry(text):
    x, paths = 0, []
    for i, ch in enumerate(text):
        width, d = LETTERS[ch]
        paths.append(f'<g transform="translate({x} 0)">{d}</g>')
        x += width
        if i + 1 < len(text) and " " not in text[i:i + 2]:
            x += PAIR_GAPS.get(text[i:i + 2], DEFAULT_GAP)
    return x, "".join(paths)


def lettering(p, text, glint=None):
    """Raised chiselled capitals in letter units (cap height 66), and their width."""
    width, paths = word_geometry(text)
    return width, (f'<defs><clipPath id="{p}cut"><rect x="-10" y="0" width="{width + 20}" height="{CAP}"/></clipPath>'
                   f'<g id="{p}word" fill="none" stroke-linejoin="miter" stroke-linecap="butt" '
                   f'clip-path="url(#{p}cut)">{paths}</g></defs>'
                   + raised(p, f"{p}word", "stroke", 12, (-20, -20, width + 40, CAP + 40), glint))


WORD_WIDTH = word_geometry("REFACTOR")[0]


def raised(p, ref, paint, width, extent, glint=None):
    """Raised gold metal for any shape in defs: drop shadow, bottom edge, lit top edge, a passing glint.

    paint is "stroke" for the stroked wordmark and "fill" for text. extent is (x, y, w, h) in local units.
    """
    sw = f' stroke-width="{width}"' if paint == "stroke" else ""
    x, y, w, h = extent
    out = (f'<defs><mask id="{p}m" maskUnits="userSpaceOnUse" x="{x}" y="{y}" width="{w}" height="{h}">'
           f'<use href="#{ref}" {paint}="#fff"{sw}/></mask>'
           f'<filter id="{p}sh" x="-10%" y="-30%" width="120%" height="160%">'
           f'<feGaussianBlur stdDeviation="3"/></filter></defs>'
           f'<use href="#{ref}" {paint}="#000"{sw} opacity="0.6" filter="url(#{p}sh)" transform="translate(0 6)"/>'
           f'<use href="#{ref}" {paint}="{GOLD_DARK}"{sw} transform="translate(0 3.5)"/>'
           f'<use href="#{ref}" {paint}="{GOLD_LIGHT}"{sw}/>'
           f'<g mask="url(#{p}m)"><use href="#{ref}" {paint}="{GOLD}"{sw} transform="translate(0 2.2)"/>')
    if glint is not None:
        out += band(glint, y, y + h, 34, 30)
    return out + "</g>"


def band(xc, y0, y1, width, slant):
    """A slanted light band centred on xc, for the glint that crosses metal."""
    return (f'<path fill="#fff8e6" opacity="0.55" d="M{xc - width / 2 + slant} {y0}H{xc + width / 2 + slant}'
            f'L{xc + width / 2 - slant} {y1}H{xc - width / 2 - slant}Z"/>')


def chamfered(w, h, inset, cut):
    i, c = inset, cut
    return f"M{i + c} {i}H{w - i - c}L{w - i} {i + c}V{h - i - c}L{w - i - c} {h - i}H{i + c}L{i} {h - i - c}V{i + c}Z"


def diamond(x, y, r, fill):
    return f'<path fill="{fill}" d="M{x} {y - r}L{x + r} {y}L{x} {y + r}L{x - r} {y}Z"/>'


def backdrop(w, h):
    corners = ((19, 19), (w - 19, 19), (w - 19, h - 19), (19, h - 19))
    return (f'<defs><radialGradient id="bg" cx="50%" cy="50%" r="70%">'
            f'<stop offset="0" stop-color="#2b1d12"/><stop offset="1" stop-color="#0e0906"/>'
            f'</radialGradient></defs>'
            f'<path d="{chamfered(w, h, 0, 24)}" fill="{RIM}"/>'
            f'<path d="{chamfered(w, h, 4, 22)}" fill="url(#bg)"/>'
            f'<path d="{chamfered(w, h, 10, 18)}" fill="none" stroke="#7a5a30" stroke-width="2"/>'
            f'<path d="{chamfered(w, h, 16, 16)}" fill="none" stroke="#3a2a19" stroke-width="1.5"/>'
            + "".join(diamond(x, y, 5, COPPER) for x, y in corners))


def embers(w, h, t, loop, count, seed):
    """Copper sparks rising. Each one finishes a whole number of rises per loop, so the loop is seamless."""
    rng = random.Random(seed)
    crisp, soft = [], []
    for _ in range(count):
        x0 = rng.uniform(40, w - 40)
        rises = rng.choice((2, 3))
        phase, sway_phase = rng.random(), rng.random()
        size, peak = rng.uniform(1.8, 3.8), rng.uniform(0.45, 0.9)
        u = (t * rises / loop + phase) % 1.0
        y = h + 10 - u * (h + 30)
        x = x0 + 9 * math.sin(2 * math.pi * (u + sway_phase))
        a = peak * math.sin(math.pi * u) ** 1.5
        colour = mix(COPPER, "#ffc06a", rng.random())
        crisp.append(f'<g opacity="{a:.3f}">{diamond(round(x, 2), round(y, 2), size, colour)}</g>')
        soft.append(f'<g opacity="{a * 0.8:.3f}">{diamond(round(x, 2), round(y, 2), size * 2.4, colour)}</g>')
    return (f'<defs><filter id="ember" x="-50%" y="-50%" width="200%" height="200%">'
            f'<feGaussianBlur stdDeviation="3"/></filter></defs>'
            f'<g filter="url(#ember)">{"".join(soft)}</g>{"".join(crisp)}')


# README banner -------------------------------------------------------------------------------

BW, BH = 1280, 320
B_LOOP = 10.0
FEATURES = ("Sell junk", "Auto repair", "Fast loot", "Quest progress on nameplates",
            "Bigger merchant window", "Loot feed", "ActionCam profiles", "Copy chat")
ICON_SIZE = 196
WORD_SCALE = 80 / CAP
GROUP_W = ICON_SIZE + 44 + WORD_WIDTH * WORD_SCALE
ICON_X, ICON_Y = (BW - GROUP_W) / 2, (BH - ICON_SIZE) / 2
TEXT_X = ICON_X + ICON_SIZE + 44
WORD_Y = 70


def rune_glow(t, period):
    return 0.1 + 0.9 * (0.5 - 0.5 * math.cos(2 * math.pi * t / period)) ** 2


def sweep(t, start, length, x0, x1):
    u = (t - start) / length
    return None if not 0 <= u <= 1 else x0 + (x1 - x0) * ease(u)


def ticker(t):
    slot = B_LOOP / len(FEATURES)
    i = int(t // slot) % len(FEATURES)
    u = (t - i * slot) / slot
    alpha = ease(u / 0.12) * (1 - ease((u - 0.86) / 0.14))
    tick = ease((u - 0.1) / 0.22)
    flash = max(0.0, 1 - (u - 0.32) / 0.25) if u > 0.32 else 0.0
    slide = 10 * (1 - ease(u / 0.16))
    x, y = TEXT_X + 2, 228
    length = 18.5
    return (f'<rect x="{x}" y="{y}" width="22" height="22" rx="4" fill="#1b130c" stroke="#8a6a38" stroke-width="1.5"/>'
            + (f'<rect x="{x - 3}" y="{y - 3}" width="28" height="28" rx="6" fill="none" stroke="{COPPER}" '
               f'stroke-width="2" opacity="{0.8 * flash * alpha:.3f}"/>' if flash > 0 else "")
            + f'<path d="M{x + 5} {y + 11.5}L{x + 9.5} {y + 16}L{x + 17} {y + 6.5}" fill="none" stroke="{GOLD_LIGHT}" '
              f'stroke-width="3" stroke-linecap="round" stroke-linejoin="round" '
              f'stroke-dasharray="{length * tick:.2f} 100" opacity="{alpha:.3f}"/>'
            + f'<text x="{x + 36 + slide:.2f}" y="{y + 18}" font-family="Noto Serif Display" font-weight="500" '
              f'font-size="22" letter-spacing="0.5" fill="#d8c7a0" opacity="{alpha:.3f}">{FEATURES[i]}</text>')


def banner(t):
    s = WORD_SCALE
    glint = sweep(t, 0.5, 1.4, ICON_X - 120, TEXT_X + WORD_WIDTH * s + 120)
    icon_glint = None if glint is None else (glint - ICON_X) * 128 / ICON_SIZE
    word_glint = None if glint is None else (glint - TEXT_X) / s
    body = backdrop(BW, BH) + embers(BW, BH, t, B_LOOP, 18, 7)
    body += (f'<g transform="translate({ICON_X:.2f} {ICON_Y:.2f}) scale({ICON_SIZE / 128})">'
             f'<defs><mask id="im" maskUnits="userSpaceOnUse" x="0" y="0" width="128" height="128">'
             f'<path d="{OCTAGON}" fill="#fff"/></mask>'
             f'<filter id="ish" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="4"/></filter></defs>'
             f'<path d="{OCTAGON}" fill="#000" opacity="0.6" filter="url(#ish)" transform="translate(0 6)"/>'
             + plate("b", rune_glow(t, B_LOOP / 2))
             + (f'<g mask="url(#im)" opacity="0.35">{band(icon_glint, 0, 128, 22, 20)}</g>' if icon_glint is not None else "")
             + "</g>")
    body += (f'<g transform="translate({TEXT_X:.2f} {WORD_Y}) scale({s:.4f})">'
             + lettering("w", "REFACTOR", word_glint)[1] + "</g>")
    body += (f'<text x="{TEXT_X + 1:.2f}" y="204" font-family="Noto Serif Display" font-weight="500" font-size="30" '
             f'letter-spacing="0.4" fill="{CREAM}">Quality of life for WoW Forever</text>')
    body += ticker(t)
    return svg(BW, BH, body)


# Ko-fi banner --------------------------------------------------------------------------------

KW, KH = 1280, 220
K_LOOP = 4.0
HEART = ("M0.5 0.92C0.1 0.62 0 0.42 0 0.28C0 0.12 0.12 0 0.27 0C0.38 0 0.46 0.06 0.5 0.16"
         "C0.54 0.06 0.62 0 0.73 0C0.88 0 1 0.12 1 0.28C1 0.42 0.9 0.62 0.5 0.92Z")


def heart(cx, cy, size, fill, opacity=1.0):
    return (f'<path d="{HEART}" fill="{fill}" opacity="{opacity:.3f}" '
            f'transform="translate({cx - size / 2:.2f} {cy - size * 0.46:.2f}) scale({size:.2f})"/>')


def steam(x, top, bottom, t, phase):
    points = []
    steps = 24
    for k in range(steps + 1):
        v = k / steps
        y = bottom - v * (bottom - top)
        amp = 2 + 7 * v
        dx = amp * math.sin(2 * math.pi * (v * 1.3 - t / K_LOOP * 2 + phase))
        points.append(f"{x + dx:.2f} {y:.2f}")
    return f'<path d="M{"L".join(points)}" fill="none" stroke="{CREAM}" stroke-width="5" stroke-linecap="round"/>'


def beat(t):
    """Lub-dub, twice per loop."""
    u = (t % (K_LOOP / 2)) / (K_LOOP / 2)
    return 1 + 0.14 * math.exp(-((u - 0.06) / 0.035) ** 2) + 0.09 * math.exp(-((u - 0.2) / 0.035) ** 2)


def mug(t):
    rise = (t % K_LOOP) / K_LOOP
    floating = heart(58 + 10 * math.sin(2 * math.pi * rise), 10 - 50 * rise, 16, KOFI_RED,
                     math.sin(math.pi * rise) ** 1.2 * 0.95)
    size = 30 * beat(t)
    return (f'<defs><linearGradient id="fade" x1="0" y1="1" x2="0" y2="0">'
            f'<stop offset="0" stop-color="#fff" stop-opacity="0.55"/><stop offset="1" stop-color="#fff" stop-opacity="0"/>'
            f'</linearGradient><mask id="steam" maskUnits="userSpaceOnUse" x="-20" y="-80" width="160" height="110">'
            f'<rect x="-20" y="-80" width="160" height="104" fill="url(#fade)"/></mask>'
            f'<filter id="msh" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="3"/></filter></defs>'
            f'<g mask="url(#steam)">{steam(34, -30, 18, t, 0)}{steam(56, -36, 18, t, 0.33)}{steam(78, -30, 18, t, 0.66)}</g>'
            + floating
            + f'<g filter="url(#msh)" opacity="0.6" transform="translate(0 5)"><rect x="-8" y="98" width="136" height="9" rx="4.5"/>'
              f'<path d="M8 30H100V68Q100 98 70 98H38Q8 98 8 68Z"/></g>'
            + f'<circle cx="102" cy="56" r="15" fill="none" stroke="#d9c9a5" stroke-width="9"/>'
            + f'<path d="M8 30H100V68Q100 98 70 98H38Q8 98 8 68Z" fill="#efe2c4"/>'
            + f'<path d="M76 30H100V68Q100 98 70 98H62Q76 90 76 68Z" fill="#dccca8"/>'
            + f'<rect x="3" y="23" width="102" height="10" rx="3" fill="#c99d5e"/>'
            + f'<rect x="3" y="23" width="102" height="3" rx="1.5" fill="#e6c485"/>'
            + heart(52, 63, size, KOFI_RED)
            + f'<rect x="-8" y="98" width="136" height="9" rx="4.5" fill="#a67a42"/>'
            + f'<rect x="-8" y="98" width="136" height="3" rx="1.5" fill="#d9b371"/>')


K_TITLE = "SUPPORT ON KO-FI"
K_LINE = "Refactor is free. Every coffee funds the next update."
K_SCALE = 54 / CAP
K_MUG_SCALE = 0.85
K_TITLE_W = word_geometry(K_TITLE)[0] * K_SCALE
K_MUG_X = (KW - (128 * K_MUG_SCALE + 56 + max(K_TITLE_W, text_width(K_LINE, 25, 0.4)))) / 2
K_TEXT_X = K_MUG_X + 128 * K_MUG_SCALE + 56


def kofi(t):
    glint = sweep(t, 0.6, 1.2, K_TEXT_X - 80, K_TEXT_X + K_TITLE_W + 80)
    body = backdrop(KW, KH) + embers(KW, KH, t, K_LOOP, 10, 11)
    body += f'<g transform="translate({K_MUG_X:.2f} 55) scale({K_MUG_SCALE})">{mug(t)}</g>'
    body += (f'<g transform="translate({K_TEXT_X:.2f} 54) scale({K_SCALE:.4f})">'
             + lettering("k", K_TITLE, None if glint is None else (glint - K_TEXT_X) / K_SCALE)[1] + "</g>")
    body += (f'<text x="{K_TEXT_X + 1:.2f}" y="152" font-family="Noto Serif Display" font-weight="500" font-size="25" '
             f'letter-spacing="0.4" fill="{CREAM}">{K_LINE}</text>')
    return svg(KW, KH, body)


# Outputs -------------------------------------------------------------------------------------

def icon_svg():
    return svg(128, 128, "<title>Refactor</title>" + plate("i"))


def write_tga(im, path):
    im.save(path, compression=None)
    print(f"wrote {path.relative_to(ROOT)} {im.size[0]}x{im.size[1]}")


def build_icons():
    doc = icon_svg()
    (ROOT / "docs/icon.svg").write_text(doc + "\n")
    write_tga(rasterise(doc, 64, 64), ROOT / "Media/Icon64.tga")
    write_tga(rasterise(doc, 32, 32), ROOT / "Media/Icon32.tga")
    # The AddOn list scales the icon into a fixed box, so this copy drops the margin.
    write_tga(rasterise(svg(64, 64, plate("l"), "4 4 120 120"), 64, 64), ROOT / "Media/IconList.tga")
    # Same footprint as the art it replaces (41 px at 11, 10), which was checked centred in game.
    minimap = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    minimap.alpha_composite(rasterise(svg(41, 41, disc("m"), "0 0 128 128"), 41, 41), (11, 10))
    write_tga(minimap, ROOT / "Media/IconMinimap.tga")
    for size in (128, 64):
        rasterise(doc, size, size).save(ROOT / f"docs/Icon{size}.png")
        print(f"wrote docs/Icon{size}.png")
    for size in (512, 256):
        rasterise(doc, size, size).save(ROOT / f"Icon{size}.png")
        print(f"wrote Icon{size}.png")


def animate(draw, w, h, loop, path):
    count = round(loop * FPS)
    with ThreadPoolExecutor() as pool:
        frames = list(pool.map(lambda i: rasterise(draw(i / FPS), w, h), range(count)))
    path.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=round(1000 / FPS), loop=0,
                   quality=86, method=6, minimize_size=True)
    print(f"wrote {path.relative_to(ROOT)} {count} frames {path.stat().st_size // 1024} KB")


def stills():
    out = ROOT / ".preview/branding"
    out.mkdir(parents=True, exist_ok=True)
    for t in (0.0, 0.9, 1.3, 2.5, 3.9):
        rasterise(banner(t), BW, BH).save(out / f"banner-{t:.1f}.png")
    for t in (0.0, 0.1, 1.0, 2.0):
        rasterise(kofi(t), KW, KH).save(out / f"kofi-{t:.1f}.png")
    print(f"wrote stills to {out.relative_to(ROOT)}")


if __name__ == "__main__":
    if "--stills" in sys.argv:
        stills()
    elif "--icons" in sys.argv:
        build_icons()
    else:
        build_icons()
        animate(banner, BW, BH, B_LOOP, ROOT / "docs/media/banner.webp")
        animate(kofi, KW, KH, K_LOOP, ROOT / "docs/media/kofi.webp")
