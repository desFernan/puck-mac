#!/bin/sh
# Builds Puck + PuckClient signed with your Apple Development
# certificate and installs Puck.app into /Applications, with PuckClient
# carried inside it.
#
# PuckClient lives at Puck.app/Contents/Library/LoginItems/PuckClient.app
# rather than beside it. Two bundles in /Applications meant searching for
# "Puck" offered two things to launch, one of which is a window the other one
# opens for you. An app nested inside another is still registered with
# LaunchServices -- CompanionAppLauncher looks it up by bundle id and finds it
# either way -- but it is not offered as something to launch on its own, which
# is the whole difference.
#
# Why not just run the Debug build out of DerivedData: macOS ties TCC grants
# (Accessibility above all) to the code signature, and an *ad-hoc* signature
# changes on every build -- so every rebuild silently revoked Accessibility
# and the global hotkey stopped working until it was re-granted by hand.
# The other half of keeping those grants is never deleting the installed
# bundle; see the rsync below.
# Signing with a real (even free, personal-team) Apple Development identity
# keeps the signature stable, so the grant survives rebuilds. Grant it once
# to /Applications/Puck.app and this script can then reinstall as often
# as it likes.
#
# DEVELOPMENT_TEAM is read from the environment if set, otherwise taken from
# the Apple Development certificate in your keychain.
set -e
cd "$(dirname "$0")/.."

if [ -z "${DEVELOPMENT_TEAM}" ]; then
    DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null \
        | tr ',' '\n' | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p' | head -1)
fi

if [ -z "${DEVELOPMENT_TEAM}" ]; then
    echo "error: no Apple Development certificate found and DEVELOPMENT_TEAM is unset."
    echo "       Sign in to Xcode with an Apple ID (Settings > Accounts) to get one;"
    echo "       an ad-hoc build works too, but loses Accessibility on every rebuild."
    exit 1
fi
export DEVELOPMENT_TEAM
echo "note: signing with team ${DEVELOPMENT_TEAM}"


# acp-claude.mjs is not in the repository -- see .gitignore for why -- so a
# fresh clone builds it once here. Needs npm and the network, and only the
# first time or after the pinned versions change.
if [ ! -f Puck/Resources/acp-claude.mjs ]; then
    echo "note: building the ACP bundles (once per clone)"
    scripts/vendor-acp.sh
fi

xcodegen generate

DERIVED=$(mktemp -d)
# Output is held rather than streamed, and shown only if the build fails.
# The vendored CodeEdit packages carry a SwiftLint plugin that cannot run
# unattended, so every successful build also printed "The following build
# commands failed: Running SwiftLint ... (2 failures)" -- which is exactly
# what a real failure looks like to anyone reading the terminal.
# SwiftTerm ships a Metal shader, so the toolchain has to be there before the
# first build on a machine -- otherwise it dies with "cannot execute tool
# 'metal'" and a 688MB download to work out for yourself. GitHub's runners
# have it; a new Mac does not.
if ! xcrun -f metal > /dev/null 2>&1; then
    echo "note: downloading the Metal toolchain (once per machine)"
    xcodebuild -downloadComponent MetalToolchain
fi

BUILD_LOG=$(mktemp)
# $DERIVED too: the failure paths below used to leave a Release build of both
# apps behind in /var/folders, and LaunchServices indexes what it finds there.
trap 'rm -f "$BUILD_LOG"; rm -rf "$DERIVED"' EXIT
for scheme in Puck PuckClient; do
    if ! xcodebuild build \
        -project Puck.xcodeproj \
        -scheme "$scheme" \
        -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED" \
        -skipPackagePluginValidation \
        DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
        > "$BUILD_LOG" 2>&1
    then
        echo "error: $scheme failed to build." >&2
        cat "$BUILD_LOG" >&2
        exit 1
    fi
done

# Quit before replacing: copying over a running bundle leaves the old process
# running against files that no longer exist. Wait for them to actually go --
# a fixed sleep raced the old Puck's shutdown, and the new one then found
# bridge.sock's lock file still held ("BridgeServer failed to start:
# alreadyRunning") and came up with no socket at all.
pkill -x PuckClient || true
pkill -x Puck || true
for _ in $(seq 1 50); do
    pgrep -x Puck > /dev/null || break
    sleep 0.2
done

# Resources the code looks up by name at runtime, per app. Shared with
# scripts/test.sh so a missing one fails in both places rather than only here.
scripts/check-resources.sh "$DERIVED/Build/Products/Release"

# Everything that can be checked is checked before anything is replaced.
# The two apps speak one protocol to each other, so a run that updated Puck
# and then failed on PuckClient left a mismatched pair installed -- and the
# old ones already killed. Nothing below this point is allowed to fail for a
# reason that was knowable up here.
for app in Puck PuckClient; do
    built="$DERIVED/Build/Products/Release/$app.app"
    if [ ! -d "$built" ]; then
        echo "error: $app.app is missing from the build output." >&2
        exit 1
    fi
    if ! codesign --verify --strict "$built" 2>/dev/null; then
        echo "error: the $app.app that was just built is not correctly signed." >&2
        echo "       Nothing has been replaced; /Applications still holds the previous pair." >&2
        exit 1
    fi
done

# The client goes inside the pet's bundle before either is installed, so what
# lands in /Applications is one app with the other already in it.
#
# Nesting invalidates the outer seal -- Contents/Library/LoginItems is a
# nested-code location, and Puck.app's signature has to cover what is in it --
# so Puck.app is signed again afterwards. Same identity as the build used, so
# the TCC grants the header is about are unaffected.
HELPERS="$DERIVED/Build/Products/Release/Puck.app/Contents/Library/LoginItems"
mkdir -p "$HELPERS"
cp -R "$DERIVED/Build/Products/Release/PuckClient.app" "$HELPERS/"
#
# `--preserve-metadata` rather than passing the entitlements file again: Xcode
# rewrites entitlements at build time (the team identifier is substituted into
# them), so re-signing from the checked-in plist would hand the app a
# different set than it was built with.
SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)
if [ -z "$SIGN_IDENTITY" ]; then
    echo "error: no Apple Development identity to re-sign Puck.app with." >&2
    exit 1
fi
if ! codesign --force --sign "$SIGN_IDENTITY" \
    --preserve-metadata=entitlements,requirements,flags \
    "$DERIVED/Build/Products/Release/Puck.app" 2>/dev/null
then
    echo "error: could not re-sign Puck.app after nesting PuckClient inside it." >&2
    echo "       Nothing has been replaced; /Applications is untouched." >&2
    exit 1
fi

# Updated in place, never deleted first. macOS drops an app's privacy grants
# when the app is *removed*, so `rm -rf` followed by a fresh copy handed back
# the microphone, speech and Accessibility prompts on every single install --
# even though the signature (a real Apple Development identity, see the header)
# has been stable the whole time. rsync overwrites what changed and deletes what
# went away, leaving the bundle itself the same item it was.
for app in Puck; do
    built="$DERIVED/Build/Products/Release/$app.app"
    if [ -d "/Applications/$app.app" ]; then
        rsync -a --delete "$built/" "/Applications/$app.app/"
    else
        cp -R "$built" /Applications/
    fi
    # An in-place update writes into a signed bundle, so the signature is
    # worth checking rather than assuming: a broken one launches to a
    # "damaged app" dialog, which is a worse morning than a re-prompt.
    if ! codesign --verify --strict "/Applications/$app.app" 2>/dev/null; then
        echo "error: /Applications/$app.app is not correctly signed after the update." >&2
        echo "       Remove it and run this script again to reinstall from scratch." >&2
        echo "       The two apps speak one protocol to each other, so run it before" >&2
        echo "       launching either: the pair in /Applications is mixed right now." >&2
        exit 1
    fi
done

# Un-register the copies we just built before deleting them, and any other
# copy of these bundle ids lying around (Xcode's own DerivedData, earlier runs
# of this script).
#
# Why this matters: LaunchServices indexes every app bundle it sees, keyed by
# bundle id, and both CompanionAppLauncher and `open -b` ask it -- not us --
# which copy to launch. Left alone it accumulated 18 registrations pointing at
# deleted mktemp dirs plus a live Xcode build, and picked whichever it liked:
# the pet would launch a *stale* client, which is what made a fresh icon look
# like it hadn't updated at all. /Applications has to be the only answer.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -dump 2>/dev/null \
        | grep -oE "/[^ ]*/(Puck|PuckClient)\.app" \
        | sort -u \
        | grep -v '^/Applications/' \
        | while IFS= read -r stale; do "$LSREGISTER" -u "$stale" 2>/dev/null || true; done
    # The nested client is named explicitly: registering the outer bundle
    # does not always reach what is inside it, and CompanionAppLauncher can
    # only launch what LaunchServices knows about.
    "$LSREGISTER" -f /Applications/Puck.app \
        /Applications/Puck.app/Contents/Library/LoginItems/PuckClient.app 2>/dev/null || true
fi

# An earlier version of this script installed the client beside the pet, and
# a copy left there is a second "Puck" in every search -- and a second
# candidate for LaunchServices to launch instead of the nested one.
if [ -d /Applications/PuckClient.app ]; then
    "$LSREGISTER" -u /Applications/PuckClient.app 2>/dev/null || true
    rm -rf /Applications/PuckClient.app
    echo "note: removed the old /Applications/PuckClient.app; it now lives inside Puck.app"
fi

open /Applications/Puck.app
echo "installed: /Applications/Puck.app (with PuckClient.app inside it)"
