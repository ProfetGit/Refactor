#!/usr/bin/env python3
"""Rewrite Restore.lua from the saved variables the Forever client last wrote.

The client writes SavedVariables correctly and never reads them back (beta 1.60.1.69813,
verified with two throwaway addons and a hand-planted file), so every session starts blank.
The written file is already a Lua table literal, so capturing it is a rename of the two
assignments onto the addon's private table: no global write, and Core/Namespace only uses
them when the client handed back nothing.

Run it after a session ends. With --watch it waits for the client to write and captures
each time, which is what makes settings survive without remembering to run anything.
"""
import glob
import io
import os
import re
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Discovered, never hard coded: the account and character folders carry a WoW account id and
# a character name, and this repo is public. REFACTOR_FOREVER_WTF overrides the search.
WTF_GLOB = os.path.join(
    os.path.expanduser("~"),
    ".local/share/Steam/steamapps/compatdata/*/pfx/drive_c",
    "Program Files (x86)/World of Warcraft/_classic_beta_/WTF",
)


def wtf_root():
    override = os.environ.get("REFACTOR_FOREVER_WTF")
    if override:
        return override
    found = sorted(glob.glob(WTF_GLOB))
    return found[0] if found else None


def saved_files():
    """The account file, then the character file of the most recently played character."""
    root = wtf_root()
    if not root:
        return []
    account = sorted(glob.glob(os.path.join(root, "Account/*/SavedVariables/Refactor.lua")))
    character = sorted(
        glob.glob(os.path.join(root, "Account/*/*/*/SavedVariables/Refactor.lua")),
        key=os.path.getmtime, reverse=True)
    return [
        ("RefactorDB", "restoreAccount", account[0] if account else None),
        ("RefactorCharDB", "restoreCharacter", character[0] if character else None),
    ]


HEADER = io.open(os.path.join(ROOT, "Restore.lua"), encoding="utf-8").read().split("local _, R = ...")[0]


def body(global_name, field, path):
    if not path or not os.path.exists(path):
        return "R.%s = nil\n" % field
    text = io.open(path, encoding="utf-8").read()
    # The file is "<Global> = {\n...\n}\n". Only the assignment target changes.
    match = re.search(r"^%s\s*=\s*(\{.*)" % re.escape(global_name), text, re.S | re.M)
    if not match:
        return "R.%s = nil\n" % field
    table = match.group(1).rstrip()
    if table in ("{", "nil") or table == "{}":
        return "R.%s = nil\n" % field
    return "R.%s = %s\n" % (field, table)


def capture():
    parts = [HEADER, "local _, R = ...\n\n"]
    for global_name, field, path in saved_files():
        parts.append(body(global_name, field, path))
    text = "".join(parts)
    target = os.path.join(ROOT, "Restore.lua")
    if io.open(target, encoding="utf-8").read() == text:
        return False
    io.open(target, "w", encoding="utf-8").write(text)
    return True


def newest():
    stamps = []
    for _, _, path in saved_files():
        stamps.append(os.path.getmtime(path) if path and os.path.exists(path) else 0)
    return tuple(stamps)


def main():
    if "--watch" not in sys.argv:
        print("captured" if capture() else "unchanged")
        return 0
    print("watching %s" % wtf_root())
    seen = None
    while True:
        stamps = newest()
        if stamps != seen:
            seen = stamps
            if capture():
                print("%s captured" % time.strftime("%H:%M:%S"))
                sys.stdout.flush()
        time.sleep(5)


if __name__ == "__main__":
    sys.exit(main())
