"""Layout preview: prepares assets, runs Tools/Preview/preview.lua, writes an index page.

  python3 Tools/Preview/run.py [--out DIR] [scenario ...]

Refactor's own TGA art is converted to PNG. Blizzard's atlases are not on disk, so their names
and sizes come from hated-wow-mcp's Forever atlas index (~/.cache/hated-wow-mcp) and the page
draws a CSS stand-in for each. Nothing here is packaged; the TOC never names Tools/.
"""
import base64
import glob
import json
import os
import shutil
import subprocess
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ATLAS_INDEX = os.path.expanduser("~/.cache/hated-wow-mcp/atlas-index-forever.json")


def main(argv):
    out = os.path.join(ROOT, ".preview")
    scenarios = []
    shots = False
    args = list(argv)
    while args:
        value = args.pop(0)
        if value == "--out":
            out = os.path.abspath(args.pop(0))
        elif value == "--shots":
            shots = True
        else:
            scenarios.append(value)
    assets = os.path.join(out, "assets")
    os.makedirs(assets, exist_ok=True)
    with open(os.path.join(assets, "index.txt"), "w") as index:
        for tga in sorted(glob.glob(os.path.join(ROOT, "Media", "*.tga"))):
            name = os.path.splitext(os.path.basename(tga))[0]
            png = os.path.join(assets, name + ".png")
            if not os.path.exists(png) or os.path.getmtime(png) < os.path.getmtime(tga):
                Image.open(tga).save(png)
            # Inlined: a CSS mask from a file:// URL is cross-origin to the browser and draws
            # nothing, and tinted art is drawn as a mask.
            with open(png, "rb") as handle:
                data = base64.b64encode(handle.read()).decode("ascii")
            index.write("%s data:image/png;base64,%s\n" % (name.lower(), data))
    atlases = os.path.join(out, "atlases.lua")
    if os.path.exists(ATLAS_INDEX) and (not os.path.exists(atlases)
                                        or os.path.getmtime(atlases) < os.path.getmtime(ATLAS_INDEX)):
        with open(ATLAS_INDEX) as handle:
            data = json.load(handle)
        seen = {}
        for atlas in data["atlases"]:
            name = atlas["name"].lower()
            if name not in seen:
                seen[name] = (atlas["right"] - atlas["left"], atlas["bottom"] - atlas["top"], atlas["fileDataID"])
        with open(atlases, "w") as handle:
            handle.write("return {\n")
            for name, (w, h, file_id) in sorted(seen.items()):
                handle.write('[%s]={%d,%d,%d},\n' % (json.dumps(name), w, h, file_id))
            handle.write("}\n")
    result = subprocess.run(["sh", "Tools/dev-env.sh", "lua5.1", "Tools/Preview/preview.lua", out] + scenarios,
                            cwd=ROOT)
    pages = sorted(p for p in os.listdir(out) if p.endswith(".html") and p != "index.html")
    with open(os.path.join(out, "index.html"), "w") as handle:
        handle.write("<!doctype html><meta charset=utf-8><title>Refactor preview</title>"
                     "<body style='font:14px sans-serif;background:#111;color:#ccc'><h3>Refactor preview</h3><ul>")
        for page in pages:
            handle.write("<li><a style='color:#9cf' href='%s'>%s</a></li>" % (page, page[:-5]))
        handle.write("</ul></body>")
    if shots:
        # PNGs of every page, for looking at without a browser pane. Any Chromium works.
        browser = next((b for b in ("brave", "chromium", "google-chrome") if shutil.which(b)), None)
        if browser:
            os.makedirs(os.path.join(out, "shots"), exist_ok=True)
            for page in pages:
                target = os.path.join(out, "shots", page[:-5] + ".png")
                subprocess.run([browser, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                                "--window-size=1600,926", "--screenshot=" + target,
                                "file://" + os.path.join(out, page)], capture_output=True, timeout=60)
    print("preview:", os.path.join(out, "index.html"))
    return result.returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
