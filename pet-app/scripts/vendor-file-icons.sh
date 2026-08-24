#!/bin/sh
# Vendors Material Icon Theme's file/folder icons into Puck's resources, so the
# editor's file tree shows the same icons VS Code users already read at a
# glance instead of one generic SF Symbol per kind.
#
# Source: https://github.com/material-extensions/vscode-material-icon-theme
# MIT (Copyright (c) 2025 Material Extensions) -- the license is copied in
# alongside the icons, which is what MIT asks for when redistributing.
#
# ## Why the released .vsix and not the git repo
#
# The repo stores the mapping as TypeScript (src/core/icons/fileIcons.ts,
# 91KB) that has to be executed to resolve patterns into real extension lists.
# Every release ships dist/material-icons.json with that already done --
# extension -> icon name, filename -> icon name, folder name -> icon name --
# so vendoring the artifact skips reimplementing their resolver.
#
# ## Why NSImage and no converter
#
# NSImage loads SVG natively on macOS (_NSSVGImageRep) and keeps it vector, so
# the .svg files ship as-is. No rasterizing, no SVG library, nothing to keep in
# sync with a renderer.
#
# Run this only to change the pinned version, then commit what it writes.
set -e
cd "$(dirname "$0")/.."

VERSION="5.37.0"
DEST="Puck/Resources/FileIcons"
REPO="material-extensions/vscode-material-icon-theme"

if ! command -v gh > /dev/null 2>&1; then
    echo "error: gh is required to download the pinned release." >&2
    exit 1
fi
if ! command -v python3 > /dev/null 2>&1; then
    echo "error: python3 is required to trim the icon map." >&2
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "downloading material-icon-theme v$VERSION"
gh release download "v$VERSION" --repo "$REPO" --dir "$WORK" --pattern '*.vsix'
unzip -q "$WORK"/*.vsix -d "$WORK/x"
gh api "repos/$REPO/contents/LICENSE" --jq '.content' | base64 -d > "$WORK/LICENSE"

SOURCE="$WORK/x/extension"

rm -rf "$DEST"
mkdir -p "$DEST/icons"
cp "$WORK/LICENSE" "$DEST/LICENSE"

# Trim: the shipped theme carries light and high-contrast variants plus
# language-id mappings that only mean something inside VS Code. Keeping the
# four maps the file tree actually reads cuts 450KB to a fraction, and copying
# only the icons those maps reference cuts 5MB the same way.
python3 - "$SOURCE" "$DEST" <<'PYTHON'
import json, shutil, sys
from pathlib import Path

source, dest = Path(sys.argv[1]), Path(sys.argv[2])
theme = json.loads((source / "dist" / "material-icons.json").read_text())

kept = {
    "file": theme["file"],
    "folder": theme["folder"],
    "folderExpanded": theme["folderExpanded"],
    "fileExtensions": theme["fileExtensions"],
    "fileNames": theme["fileNames"],
    "folderNames": theme["folderNames"],
    "folderNamesExpanded": theme["folderNamesExpanded"],
}

referenced = {kept["file"], kept["folder"], kept["folderExpanded"]}
for key in ("fileExtensions", "fileNames", "folderNames", "folderNamesExpanded"):
    referenced.update(kept[key].values())

definitions = theme["iconDefinitions"]
copied = 0
for name in sorted(referenced):
    icon = definitions.get(name)
    if not icon:
        continue
    svg = source / "icons" / Path(icon["iconPath"]).name
    if not svg.exists():
        continue
    shutil.copy(svg, dest / "icons" / svg.name)
    copied += 1

(dest / "icon-map.json").write_text(json.dumps(kept, separators=(",", ":"), sort_keys=True))
print(f"  {copied} icons, "
      f"{len(kept['fileExtensions'])} extensions, {len(kept['fileNames'])} filenames, "
      f"{len(kept['folderNames'])} folder names")
PYTHON

echo "vendored -> $DEST ($(du -sh "$DEST" | cut -f1))"
