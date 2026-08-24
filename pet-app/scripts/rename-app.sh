#!/bin/bash
# Renames the pet app + client app throughout the repo -- directories,
# entitlements, AppIdentity.swift, project.yml, docs, everything sed can
# reach. Written after the PetAgent -> Shaydi rename took hours by hand and
# a follow-up git rebase attempt left ~20 stray duplicate files behind
# (byeolki, 2026-08-01: "다음에도 프로그램 명이 바뀔 수 있으니까 알아서 잘
# config 설정 해놔. 나중에 바꿀때 오래걸리지 말구").
#
# Usage:
#   scripts/rename-app.sh <OldPetName> <NewPetName> <OldClientName> <NewClientName>
#
# Examples (this repo's own history):
#   scripts/rename-app.sh PetAgent Shaydi PetAgentClient ShaydiAgent
#   scripts/rename-app.sh Shaydi Puck ShaydiAgent PuckClient
#
# What this does NOT do:
#   - Touch the actual PRODUCT_BUNDLE_IDENTIFIER strings' *meaning* --
#     they're recomputed as com.speaki-e.<NewName>, still under the same
#     bundleIdPrefix. If that prefix itself needs to change, edit
#     project.yml's `options.bundleIdPrefix` by hand.
#   - Commit or push anything. Review the diff, run the app, then commit.
#   - Rename the App Store / marketing name if one exists somewhere outside
#     this repo -- this only reaches what git tracks here.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -ne 4 ]; then
    echo "usage: $0 <OldPetName> <NewPetName> <OldClientName> <NewClientName>" >&2
    exit 1
fi

OLD_PET="$1"
NEW_PET="$2"
OLD_CLIENT="$3"
NEW_CLIENT="$4"
OLD_TESTS="${OLD_PET}Tests"
NEW_TESTS="${NEW_PET}Tests"

if [ -n "$(git status --porcelain)" ]; then
    echo "error: working tree isn't clean -- commit or stash first." >&2
    exit 1
fi

if [ ! -d "$OLD_PET" ] || [ ! -d "$OLD_CLIENT" ]; then
    echo "error: $OLD_PET/ or $OLD_CLIENT/ doesn't exist -- check the old names." >&2
    exit 1
fi

echo "==> Rewriting file contents ($OLD_CLIENT -> $NEW_CLIENT, then $OLD_PET -> $NEW_PET)"
# Order matters: OLD_CLIENT is replaced first because it very likely
# contains OLD_PET as a substring (PetAgentClient contains PetAgent) --
# doing the shorter replacement first would corrupt every occurrence of the
# longer one before it's ever matched.
git ls-files | grep -v -E '\.(png|wav|jpg|jpeg|icns|usdz)$' > /tmp/rename-app-files.txt
while IFS= read -r f; do
    if grep -qE "$OLD_CLIENT|$OLD_PET" "$f" 2>/dev/null; then
        perl -pi -e "s/\Q$OLD_CLIENT\E/$NEW_CLIENT/g; s/\Q$OLD_PET\E/$NEW_PET/g;" "$f"
    fi
done < /tmp/rename-app-files.txt
rm -f /tmp/rename-app-files.txt

echo "==> Renaming directories and entitlements"
[ -f "$OLD_PET/Resources/${OLD_PET}.entitlements" ] && \
    git mv "$OLD_PET/Resources/${OLD_PET}.entitlements" "$OLD_PET/Resources/${NEW_PET}.entitlements"
[ -f "$OLD_CLIENT/Resources/${OLD_CLIENT}.entitlements" ] && \
    git mv "$OLD_CLIENT/Resources/${OLD_CLIENT}.entitlements" "$OLD_CLIENT/Resources/${NEW_CLIENT}.entitlements"
git mv "$OLD_PET" "$NEW_PET"
git mv "$OLD_CLIENT" "$NEW_CLIENT"
[ -d "$OLD_TESTS" ] && git mv "$OLD_TESTS" "$NEW_TESTS"

# @main entry-point files conventionally carry the app name in their own
# filename (PuckApp.swift, PuckClientApp.swift) -- their contents were
# already renamed above, so just the filenames need to catch up.
[ -f "$NEW_PET/App/${OLD_PET}App.swift" ] && \
    git mv "$NEW_PET/App/${OLD_PET}App.swift" "$NEW_PET/App/${NEW_PET}App.swift"
[ -f "$NEW_CLIENT/${OLD_CLIENT}App.swift" ] && \
    git mv "$NEW_CLIENT/${OLD_CLIENT}App.swift" "$NEW_CLIENT/${NEW_CLIENT}App.swift"

echo "==> Sweeping for anything the sed pass didn't catch (should be empty)"
if grep -rn "$OLD_PET\|$OLD_CLIENT" --include="*" . 2>/dev/null \
    | grep -v "\.git/" | grep -v DerivedData | grep -v "\.xcodeproj/"; then
    echo "warning: the lines above still mention the old name(s) -- check them by hand." >&2
fi

echo "==> Regenerating the Xcode project"
rm -rf ./*.xcodeproj
xcodegen generate

echo "==> Building and testing both targets"
xcodebuild -project "${NEW_PET}.xcodeproj" -scheme "$NEW_PET" -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project "${NEW_PET}.xcodeproj" -scheme "$NEW_CLIENT" -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project "${NEW_PET}.xcodeproj" -scheme "$NEW_PET" -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO

cat <<EOF

==> Done. Before committing:
    - Review "git status --short" and "git diff --stat" -- this touched
      nearly every tracked file, so skim rather than read line by line.
    - Launch both apps by hand and confirm they still find each other
      (CompanionAppLauncher) -- the AppIdentityTests regression guard only
      catches the pet's own bundle id, not the cross-app lookup.
    - You will almost certainly need to re-grant Accessibility/Microphone/
      Speech Recognition permission: the bundle id changed, and macOS ties
      those grants to it.
EOF
