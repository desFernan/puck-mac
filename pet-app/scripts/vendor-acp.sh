#!/bin/sh
# Bundles the two ACP agents into single .mjs files inside Puck's resources,
# so AcpAgentProcess can run them with a plain `node <file>` and pet-app needs
# no node_modules at runtime.
#
# Why bundled rather than shipped as node_modules: the packages pull ~40 deps
# between them, and a node_modules tree inside an .app bundle is both large and
# awkward to sign. esbuild flattens each to one file (claude 2.2MB, codex
# 1.1MB), which is small enough to commit -- and committing them is the point:
# these bundles change only when the pinned versions do, so paying an npm
# install per checkout would buy nothing. (Unlike ChatWeb, whose built bundle
# is gitignored and rebuilt by sync-chat-web.sh, because its source changes
# constantly.)
#
# Run this only when bumping the pinned versions in scripts/acp/package.json,
# then commit the regenerated .mjs files. This is the one Node dependency left
# in the repo, and it is build-time only.
#
# ## Neither agent is self-contained: both need their vendor's CLI
#
# Both ACP packages are shims. claude-agent-acp resolves @anthropic-ai/
# claude-agent-sdk to find a 256MB native binary; codex-acp resolves
# @openai/codex to find a 262MB one. Vendoring either would multiply the app's
# size, so AcpAgentProcess points each shim at the user's own install through
# the variable the shim already reads -- CLAUDE_CODE_EXECUTABLE and CODEX_PATH.
# Without that CLI installed, that agent is unavailable and the other is
# unaffected.
#
# The resolution is lazy, which is a trap: `initialize` is answered long before
# the binary is needed, so a bundle missing it looks perfectly healthy until
# the first real edit. That is why the smoke test below goes all the way to
# session/new -- an initialize-only probe shipped exactly that bug once.
set -e
cd "$(dirname "$0")/.."

VENDOR_DIR="scripts/acp"
DEST="Puck/Resources"

if ! command -v npm > /dev/null 2>&1; then
    echo "error: npm is required to regenerate the ACP bundles (build-time only)." >&2
    echo "       The committed Puck/Resources/acp-*.mjs are what the app actually ships;" >&2
    echo "       you only need this script when bumping scripts/acp/package.json." >&2
    exit 1
fi

(cd "$VENDOR_DIR" && npm install --silent --no-audit --no-fund)

ESBUILD="$VENDOR_DIR/node_modules/.bin/esbuild"

bundle() {
    package="$1"
    output="$2"
    entry="$VENDOR_DIR/node_modules/$package/dist/index.js"
    if [ ! -f "$entry" ]; then
        echo "error: $entry not found after npm install" >&2
        exit 1
    fi
    # --format=esm and the .mjs extension both matter: the packages are ESM,
    # and node decides module vs script by extension when given a bare path.
    "$ESBUILD" "$entry" \
        --bundle \
        --platform=node \
        --format=esm \
        --outfile="$DEST/$output" \
        --log-level=warning
    echo "bundled $package -> $DEST/$output"
}

mkdir -p "$DEST"
bundle "@agentclientprotocol/claude-agent-acp" "acp-claude.mjs"
bundle "@agentclientprotocol/codex-acp" "acp-codex.mjs"

# Smoke test: initialize *and* session/new. The second is the one that matters
# -- it is where the shim dynamically resolves its native binary, so it is the
# step that catches an import esbuild could not inline. Requires node and the
# claude CLI; skipped rather than failed without them, since neither absence is
# a bundling bug.
#
# codex-acp is deliberately not probed: same shape, and its CLI is a 262MB
# install that a machine building this repo has no reason to have.
if command -v node > /dev/null 2>&1 && command -v claude > /dev/null 2>&1; then
    probe_output=$(
        {
            printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}'
            sleep 2
            printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"session/new\",\"params\":{\"cwd\":\"$(pwd)\",\"mcpServers\":[]}}"
            sleep 5
        } | CLAUDE_CODE_EXECUTABLE="$(command -v claude)" node "$DEST/acp-claude.mjs" 2>/dev/null
    )
    if ! printf '%s' "$probe_output" | grep -q '"protocolVersion"'; then
        echo "error: acp-claude.mjs did not answer initialize" >&2
        exit 1
    fi
    if ! printf '%s' "$probe_output" | grep -q '"sessionId"'; then
        echo "error: acp-claude.mjs answered initialize but could not open a session." >&2
        echo "       Usually a dependency esbuild could not inline -- check the" >&2
        echo "       error's data.details in the output below." >&2
        printf '%s\n' "$probe_output" | tail -3 >&2
        exit 1
    fi
    echo "smoke test: acp-claude.mjs answers initialize and opens a session"
else
    echo "smoke test: skipped (needs both node and the claude CLI)"
fi
