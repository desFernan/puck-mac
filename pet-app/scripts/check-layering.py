#!/usr/bin/env python3
"""Fails when a lower layer names a type from a higher one.

Puck is one module. Every folder can see every other folder, so "the movement
engine must not know about the chat window" is a thing people remember rather
than a thing the compiler checks -- and what actually happened is that types
got filed under whichever feature needed them first, and the next feature to
need one reached across for it. Six pairs of folders ended up pointing at each
other that way.

Splitting into real modules would enforce this, and would also mean marking
most of forty thousand lines `public` for the privilege. This is the same
check for the price of a script: the order the layers go in is written down in
scripts/puck-layers.txt, and an edge that runs the wrong way up it fails the
build.

Only top-level declarations count as owned by a layer. Four different types
here are called `Outcome` and each is nested in its own enclosing type; a
check that counted those would report cycles that do not exist.

Usage: check-layering.py [layers file]
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAYERS = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "scripts/puck-layers.txt"

DECLARATION = re.compile(
    r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:public\s+|internal\s+|package\s+|final\s+)*"
    r"(?:class|struct|enum|protocol|actor|typealias)\s+(\w+)",
    re.M,
)


def read_layers():
    """Layer names lowest first, then the edges recorded as allowed anyway."""
    order, allowed = [], set()
    for line in LAYERS.read_text().split("\n"):
        line = line.split("#")[0].strip()
        if not line:
            continue
        if "->" in line:
            lower, _, higher = line.partition("->")
            allowed.add((lower.strip(), higher.strip()))
        else:
            order.append(line)
    return order, allowed


def strip_swift(source):
    """Comments and string literals gone.

    Both carry English words that are also type names -- the string table has
    a "Toy size" in it, and `Toy` is a type -- and counting those reported the
    localisation table as depending on the movement engine.
    """
    source = re.sub(r'"""(?:.|\n)*?"""', '""', source)
    source = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', source)
    source = re.sub(r"/\*(?:.|\n)*?\*/", "", source)
    return re.sub(r"//[^\n]*", "", source)


def swift_files(layer):
    return sorted((ROOT / "Puck" / layer).rglob("*.swift"))


def owners(order):
    """Top-level type name -> the layer that declares it."""
    owner = {}
    for layer in order:
        for path in swift_files(layer):
            for line in strip_swift(path.read_text(encoding="utf8")).split("\n"):
                # Top level only: a nested type belongs to its enclosing one,
                # and several layers nest a type of the same name.
                if line[:1].strip() == "" and line[:1] != "":
                    continue
                match = DECLARATION.match(line)
                if match:
                    owner.setdefault(match.group(1), layer)
    return owner


def main():
    order, allowed = read_layers()
    missing = [layer for layer in order if not (ROOT / "Puck" / layer).is_dir()]
    present = {d.name for d in (ROOT / "Puck").iterdir() if d.is_dir() and d.name != "Resources"}
    unlisted = sorted(present - set(order))
    if missing or unlisted:
        print("error: scripts/puck-layers.txt no longer matches the tree.", file=sys.stderr)
        for layer in missing:
            print(f"  listed but gone: {layer}", file=sys.stderr)
        for layer in unlisted:
            print(f"  in the tree but unlisted: {layer}", file=sys.stderr)
        print("\nAdd it at the height it belongs, or drop the line.", file=sys.stderr)
        return 1

    rank = {layer: index for index, layer in enumerate(order)}
    owner = owners(order)
    violations = []
    for layer in order:
        for path in swift_files(layer):
            source = strip_swift(path.read_text(encoding="utf8"))
            for name in sorted(set(re.findall(r"\b([A-Z]\w+)\b", source))):
                above = owner.get(name)
                if above is None or above == layer:
                    continue
                if rank[above] > rank[layer] and (layer, above) not in allowed:
                    violations.append((path.relative_to(ROOT).as_posix(), name, above, layer))

    if violations:
        print("error: these reach up the layers rather than down them:", file=sys.stderr)
        for path, name, above, layer in violations:
            print(f"  {path}\n      names {name}, which belongs to {above} -- above {layer}", file=sys.stderr)
        print(file=sys.stderr)
        print("Either the type is filed under the feature that first needed it", file=sys.stderr)
        print("rather than under what it is -- move it down -- or the dependency", file=sys.stderr)
        print(f"is real and belongs in {LAYERS.relative_to(ROOT)} as an allowed edge.", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
