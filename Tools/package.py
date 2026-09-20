"""Create a deterministic install archive from the explicit TOC, never ship dev tools."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

root = Path(__file__).resolve().parent.parent
files = ["Refactor.toc", "README.md", "CHANGELOG.md", "Libs/NOTICE.md"]
# Art is referenced by the theme, not by the TOC, so it is listed explicitly.
files += sorted(str(path.relative_to(root)) for path in (root / "Media").glob("*.tga"))
for line in (root / "Refactor.toc").read_text().splitlines():
    line = line.strip().replace("\\", "/")
    # Restore.lua is one machine's captured saved variables; shipping it would ship them.
    if line and not line.startswith("#") and line != "Restore.lua":
        files.append(line)
assert len(files) == len(set(files)), "duplicate package file"
out = root / ".release/Refactor-retail.zip"
out.parent.mkdir(exist_ok=True)
with ZipFile(out, "w", compression=ZIP_DEFLATED) as archive:
    for name in files:
        file = (root / name).resolve()
        assert file.is_relative_to(root) and file.is_file(), f"missing or unsafe package file: {name}"
        info = ZipInfo("Refactor/" + name, (2026, 9, 17, 0, 0, 0))
        info.compress_type = ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        archive.writestr(info, file.read_bytes())
with ZipFile(out) as archive:
    assert archive.testzip() is None
print(f"Packaged and verified {len(files)} files: {out}")
