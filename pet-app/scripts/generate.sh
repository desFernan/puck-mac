#!/bin/sh
# Generates Puck.xcodeproj from project.yml.
#
# DEVELOPMENT_TEAM is per-developer and must NOT be committed: a free Apple ID
# personal team has exactly one member, so hardcoding one person's team ID in
# project.yml breaks everyone else's build. Set your own in ~/.zshrc:
#
#   export DEVELOPMENT_TEAM=XXXXXXXXXX
#
# Find yours (it is the OU field, NOT the value in parentheses):
#
#   security find-certificate -c "Apple Development" -p \
#     | openssl x509 -noout -subject | tr ',' '\n' | grep OU=
#
# Leaving it unset is fine for building and running tests — the app is then
# ad-hoc signed, which only costs you persistent TCC permissions (macOS ties
# those to the code signature, and an ad-hoc signature changes every build).
set -e
cd "$(dirname "$0")/.."

if [ -z "${DEVELOPMENT_TEAM}" ]; then
    echo "note: DEVELOPMENT_TEAM is unset — building ad-hoc signed."
    echo "      Accessibility/microphone grants will not survive a rebuild."
    echo "      See the comment at the top of scripts/generate.sh."
fi

DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" exec xcodegen generate
