"""Compare the step folders made by PluginsTxtSnapshot.ps1.

Each step is a folder holding info.txt. Steps are taken in the order of their number prefix (2-x before 10-x).
For each pair of steps it reports:
  - whether Plugins.txt was rewritten (its modified time changed) and how its lines changed,
  - whether ContentCatalog.txt changed, field by field.

Usage:
  python compare_snapshots.py [FOLDER] [--verbose]

FOLDER defaults to PluginsTxtTest on your Desktop. --verbose also writes compare.log in FOLDER.
Exit codes: 0 compared; 1 folder missing or fewer than two steps; 2 wrong arguments.
It only reads the snapshot folders.
"""
import argparse
import difflib
import json
import os
import re
import sys
from pathlib import Path

LOG = []
MISSING = object()


def log(msg):
    LOG.append(msg)


def lines(p):
    if not p.exists():
        return None
    return p.read_text(encoding="utf-8", errors="replace").splitlines()


def mtime(step, name):
    info = step / "info.txt"
    if not info.exists():
        return None
    m = re.search(re.escape(name) + r": modified ([0-9-]+ [0-9:]+)", info.read_text(encoding="utf-8", errors="replace"))
    return m.group(1) if m else None


def desktop():
    """The real Desktop folder (OneDrive can move it), as PluginsTxtSnapshot.ps1 finds it."""
    if os.name == "nt":
        try:
            import ctypes
            from ctypes import wintypes

            class GUID(ctypes.Structure):
                _fields_ = [("d1", wintypes.DWORD), ("d2", wintypes.WORD), ("d3", wintypes.WORD),
                            ("d4", ctypes.c_ubyte * 8)]

            fid = GUID(0xB4BFCC3A, 0xDB2C, 0x424C, (ctypes.c_ubyte * 8)(0xB0, 0x29, 0x7F, 0xE9, 0x9A, 0x87, 0xC6, 0x41))
            path = ctypes.c_wchar_p()
            if ctypes.windll.shell32.SHGetKnownFolderPath(ctypes.byref(fid), 0, None, ctypes.byref(path)) == 0:
                result = path.value
                ctypes.windll.ole32.CoTaskMemFree(path)
                if result:
                    return Path(result)
        except (OSError, AttributeError):
            pass
    return Path(os.path.expanduser("~")) / "Desktop"


def step_key(p):
    """Sort steps by their number prefix (2-x before 10-x), then by name."""
    m = re.match(r"(\d+)", p.name)
    return (int(m.group(1)) if m else float("inf"), p.name)


def catalog_diff(pa, pb):
    try:
        ja = json.loads(pa.read_text(encoding="utf-8-sig"))
        jb = json.loads(pb.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as ex:
        return [f"    could not read as JSON ({ex}); compare the two files by hand"]
    if not isinstance(ja, dict) or not isinstance(jb, dict):
        return ["    not the expected JSON object; compare the two files by hand"]
    out = []
    for k in sorted(set(ja) | set(jb)):
        va, vb = ja.get(k, MISSING), jb.get(k, MISSING)
        if va == vb:
            continue
        if isinstance(va, dict) and isinstance(vb, dict):
            fields = [f for f in sorted(set(va) | set(vb)) if va.get(f, MISSING) != vb.get(f, MISSING)]
            out.append(f"    {k}: {', '.join(fields) or 'entry'} changed")
        else:
            out.append(f"    {k}: {'added' if va is MISSING else 'removed' if vb is MISSING else 'changed'}")
    return out


def changed_lines(pa, pb):
    """The removed (-) and added (+) lines, from the diff's change blocks only (no file headers)."""
    out = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(a=pa, b=pb, autojunk=False).get_opcodes():
        if tag in ("delete", "replace"):
            out += ["-" + x for x in pa[i1:i2]]
        if tag in ("insert", "replace"):
            out += ["+" + x for x in pb[j1:j2]]
    return out


def compare(a, b):
    print(f"===== {a.name} -> {b.name}")
    ta, tb = mtime(a, "Plugins.txt"), mtime(b, "Plugins.txt")
    pa, pb = lines(a / "Plugins.txt"), lines(b / "Plugins.txt")
    log(f"{a.name} -> {b.name}: Plugins.txt modified {ta} -> {tb}")
    if pa is None or pb is None:
        print("Plugins.txt: missing from one of the steps")
    elif ta is None or tb is None:
        which = " and ".join(s.name for s, t in ((a, ta), (b, tb)) if t is None)
        print(f"Plugins.txt: modified time unknown for {which} (see info.txt there); can't tell whether it was "
              "rewritten. Take that step's snapshot again.")
    else:
        rewritten = ta != tb
        if pa == pb:
            print(f"Plugins.txt: {'rewritten (new modified time), same text' if rewritten else 'not rewritten'}")
        elif not rewritten:
            print(f"Plugins.txt: text differs but the modified time didn't change ({ta}); one copy may have been "
                  "taken while the file was being written. Compare the two copies by hand:")
            for d in changed_lines(pa, pb):
                print("   ", d)
        else:
            bare = lambda ls: sorted(x.lstrip("*") for x in ls)
            if sorted(pa) == sorted(pb):
                kind = "same lines, new order"
            elif bare(pa) == bare(pb):
                kind = "plugins enabled or disabled"
            else:
                kind = "lines added or removed"
            print(f"Plugins.txt: rewritten ({kind})")
            for d in changed_lines(pa, pb):
                print("   ", d)
    ca, cb = a / "ContentCatalog.txt", b / "ContentCatalog.txt"
    if ca.exists() and cb.exists():
        if ca.read_bytes() == cb.read_bytes():
            print("ContentCatalog.txt: not changed")
        else:
            print("ContentCatalog.txt: changed")
            for d in catalog_diff(ca, cb):
                print(d)
    else:
        print("ContentCatalog.txt: missing from one of the steps")


def main(argv):
    # Plugin names can hold any character; never crash on a console or file that can't show them.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="backslashreplace")
        except (AttributeError, ValueError):
            pass
    desk = desktop() / "PluginsTxtTest"
    ap = argparse.ArgumentParser(description="Compare PluginsTxtSnapshot.ps1 step folders.")
    ap.add_argument("folder", nargs="?", default=str(desk), help="snapshot folder (default: %(default)s)")
    ap.add_argument("--verbose", action="store_true", help="also write compare.log in the folder")
    args = ap.parse_args(argv)
    root = Path(args.folder)

    def fail(msg):
        print(f"compare_snapshots: {msg}", file=sys.stderr)
        log(f"FAILED: {msg}")
        write_log(root, args.verbose)
        return 1

    if not root.is_dir():
        return fail(f"folder not found: {root}. Pass the folder PluginsTxtSnapshot.ps1 wrote to.")
    try:
        steps = sorted((p for p in root.iterdir() if p.is_dir() and (p / "info.txt").exists()), key=step_key)
        log(f"folder {root}: steps {[s.name for s in steps]}")
        if len(steps) < 2:
            return fail(f"{root} has {len(steps)} step folder(s) with info.txt; take at least two snapshots first.")
        for a, b in zip(steps, steps[1:]):
            compare(a, b)
    except OSError as ex:
        where = ex.filename or root
        return fail(f"could not read {where} ({ex.strerror or ex}). If the folder is on OneDrive, make it "
                    "'Always keep on this device', or copy it to a local folder and pass that folder.")
    write_log(root, args.verbose)
    return 0


def write_log(root, verbose):
    """With --verbose, write compare.log in the folder (or the current folder if that one is missing)."""
    if not verbose:
        return
    target = (root if root.is_dir() else Path.cwd()) / "compare.log"
    try:
        target.write_text("\n".join(LOG) + "\n", encoding="utf-8")
        print(f"log: {target}")
    except OSError as ex:
        print(f"compare_snapshots: could not write {target} ({ex})", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
