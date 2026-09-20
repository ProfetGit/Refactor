"""Index Blizzard's exported declarations without executing its Lua code.

This is explicitly source evidence, not a client Probe dump. Legacy symbols are
included only with a reviewed Mainline/shared source reference in legacy-api.json.
A global the client exports but no Blizzard UI file calls can enter through
client-api.json, naming the client index that verified it and the build it was
verified at, which has to be the build this index targets.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
args = parser.parse_args()
root = args.source.resolve()
commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
index = {
    "schema": 1, "flavor": "retail", "version": "12.1.0", "build": "69814", "interface": 120100,
    "provenance": "blizzard-ui-source", "runtimeVerified": False,
    "source": "https://github.com/Gethe/wow-ui-source", "commit": commit,
    "symbols": {}, "widgetMethods": {},
}
docs = root / "Interface/AddOns/Blizzard_APIDocumentationGenerated"
for path in sorted(docs.glob("*.lua")):
    text = path.read_text()
    header = text.split("Functions =", 1)[0]
    namespace = re.search(r'Namespace\s*=\s*"([^"]+)"', header)
    script_object = 'Type = "ScriptObject"' in header
    entries = re.finditer(r'Name\s*=\s*"([^"]+)"\s*,\s*Type\s*=\s*"Function"', text)
    for entry in entries:
        name = (namespace[1] + "." if namespace else "") + entry[1]
        evidence = {"path": str(path.relative_to(root)), "line": text.count("\n", 0, entry.start()) + 1}
        if script_object:
            index["widgetMethods"].setdefault(entry[1], evidence)
        else:
            index["symbols"][name] = evidence
legacy_path = Path("Data/legacy-api.json")
if legacy_path.exists():
    for name, evidence in json.loads(legacy_path.read_text()).items():
        text = (root / evidence["path"]).read_text()
        needle = evidence.get("needle", name)
        if needle not in text:
            raise SystemExit(f"Legacy reference missing: {name}: {evidence}")
        index["symbols"][name] = {
            "path": evidence["path"], "line": text.count("\n", 0, text.index(needle)) + 1,
            "kind": "source-reference",
        }
client_path = Path("Data/client-api.json")
if client_path.exists():
    for name, evidence in json.loads(client_path.read_text()).items():
        if evidence.get("build") != index["build"] or not evidence.get("verifiedBy"):
            raise SystemExit(f"Client reference needs verifiedBy and this build: {name}: {evidence}")
        index["symbols"][name] = {
            "kind": "client-index", "verifiedBy": evidence["verifiedBy"], "build": evidence["build"],
            "note": evidence.get("note", ""),
        }
Path("Data/api-retail.json").write_text(json.dumps(index, indent=2, sort_keys=True) + "\n")
print(f"Indexed {len(index['symbols'])} declarations/references at {commit}; not a runtime Probe.")
