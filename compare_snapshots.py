"""Compare the step folders made by PluginsTxtSnapshot.ps1.

For each pair of steps in name order it reports:
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


def catalog_diff(pa, pb):
    try:
        ja = json.loads(pa.read_text(encoding="utf-8"))
        jb = json.loads(pb.read_text(encoding="utf-8"))
    except (OSError, ValueError) as ex:
        return [f"    could not read as JSON ({ex}); compare the two files by hand"]
    out = []
    for k in sorted(set(ja) | set(jb)):
        va, vb = ja.get(k), jb.get(k)
        if va == vb:
            continue
        if isinstance(va, dict) and isinstance(vb, dict):
            fields = [f for f in sorted(set(va) | set(vb)) if va.get(f) != vb.get(f)]
            out.append(f"    {k}: {', '.join(fields)} changed")
        else:
            out.append(f"    {k}: {'added' if va is None else 'removed' if vb is None else 'changed'}")
    return out


def compare(a, b):
    print(f"===== {a.name} -> {b.name}")
    ta, tb = mtime(a, "Plugins.txt"), mtime(b, "Plugins.txt")
    pa, pb = lines(a / "Plugins.txt"), lines(b / "Plugins.txt")
    log(f"{a.name} -> {b.name}: Plugins.txt modified {ta} -> {tb}")
    if pa is None or pb is None:
        print("Plugins.txt: missing from one of the steps")
    else:
        rewritten = ta != tb
        if pa == pb:
            print(f"Plugins.txt: {'rewritten (new modified time), same text' if rewritten else 'not rewritten'}")
        else:
            kind = "same lines, new order" if sorted(pa) == sorted(pb) else "lines added or removed"
            print(f"Plugins.txt: rewritten ({kind})")
            for d in difflib.unified_diff(pa, pb, lineterm="", n=0):
                if d.startswith(("+", "-")) and not d.startswith(("+++", "---")):
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
    desk = Path(os.path.expanduser("~")) / "Desktop" / "PluginsTxtTest"
    ap = argparse.ArgumentParser(description="Compare PluginsTxtSnapshot.ps1 step folders.")
    ap.add_argument("folder", nargs="?", default=str(desk), help="snapshot folder (default: %(default)s)")
    ap.add_argument("--verbose", action="store_true", help="also write compare.log in the folder")
    args = ap.parse_args(argv)
    root = Path(args.folder)
    if not root.is_dir():
        print(f"compare_snapshots: folder not found: {root}. Pass the folder PluginsTxtSnapshot.ps1 wrote to.",
              file=sys.stderr)
        return 1
    steps = sorted(p for p in root.iterdir() if p.is_dir())
    log(f"folder {root}: steps {[s.name for s in steps]}")
    if len(steps) < 2:
        print(f"compare_snapshots: {root} has {len(steps)} step folder(s); take at least two snapshots first.",
              file=sys.stderr)
        return 1
    for a, b in zip(steps, steps[1:]):
        compare(a, b)
    if args.verbose:
        (root / "compare.log").write_text("\n".join(LOG) + "\n", encoding="utf-8")
        print(f"log: {root / 'compare.log'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
