#!/usr/bin/env python3
"""Fails when a new file lands in a folder PuckClient sources file by file.

Both apps compile out of one tree. Puck's target takes whole folders;
PuckClient's names files one at a time, because it wants some of Puck/Bridge
and some of Puck/Tools and not the rest. That list is kept by hand and nothing
has ever compared it against the tree, so a file added to one of those folders
is simply missing from PuckClient until somebody notices -- which is how the
app once shipped without the ACP scripts and failed every code edit.

Only folders PuckClient already draws from individually are checked. A folder
it takes nothing from is Puck's alone and needs no decision. Within the ones it
does draw from, every file must be either listed in project.yml or written down
here as deliberately left out, so that adding one forces the choice to be made
and recorded rather than defaulted to "absent".

Usage: check-client-sources.py [project.yml] [omissions file]
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "project.yml"
OMISSIONS = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "scripts/puckclient-omitted-sources.txt"


def client_source_paths(project_text):
    """The `- path:` entries under PuckClient's `sources:`.

    Counted by indentation rather than parsed with a YAML library: this runs
    wherever the test script does, and a dependency would cost more than
    reading a list of paths is worth.
    """
    lines = project_text.split("\n")
    try:
        start = next(i for i, line in enumerate(lines) if line.strip() == "PuckClient:")
    except StopIteration:
        raise SystemExit("check-client-sources: no PuckClient target in project.yml")

    paths = []
    in_sources = False
    for line in lines[start:]:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if in_sources and indent <= 4 and not stripped.startswith("-"):
            break
        if stripped == "sources:":
            in_sources = True
            continue
        if in_sources and stripped.startswith("- path:"):
            paths.append(stripped[len("- path:"):].strip())
    return paths


def unlisted_files(sourced):
    """Files in a partially-sourced folder that PuckClient does not name."""
    named = {p for p in sourced if p.endswith(".swift")}
    folders = sorted({p.rsplit("/", 1)[0] for p in named})
    unlisted = []
    for folder in folders:
        for path in sorted((ROOT / folder).glob("*.swift")):
            relative = path.relative_to(ROOT).as_posix()
            if relative not in named:
                unlisted.append(relative)
    return unlisted


def read_omissions():
    if not OMISSIONS.exists():
        return set()
    return {
        line.strip()
        for line in OMISSIONS.read_text().split("\n")
        if line.strip() and not line.strip().startswith("#")
    }


def main():
    unlisted = unlisted_files(client_source_paths(PROJECT.read_text()))
    acknowledged = read_omissions()

    undecided = [path for path in unlisted if path not in acknowledged]
    if undecided:
        print("error: PuckClient names its sources one by one, and these are in a", file=sys.stderr)
        print("       folder it draws from but are neither listed nor recorded as", file=sys.stderr)
        print("       deliberately left out:", file=sys.stderr)
        for path in undecided:
            print(f"  {path}", file=sys.stderr)
        print(file=sys.stderr)
        print("Add each to PuckClient's sources in project.yml if that app needs it,", file=sys.stderr)
        print(f"or to {OMISSIONS.relative_to(ROOT)} if it belongs to Puck alone.", file=sys.stderr)
        return 1

    stale = sorted(acknowledged - set(unlisted))
    if stale:
        print("error: these are recorded as deliberately left out of PuckClient, but", file=sys.stderr)
        print("       are now either gone or sourced by it:", file=sys.stderr)
        for path in stale:
            print(f"  {path}", file=sys.stderr)
        print(f"\nDrop them from {OMISSIONS.relative_to(ROOT)}.", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
