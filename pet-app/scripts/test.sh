#!/bin/bash
# Runs the whole PuckTests suite, unattended, from any directory.
#
# Why this exists rather than a bare `xcodebuild test`: the vendored
# CodeEditSourceEditor/CodeEditTextView packages carry a SwiftLint build tool
# plugin, and an untrusted plugin fails the *build* ("Plugin \"SwiftLint\" from
# package \"SwiftLintPlugin\" must be enabled before it can be used"), so
# testing is cancelled before a single test runs. Trusting it is a GUI prompt
# in Xcode, which a terminal has no way to answer. -skipPackagePluginValidation
# skips it -- the same flag scripts/install.sh already passes, and it only
# affects those vendored packages' linting, never Puck's own sources or tests.
set -euo pipefail
cd "$(dirname "$0")/.."

# Before anything is built: a file added to a folder PuckClient sources one
# file at a time is absent from that app and nothing else notices. Checked
# first because it reads only project.yml and the tree, and a build that is
# going to be wrong should not take ten minutes to say so.
scripts/check-client-sources.py

# And that no layer reaches up. One module means the compiler allows every
# folder to see every other one, so this is the only thing standing between
# "the movement engine must not know about the chat window" and somebody
# reaching across for a type filed in the wrong place.
scripts/check-layering.py

# Puck.xcodeproj is generated from project.yml and deliberately untracked (it
# embeds a per-developer DEVELOPMENT_TEAM), so a fresh clone -- CI included --
# has no project to test until xcodegen has run.
#
# Every time, not only when it is missing. Regenerating only when the directory
# is absent means a local checkout keeps building the project it generated
# before the last file was added or deleted -- which fails as "Build input file
# cannot be found" for a file that is right there, or worse, passes while
# silently leaving a new file out of the target. CI never sees it: a fresh
# clone has no project at all, so CI always generates one.
scripts/generate.sh > /dev/null

# Tee'd rather than streamed: the warning gate below reads what the build
# said, and a warning nobody reads is a warning nobody fixes.
BUILD_LOG=$(mktemp)
trap 'rm -f "$BUILD_LOG"' EXIT

xcodebuild test \
    -project Puck.xcodeproj \
    -scheme Puck \
    -destination 'platform=macOS' \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO | tee "$BUILD_LOG"

# PuckClient is a separate application target with tests of its own -- it
# holds the agent loop, and PuckTests cannot reach a line of it. `test` rather
# than `build`: building still proves its target membership and entry point,
# and running proves the half of the product that lives over here.
xcodebuild test \
    -project Puck.xcodeproj \
    -scheme PuckClient \
    -destination 'platform=macOS' \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO | tee -a "$BUILD_LOG"

# The app bundles the build just produced actually carry what the code looks
# up at runtime. xcodebuild cannot answer this and neither can the unit tests
# -- see scripts/check-resources.sh.
scripts/check-resources.sh "$(xcodebuild -project Puck.xcodeproj -scheme PuckClient -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/ { print $2; exit }')"

# Warnings in our own sources, which xcodebuild reports and then forgets.
scripts/check-warnings.sh "$BUILD_LOG"
