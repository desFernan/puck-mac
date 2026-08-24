#!/bin/sh
# Fails if an app bundle is missing a resource the code looks up by name at
# runtime.
#
# A missing one is not a build error: Bundle.url(forResource:) just returns nil
# and the feature fails the moment somebody uses it. That is exactly how
# PuckClient shipped without the ACP agents (every edit answered
# agentScriptMissing) and later without the file icons -- the Puck target
# sources the whole Puck/ folder and picks them up implicitly, while PuckClient
# lists its files one by one and had not been told.
#
# The unit tests cannot catch it either: they resolve against the test bundle,
# which is built from the Puck target and therefore always has everything. So
# both scripts that produce app bundles call this one.
#
# Usage: scripts/check-resources.sh <products-directory>
set -e

PRODUCTS="$1"
if [ -z "$PRODUCTS" ]; then
    echo "usage: $0 <products-directory>" >&2
    exit 2
fi

failed=0
check() {
    if [ ! -e "$PRODUCTS/$1.app/Contents/Resources/$2" ]; then
        echo "error: $1.app is missing Resources/$2" >&2
        echo "       Add it to that target's sources in project.yml." >&2
        failed=1
    fi
}

# PuckClient runs code_editor and shows the editor pane, so it needs both.
check PuckClient acp-claude.mjs
check PuckClient acp-codex.mjs
check PuckClient FileIcons/icon-map.json
check Puck Avatars
# The island's one drawn background. PuckClient is the app that shows the
# island; Puck picks the folder up implicitly.
check PuckClient TankBackgrounds/seabed.png

exit $failed
