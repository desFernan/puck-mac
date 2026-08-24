#!/bin/sh
# Builds Puck + PuckClient in Release and packs both into one .dmg, ready to
# attach to a GitHub release.
#
# The two apps are one product: they speak a private protocol to each other
# over bridge.sock and neither is useful alone, so they ship together in one
# image rather than as two downloads that can drift apart.
#
# Nothing here touches /Applications or the running pair -- that is
# install.sh's job. This only writes build/Puck-<version>.dmg.
#
# Signed ad-hoc, deliberately, and not with the Apple Development certificate
# install.sh uses. A development certificate belongs to one person's Apple ID,
# expires in a year, and is meant for the machine it was issued on; an ad-hoc
# signature is a hash of the bundle, works anywhere, and is what "unidentified
# developer" means. Either way macOS quarantines the download and refuses the
# first launch -- see the README's install section for the way through it.
#
# SIGN_IDENTITY takes a real certificate when there is one to take:
#
#   SIGN_IDENTITY="Developer ID Application: NAME (TEAMID)" scripts/make-dmg.sh
#
# and that image can then be notarised and stapled (xcrun notarytool submit
# --wait, xcrun stapler staple), which is what removes the warning entirely.
set -e
cd "$(dirname "$0")/.."

SIGN_IDENTITY="${SIGN_IDENTITY:--}"

xcodegen generate

# Same one-off as install.sh: SwiftTerm ships a Metal shader, and a machine
# that has never built one dies with "cannot execute tool 'metal'".
if ! xcrun -f metal > /dev/null 2>&1; then
    echo "note: downloading the Metal toolchain (once per machine)"
    xcodebuild -downloadComponent MetalToolchain
fi

DERIVED=$(mktemp -d)
STAGE=$(mktemp -d)
BUILD_LOG=$(mktemp)
trap 'rm -f "$BUILD_LOG"; rm -rf "$DERIVED" "$STAGE"' EXIT

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "note: signing ad-hoc (unidentified developer)"
else
    echo "note: signing with ${SIGN_IDENTITY}"
fi

for scheme in Puck PuckClient; do
    if ! xcodebuild build \
        -project Puck.xcodeproj \
        -scheme "$scheme" \
        -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED" \
        -skipPackagePluginValidation \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
        DEVELOPMENT_TEAM="" \
        PROVISIONING_PROFILE_SPECIFIER="" \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
        ARCHS="arm64 x86_64" \
        ONLY_ACTIVE_ARCH=NO \
        > "$BUILD_LOG" 2>&1
    then
        echo "error: $scheme failed to build." >&2
        cat "$BUILD_LOG" >&2
        exit 1
    fi
done

PRODUCTS="$DERIVED/Build/Products/Release"
# The resources the code looks up by name at runtime. A .dmg is the one place
# a missing one cannot be fixed by rebuilding, so it is checked before the
# image is written rather than discovered by whoever downloads it.
scripts/check-resources.sh "$PRODUCTS"

for app in Puck PuckClient; do
    built="$PRODUCTS/$app.app"
    if [ ! -d "$built" ]; then
        echo "error: $app.app is missing from the build output." >&2
        exit 1
    fi
    if ! codesign --verify --strict "$built" 2>/dev/null; then
        echo "error: the $app.app that was just built is not correctly signed." >&2
        exit 1
    fi
    # get-task-allow lets any process on the machine attach a debugger to
    # this one -- which here means attaching to an app holding Accessibility,
    # the microphone and a shell. Xcode injects it when signing for
    # development, so a distribution image is checked for it rather than
    # assumed to be free of it.
    if codesign -d --entitlements - "$built" 2>/dev/null | grep -q "get-task-allow"; then
        echo "error: $app.app carries the debug entitlement (get-task-allow)." >&2
        echo "       Refusing to package it." >&2
        exit 1
    fi
    # Both architectures, and the same both for each app: the pair is one
    # product, so a universal pet beside an arm64-only window is an Intel Mac
    # that installs half of it and can only run the half that does nothing on
    # its own. A package that quietly drops an architecture is what this
    # catches -- the default build produces only the machine's own.
    for arch in arm64 x86_64; do
        if ! lipo -archs "$built/Contents/MacOS/$app" | tr " " "\n" | grep -qx "$arch"; then
            echo "error: $app.app was not built for $arch." >&2
            exit 1
        fi
    done
    cp -R "$built" "$STAGE/"
done

# Drag-to-install: the window shows both apps and the folder they go in.
ln -s /Applications "$STAGE/Applications"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$PRODUCTS/Puck.app/Contents/Info.plist" 2>/dev/null || echo "0.0")
mkdir -p build
DMG="build/Puck-$VERSION.dmg"
rm -f "$DMG"

# UDZO: compressed and read-only, which is what a download should be.
hdiutil create \
    -volname "Puck $VERSION" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" > /dev/null

echo "built: $DMG ($(du -h "$DMG" | cut -f1))"
