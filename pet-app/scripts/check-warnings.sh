#!/bin/sh
# Fails when a build logged a warning in this project's own sources.
#
# Why a script rather than SWIFT_TREAT_WARNINGS_AS_ERRORS: the vendored
# CodeEdit/SwiftTerm packages warn for their own reasons and would take the
# build down with them, and a new Xcode's deprecations would break every
# checkout on the day it shipped rather than when someone chose to deal with
# them.
#
# Why it is needed at all: warnings only appear for files the compiler
# actually recompiled, so an incremental build shows none of the ones already
# in the tree. That is how a commit claiming to have fixed 68 of them had
# really fixed the two files that happened to rebuild.
#
# Usage: scripts/check-warnings.sh <build-log>
set -e

LOG="$1"
if [ ! -f "$LOG" ]; then
    echo "usage: $0 <build-log>" >&2
    exit 2
fi

# Known and deliberate. Each line here is a warning somebody decided to keep,
# and the reason lives at the code it points at.
#
# - LaunchAppHandler: NSWorkspace has no by-display-name lookup that isn't
#   deprecated, and no replacement was ever shipped.
ALLOWED='LaunchAppHandler\.swift.*fullPath\(forApplication:\)'

grep "warning:" "$LOG" \
    | grep -E "pet-app/(Puck|PuckClient|PuckTests)/" \
    | grep -vE "$ALLOWED" \
    | sort -u > /tmp/puck-warnings.$$ || true

count=$(wc -l < /tmp/puck-warnings.$$ | tr -d ' ')
if [ "$count" != "0" ]; then
    echo "error: $count warning(s) in this project's own sources:" >&2
    sed 's|.*pet-app/||' /tmp/puck-warnings.$$ >&2
    rm -f /tmp/puck-warnings.$$
    exit 1
fi
rm -f /tmp/puck-warnings.$$

# And how much of the tree this build actually looked at, because a pass does
# not mean the same thing on an incremental build as on a clean one -- the
# compiler reports warnings only for files it recompiled, so a green gate here
# can mean "no warnings" or "nothing was compiled". Reported rather than
# enforced: rebuilding everything on every run would cost ten minutes to say
# something a clean CI build already says.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
seen=$(grep -oE "pet-app/(Puck|PuckClient|PuckTests|PuckClientTests)/[^ ]*\.swift" "$LOG" \
    | sort -u | wc -l | tr -d ' ')
total=$(find "$ROOT/pet-app/Puck" "$ROOT/pet-app/PuckClient" \
    "$ROOT/pet-app/PuckTests" "$ROOT/pet-app/PuckClientTests" \
    -name '*.swift' | wc -l | tr -d ' ')
if [ "$seen" -lt "$total" ]; then
    echo "note: this build compiled $seen of $total sources; warnings in the rest were not re-checked."
    echo "      Delete DerivedData for a build that checks all of them."
fi
