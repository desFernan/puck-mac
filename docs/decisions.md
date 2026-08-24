# Decisions log

Cross-cutting product/architecture decisions that don't belong inline in code
comments. Newest first. Each entry: what changed, why, and where the actual
implementation lives.

## 2026-08-22: the specs the code cites are historical, not files to open

Comments across `pet-app` cite `plan/01_protocol.md`, `plan/02_pet-app.md`,
`plan/04_ai-module.md`, `docs/tools.md`, `docs/socket.md`,
`docs/avatar-spec.md` and `src/types/tools.ts`. None of those are in this
repository and none ever were: they lived in the `plan` spec repo and in the
`protocol`/`ai-module`/`workspace` repos the native rewrite folded away.

The citations stay. Most of them quote the rule they are citing -- the state
table, the timeout, the message schema -- so the substance survives the
source; stripping 65 of them would risk the prose for no gain, and provenance
for a decision is worth keeping even when the document is gone.

What was removed is the handful of comments that told a reader to *do*
something impossible: "always update this file together with
`src/types/tools.ts`", and the framing of `ToolRegistry`, `ToolTimeouts` and
`BridgeMessages` as mirrors that some other repo owns. Nothing owns them now
but this repository, which makes a change to any of the three a change to the
wire rather than a copy to keep in step.

## 2026-08-15: the chat UI goes back to native SwiftUI; chat-web is deleted

The chat window is native again, and `pet-app` is now the whole repository.
`install.sh` alone builds a fresh checkout: chat-web's bundle was gitignored
and rebuilt by `sync-chat-web.sh`, which was the only thing that made a clone
need npm.

**This reverses the 2026-08-13 entry below, and the reason it gives is exactly
why.** That entry chose a webview because native SwiftUI could not iterate fast
enough toward a specific bespoke look -- "Orca/Zed-inspired, minimalist,
shadcn" -- with no devtools, no hot reload, and no exact-value extraction. The
target changed (byeolki: "iOS 기본 제공 탬플릿 같은거 써서"), and stock SwiftUI
is the fastest way to look like stock SwiftUI. The premise went, so the
conclusion went with it.

**It was a view swap, not an architecture change.** The same 2026-08-13 entry
described chat-web as gaining "a second UI consumer" of `ClientWindowStore` /
`ChatSession`, which stayed "the real-time source of truth exactly as they are
today". That held: no state moved, and what was deleted was the mirror --
`chat-reducer.ts`, the hand-maintained `bridge-types.ts` contract, and
`ClientChatBridge` pushing deltas across it.

Also smaller than 2,926 lines suggests. ~1,100 of those were shadcn `ui/`
primitives with direct SwiftUI equivalents (`Menu`, `.alert`, `Picker`,
`.sheet`, `Slider`, `Toggle`, `ScrollView`), and ~240 were bridge plumbing that
died with the webview. The app-specific views came to ~700 lines of Swift.

macOS idioms rather than iOS ones, despite how the request was phrased: this is
a Mac app, and iOS's grouped lists and bottom tab bars read as wrong here.
`List` with a `Section` per workspace (what Mail and Xcode use for this shape,
and it brings selection and keyboard navigation for free),
`NavigationSplitView`, `DisclosureGroup` for tool calls,
`TextField(axis: .vertical)` for the composer, `Form(.formStyle(.grouped))` for
the new-workspace sheet, SF Symbols and semantic colors.

The editor toggle gained ⇧⌘E on the way. As a web button it could only be
clicked -- no keyboard path, and no way for automation to reach it, which is
why verifying the editor pane kept stalling.

Kept: `ClientPalette`/`ClientTheme` (the editor pane and status bar already use
them), and the session tab strip, which is not a stock macOS idiom but was a
deliberate addition two days earlier -- removing it is a product decision, not
a restyle.

Implementation: `pet-app/Puck/ClientWindow/Chat/`. Spec:
`docs/superpowers/specs/2026-08-15-native-chat-design.md`.

## 2026-08-15: Material Icon Theme in the editor's file tree

The tree drew one SF Symbol per kind, so every file was the same grey document
and scanning a project meant reading filenames. Vendored Material Icon Theme
(MIT, Copyright (c) 2025 Material Extensions) instead of inventing a set --
it is what VS Code users already read at a glance.

Two findings kept this to one small file plus a vendor script:

- **`NSImage` reads SVG natively on macOS** and keeps it as a vector rep
  (`_NSSVGImageRep`), verified before committing to the approach. So the icons
  ship as `.svg` with no rasterizing step, no SVG library, and nothing to keep
  in sync with a renderer.
- **The released `.vsix` carries the mapping already resolved.** The git repo
  stores it as TypeScript (`src/core/icons/fileIcons.ts`) that has to be
  executed to expand patterns into real extension lists; the published artifact
  has `dist/material-icons.json` with extension/filename/folder → icon name
  done. Vendoring the artifact skips reimplementing their resolver.

`scripts/vendor-file-icons.sh` pins 5.37.0, keeps the four maps the tree reads
(dropping light/high-contrast variants and VS Code language ids), and copies
only the 1,125 icons those maps reference. 4.8MB. Not subset further: guessing
which languages matter breaks the moment someone opens a `.rs` or `.ex` file.

The behaviour worth testing is resolution order, and `FileIconThemeTests`
covers it against the real vendored map -- so a packaging mistake fails a test
rather than producing a silently icon-less tree. Exact filename beats extension
(`tsconfig.json` is not a `.json` file), longest extension wins
(`button.test.ts` is not `button.ts`), lookup is case-insensitive, and folders
have their own icons including an open variant.

Implementation: `pet-app/Puck/ClientWindow/Editor/Views/FileIconTheme.swift`.

## 2026-08-15: workspace, protocol and ai-module are deleted; pet-app absorbs what was left

`workspace` (Electron + Monaco + ACP) is gone, and with it the last non-Swift
process in the product. `protocol` and `ai-module` went at the same time, for
reasons that follow from it.

Only three things in `workspace` were still doing work by this point. The
2026-08-14 native editor entry below had already replaced the editor pane, and
the renderer, `editor-gateway.ts` and `file-service.ts` (~1,500 lines) were
dead behind it.

- **The workspace/session registries.** `workspace-registry.ts` owned workspace
  metadata, so PuckClient's "새 워크스페이스" had to travel over the bridge and
  come back. Ported to `Puck/Workspaces/WorkspaceRegistry.swift`, keeping the
  on-disk shape (`{version: 1, workspaces: [...]}`) so there is no migration.
- **`code_editor`.** `agent-host/` spawned an ACP agent in an Electron utility
  process. Now `Puck/Agent/ACP/` spawns it directly: the six JSON-RPC methods
  the TS adapter used, hand-rolled the way `ClaudeClient` hand-rolls the
  Anthropic Messages API.
- **The bridge client.** `pet-bridge.ts` existed to connect the other two to
  pet-app's socket. With both in-process there is nothing to connect.

**Order mattered more than the deletion did.** Deleting `workspace` first would
have killed workspace *creation*, not just `code_editor` -- and a workspace is
where a project path comes from, so `EditorAvailability` would have resolved
`.noProject` forever and the native editor could never open again. The
registry was ported first for that reason, and the deletion came last, when
nothing was lost by it.

**`user_input` changed direction.** It was relayed to the `workspace` role and
carries what the user typed into the pet's bubble or spoke over push-to-talk.
Its consumer is whoever runs the agent, which is PuckClient now, so it targets
`gui` -- left alone it would have been relayed to nobody and silently broken
both inputs. `BridgeServer`'s `UserInputTransport` inverted for the same
reason: it excluded gui connections precisely because they could not act, and
now they are the only ones that can. F6's offline bubble means "the chat window
is closed" rather than "workspace is down".

**`protocol` died as a consequence, not a decision.** Its job was to hold one
contract against two implementations -- TypeScript types on one side, hand-
maintained Swift mirrors on the other, with `swift-mirror.test.ts` guarding the
drift. With no TypeScript consumer left there is no second implementation, so
the guard compares a thing to itself. The Swift copies in `pet-app/Puck` are
the contract now. `ai-module` was already dead (its README said so) and only
appeared in `workspace`'s pnpm workspace members.

**Neither ACP agent is self-contained, and neither is vendored whole.**
`claude-agent-acp` and `codex-acp` are shims around ~256MB per-platform native
binaries. The shims are esbuilt to one committed `.mjs` each (3.3MB total,
`scripts/vendor-acp.sh`); the binaries are the user's own install, reached
through the variable each shim already reads (`CLAUDE_CODE_EXECUTABLE`,
`CODEX_PATH`). That resolution is lazy -- `initialize` succeeds long before it
happens -- which shipped a bundle that answered the handshake and could not
open a session, so both the build-time probe and the integration test now run
through `session/new`.

Node is still required for `code_editor` and nothing else. Without it, or
without the selected agent's CLI, that one tool reports why and the rest of the
app is unaffected.

Implementation: `pet-app/Puck/Workspaces/`, `pet-app/Puck/Agent/ACP/`,
`pet-app/scripts/vendor-acp.sh`. Spec:
`docs/superpowers/specs/2026-08-15-workspace-to-swift-design.md`.

## 2026-08-15: model hosting providers -- OpenAI or Anthropic for the pet-app agent, Claude or Codex for workspace's `code_editor`

Both apps could only ever talk to one model host each: `pet-app`'s own agent
loop was OpenAI-only (`GPTClient`), and `workspace`'s `code_editor` tool
always shelled out to Claude Code over ACP. This adds a second option on
each side, independently -- they are different subsystems with different
protocols, not one provider switch.

**`pet-app`'s agent loop: `AgentLLMClient` split, `GPT*` names kept.**
`pet-app/Puck/Agent/GPTClient.swift` used to be both the wire client and the
only shape `AgentRunner` knew about. `protocol AgentLLMClient { func
send(messages: [GPTMessage], tools: [GPTToolSpec]) async throws -> GPTTurn }`
was pulled out of it so a second implementation could sit next to it;
`AgentRunner` now takes `any AgentLLMClient` instead of `GPTClient` directly.
The `GPT*` request/response type names (`GPTMessage`, `GPTToolCall`,
`GPTTurn`, `GPTToolSpec`) were kept even though they now cross provider
lines -- renaming them would touch every call site for no behavioral gain,
since the shapes really are the same three request fields and two response
fields regardless of who serves them (see the doc comment directly above
`protocol AgentLLMClient`).

**`ClaudeClient`: no SDK, four Messages-API differences.**
`pet-app/Puck/Agent/ClaudeClient.swift` is a hand-rolled Anthropic Messages
API client, matching `GPTClient`'s existing no-SDK policy (a tool-use loop
needs three request fields and reads two response fields; a dependency for
that is a dependency to keep updated, and there is no official Anthropic
Swift SDK to reach for anyway). Its header documents the four differences
from Chat Completions that would have silently misbehaved if copy-pasted:
auth is `x-api-key` + `anthropic-version: 2023-06-01`, not `Authorization:
Bearer`; `system` is a top-level request field, not a `role: "system"`
message; tool use arrives as content blocks (an assistant reply's `content`
mixes `text` and `tool_use` blocks, and a tool result goes back inside a
*user* message as a `tool_result` block -- there is no `role: "tool"`); and
`max_tokens` is required (fixed at 4096, since `AgentRunner`'s turns are
short tool-call exchanges, not long-form generation).

**`AgentProvider` + `ANTHROPIC_API_KEY`, back-compatible default.**
`AgentConfiguration` (`pet-app/Puck/Agent/AgentConfiguration.swift`) gained
`provider: AgentProvider` (`.openai` / `.anthropic`), resolved through the
same environment-then-`.env`-search-path order the API key already used, via
`AGENT_PROVIDER` (default `openai`; an unrecognized value falls back to
`openai` rather than crashing -- `AgentProvider.resolved(fromRawValue:)`).
Anthropic reads `ANTHROPIC_API_KEY` and defaults to model
`claude-sonnet-5` (`AgentConfiguration.defaultAnthropicModel`, taken from
Anthropic's official model docs as their balanced speed/intelligence
default, the same role `gpt-4o` plays for OpenAI) unless `ANTHROPIC_MODEL`
or the provider-neutral `AGENT_MODEL` names something else. Defaulting to
`.openai` means every existing `.env` with just `OPENAI_API_KEY` keeps
working unchanged -- the provider field is additive, not a breaking
migration.

**Surfaced to the user:** a provider picker (segmented `Picker` over
`AgentProvider.allCases`) in `pet-app/PuckClient/AgentSettingsView.swift` --
deliberately not `Puck/Settings/SettingsView.swift`, whose header disclaims
owning agent settings. It reads/writes `AGENT_PROVIDER` in the same `.env`
the API key field already writes to (`AgentConfiguration.writableEnvFile`).

**Gap fixed -- provider switches now take effect without a relaunch.**
`AgentHost.init` (`pet-app/PuckClient/AgentHost.swift`) constructs exactly
one `AgentRunner`, once, for the process's lifetime. Choosing the
`AgentLLMClient` *class* at that same moment -- as the original
`makeAgentLLMClient` did, switching on `configuration().provider` once at
construction -- meant a provider change in Settings only took effect on the
next relaunch, even though the key itself was already live (`GPTClient` and
`ClaudeClient` both re-read `configuration()` on every `send`, precisely so
a key typed into Settings works without quitting the app). That was an
inconsistency, not a deliberate choice: the class-level `provider` decision
and the request-level `apiKey`/`model` decisions disagreed about how live
"live" should be. Fixed with `RoutingAgentLLMClient`
(`pet-app/Puck/Agent/GPTClient.swift`), a thin `AgentLLMClient` that holds
one instance of each underlying client (cheap -- just a closure and a
`URLSession`) and re-reads `configuration().provider` on every `send` to
pick which one handles that turn. `makeAgentLLMClient` now always returns a
`RoutingAgentLLMClient` rather than switching once.
`PuckTests/Agent/RoutingAgentLLMClientTests.swift` proves a provider flip
between two `send` calls on the same router instance reaches the newly
selected client and not the old one, without reconstructing anything.

**`workspace`'s `code_editor`: ACP command generalized, Codex via a wrapper
package.** `resolveAgentCommand(kind: CodingAgentKind, appPath)` in
`workspace/src/shared/acp-command.ts` replaces a Claude-only command
resolver; `CodingAgentKind` is `"claude" | "codex"`. Codex does not speak ACP
natively -- it reaches the same `AcpAdapter` protocol through
`@agentclientprotocol/codex-acp` (pinned at `1.2.0`, added to the
`workspace` Electron build's `asarUnpack` list alongside the existing Claude
Code ACP package), the same way `@agentclientprotocol/claude-agent-acp`
already stood in for Claude Code. `AcpAdapter`
(`workspace/src/agent-host/acp-adapter.ts`) takes an `agentKind` option
(defaults `"claude"` for back-compatibility) and, when it is `"codex"`,
forwards `CODEX_API_KEY`/`OPENAI_API_KEY` from its own process env into the
spawned agent's env (and still forwards `ANTHROPIC_API_KEY` for the Claude
case). The `codingAgent` setting is threaded end-to-end -- `SettingsStore` /
`settings-contract.ts` → `agent-runtime-coordinator.ts`'s
`getCodingAgent` hook → `tool-executors.ts` → the `agent_host_dispatch`
payload → `agent-host/index.ts`'s `createAdapterFor` → `AcpAdapter`'s
`agentKind` -- but there is currently no renderer control that lets a user
set it from a settings screen; it is settable only via the `settings:update`
IPC handler (`SettingsController.installIpc` in
`workspace/src/main/settings-controller.ts`). That renderer tree is slated
for deletion, so the omission was deliberate rather than an oversight.

**Gap fixed -- Codex's key never reached the ACP child process.**
`AcpAdapter` runs inside the Agent Host child process, spawned by
`workspace/src/main/agent-host-controller.ts` via `utilityProcess.fork`.
That fork only ever put `ANTHROPIC_API_KEY` into the child's `env` (sourced
from `claudeApiKey`, itself sourced in `workspace-application.ts` from the
secrets store with `process.env.ANTHROPIC_API_KEY` as a one-time seed/
fallback). So even though `AcpAdapter` already knew to read
`CODEX_API_KEY`/`OPENAI_API_KEY` from its own process env when
`agentKind === "codex"`, those variables never arrived -- selecting
`"codex"` spawned it unauthenticated. Fixed by adding `codexApiKey`/
`openAiApiKey` constructor parameters to `AgentHostController`, forwarded
into the child's `env` the same conditional way `ANTHROPIC_API_KEY` already
is (`...(this.codexApiKey ? { CODEX_API_KEY: this.codexApiKey } : {})`, and
likewise for `OPENAI_API_KEY`) -- minimal-env discipline kept, no
`...process.env` spread. `workspace-application.ts` sources both directly
from `process.env.CODEX_API_KEY`/`process.env.OPENAI_API_KEY`, the same
"environment variable, no secrets-store entry yet" path the existing
`openAiCodeEditor` wiring a few lines below it already uses for
`OPENAI_API_KEY` -- there is no codex/openai secrets-store key yet, so this
does not invent a second mechanism alongside the Claude one, it just doesn't
extend the secrets store to a place the plan didn't ask for it.
`workspace/src/main/agent-host-controller.test.ts` gained two cases: all
three keys land in the forked child's `env` when supplied, and none of them
are present (not even as empty strings) when omitted.

## 2026-08-14: design system v2 -- new mood, light/dark only, new status vocabulary

Full art-direction replacement of `ClientPalette`/`ClientTheme` and the two
web surfaces that mirror them, not a technical fix -- the previous look
(pumpkin-orange accent, dark/white/glass three-mood system) just wasn't
working. New reference mood is an Orca/Zed-style IDE tool: near-black/white
base, denser spacing, harder (smaller) corner radii. `#ed8c33` accent is
kept -- still the one deliberately loud color.

- Themes: 3 → 2. `.glass` is deleted entirely from `ClientThemeStyle` --
  no longer light/dark/glass, just light/dark. `GlassSurface.swift` and the
  `themedSurface` view modifier are deleted as dead code (nothing else drew
  the glass material). `VisualEffectBackground.swift` (the AppKit half of
  the same glass sidebar) is deleted too, in the same cleanup pass.
- `ClientPalette` values replaced for both `.light`/`.dark`: `background`/
  `surface`/`surfaceBorder`/`textPrimary`/`textSecondary`/`onAccent` all
  repointed to the new v2 hexes (`pet-app/design.md` §2 has the full table).
  `accent` (`#ed8c33`) is unchanged. `onAccent` on `.dark` is now `#161616`
  (near-black) rather than white -- reads better on the orange fill per the
  new reference mood; `.light`'s `onAccent` stays white.
- New status-color vocabulary on `ClientPalette`: `statusSuccess`
  (`#3fb950`), `statusError` (`#f85149`), `statusWarning` (`#e3b341`) are
  new stored fields (theme-invariant), plus `statusIdle`/`statusActive`
  as *computed* properties (`textSecondary`/`accent` respectively) so they
  can never drift from those fields. Replaces the old system-color
  (`.green`/`.red`/`.orange`) usage design.md previously documented as ad
  hoc.
- New components consuming that vocabulary: `StatusDotView` (small filled
  circle, `.active` pulses) and `ClientStatusBarView` (persistent thin
  status bar along the bottom of the client window, new UI surface --
  reports the active workspace's editor/project status, not the
  pet-app<->workspace bridge socket).
- Density retune in `ClientTheme.Metrics`: `spacingSmall`/`spacingMedium`/
  `spacingLarge` go from 6/10/16 to 4/8/12; `cardCornerRadius`/
  `rowCornerRadius` go from 12/6 to 6/4. Every panel/tab/badge gets a step
  smaller and more tightly packed -- "soft chat app" density to "dense
  tool" density.
- `chat-web/src/styles.css` and `workspace/src/renderer/styles.css`: token
  values updated to match (`--canvas`/`--surface`/`--hairline`/`--ink`/
  `--mute`/`--brand` names unchanged, values replaced), new `--status-*`
  variables added. Both files also gain a `.light` block for the first time
  -- neither had a light theme before. Note: chat-web's light variables are
  complete and the stylesheet below the token block has zero hardcoded
  color literals, so `class="light"` works today; workspace's `.light`
  block is defined but ~59 hardcoded dark literals remain further down that
  file, so `class="light"` there currently yields a broken half-light UI --
  not fixed in this pass (tracked as follow-up, not urgent since nothing
  wires up a light toggle yet on either surface).
- `pet-app/design.md` was rewritten in full to the v2 values and is the
  detailed reference for all of the above (exact hex tables, typography,
  component patterns) -- this entry is the summary, not a duplicate.
- Supersedes the 2026-08-12 "PuckClient adopts workspace's design" entry
  below (the `#090909`/`#111111` surfaces and 12px/6px radii it describes
  as "source of truth" are the now-replaced v1 values) and the 2026-08-13
  "one point color" entry's claim that `ClientPalette.light/.dark/.glass`
  all share `#ed8c33` (`.glass` no longer exists).

## 2026-08-14: PuckClient's editor pane goes native, drops workspace at runtime

Replaced `EditorWebView.swift` (a `WKWebView` loading a URL `workspace`
served over its own loopback `EditorGateway`, the entire compiled React/
Monaco bundle plus a WS file API) with a fully native SwiftUI file tree +
tabs + syntax-highlighted editor, backed directly by a new
`WorkspaceFileService` that reads/writes the project itself. Same motivation
as the chat window's earlier move, opposite direction: this time native
Swift is what let the app stop depending on `workspace` being launched at
all for manual file browsing/editing, not what was blocking it. Lightweight
by design -- no diff view, minimap, autocomplete/LSP, or multi-cursor,
matching Monaco's *un*used feature surface rather than its full one.

- New: `pet-app/Puck/ClientWindow/Editor/` -- `WorkspaceFileService.swift`
  (1:1 port of `workspace/src/main/file-service.ts`: tree listing with the
  same hardcoded ignore list, binary/UTF-8 sniffing, SHA-256-revision
  optimistic-concurrency save, image preview), `PathContainment.swift`/
  `ImageMime.swift` (ports of the matching `shared/*.ts`), `WorkspaceFileWatcher.swift`
  (FSEvents, not `DispatchSource` -- the latter doesn't recurse or notice new
  paths), `EditorPaneStore`/`EditorPaneStorePool` (tab/tree state, one
  `EditorPaneStore` per workspace, kept alive for the process's life same as
  the old `EditorWebViewPool`), `EditorAvailability.swift` (replaces
  `ClientWorkspace.editorViewURL`/`editorUnavailableReason` with a
  synchronous, locally-resolved enum -- no round trip needed now that
  PuckClient already has the real path before touching anything).
- Syntax highlighting: `CodeEditSourceEditor`/`CodeEditLanguages`
  (MIT, tree-sitter-based, the actual editor component behind CodeEdit.app),
  the first external SwiftPM dependency in this repo (`project.yml`'s new
  `packages:` section). `STTextView` was ruled out (GPLv3/paid-commercial
  license); `Runestone` was ruled out (its own README says AppKit/Catalyst
  support isn't finished). Its bundled `SwiftLint` build-tool plugin has no
  local binary to run in this environment, so builds/tests pass
  `-skipPackagePluginValidation` now (`scripts/install.sh` updated to match)
  -- harmless, since that plugin only lints `CodeEditSourceEditor`'s own
  source, not this repo's.
- `read_file`/`open_in_editor` re-pointed to native too, in the same pass:
  new `Puck/Agent/EditorFileDelegate.swift`, delegated from `AgentRunner`
  exactly like `code_editor` already was (`AgentFileDelegation` closures,
  offered to the model only when wired) -- **not** `.petApp`-executor
  `ToolExecutor`/`ToolHandler` dispatch, since that machinery runs in
  Puck.app's separate process/on Puck.app's own state, which has no access
  to PuckClient's editor-pane state at all. Both tools were actually inert
  before this (excluded from `AgentRunner.petToolSpecs` and never delegated),
  so this is the first time either is reachable by the model, closing a real
  inconsistency: previously a human could edit files with `workspace` fully
  unlaunched but the agent couldn't read one at all.
- `pet-app/project.yml`'s `packages:`/target `dependencies:` had to go on
  **both** `Puck` and `PuckClient` targets, not just `PuckClient` -- the new
  `Editor/` sources live under the already-shared `Puck/ClientWindow` path,
  so `Puck.app` (the pet, no editor UI of its own) links
  `CodeEditSourceEditor` transitively too, same structural situation as it
  already linking WebKit for the same reason.
- Explicitly not touched: `workspace`'s TypeScript side (`EditorGateway`,
  `editor_view_ready`/`editor_view_unavailable` sending) -- PuckClient just
  stops consuming those messages; `EditorGateway` becomes a dead-consumer
  server that still starts on every `workspace` launch, a natural TS-side
  cleanup follow-up, not bundled here. `code_editor`'s ACP-subprocess
  mechanism (still genuinely needs `workspace` running) is untouched.
- Verified: 1016/1016 `PuckTests` (was 957 pre-Electron-revert baseline +
  59 new, covering `WorkspaceFileService`/`PathContainment`/`EditorLanguage`/
  `WorkspaceFileWatcher`/`EditorPaneStore`/`EditorFileDelegate`/
  `AgentRunner.pathArgument`), both `Puck`/`PuckClient` targets build clean,
  `scripts/install.sh` builds+signs+installs both apps.

## 2026-08-13: PuckClient's chat UI moved to web (React/Tailwind/shadcn) -- done

Landed in full: `chat-web/` (sidebar, top bar, transcript, streaming, tool
calls, approvals, session/workspace switching) replaces
`ChatView.swift`/`ClientSidebarView.swift`, which are deleted.
`ClientChatBridge.swift`/`ClientChatBridgeMessages.swift` are the JS↔Swift
bridge (`chat-web/src/lib/bridge-types.ts` mirrors the Swift side by hand).
`ClientWindowStore`/`ChatSession` are unchanged -- `AppDelegate.swift` now
routes chat events through `chatBridge.applyEvent(...)` (which folds into the
store itself, then pushes the exact delta) instead of calling
`ClientWindowStore.handleChatEvent` directly, and pushes a blanket
`refreshWorkspacesAndSessions()` after every other store mutation (new
workspace/session, editor URL, task-session moves) -- the store isn't
Combine-observed because its session list (`sessionOrder`/`sessionsByKey`)
isn't `@Published`, only individual fields like `workspaces` are, so passive
observation would silently miss session-list changes. `AgentSettingsView`
(API key entry) stays native, opened the same way via
`NSApp.sendAction(Selector(("showSettings:")))`, now triggered by
`action:openSettings` from the web sidebar instead of a SwiftUI button.
Editor-open state moved from `ClientWindowView`'s local `@State` to
`ClientChatBridge` (`isEditorOpen` + `setEditorOpenChangeHandler`), since the
toggle now lives in the web sidebar but still has to drive the native
`HSplitView` layout choice. Verified end-to-end via the accessibility tree
(not screenshots) after a real `state:hydrate` round-trip through the actual
`ClientWindowStore` -- 957/957 `PuckTests` still pass.

### (original scoping notes, kept for context)

Native SwiftUI iteration on PuckClient's chat window couldn't hit a specific
visual target (Orca/Zed-inspired, minimalist, shadcn) at any reasonable
speed -- no devtools, no hot reload, no exact-value extraction, just
rebuild/relaunch/eyeball-compare. `workspace`'s own renderer (already
Tailwind+shadcn) took a rich shadcn migration far more easily for the same
reason. Full plan: `puck/pet-app` chat/sidebar/settings gets rebuilt as a new
standalone package, `puck/chat-web/` (React+Tailwind+shadcn, its own
`package.json`, not part of `workspace`'s pnpm workspace or build pipeline --
routing it through `workspace` would partially reverse the entry right below
this one, and concretely break chat for the default project-less workspace
since `EditorGateway` never starts without a bound project). Built to a
static bundle, copied into `PuckClient.app`'s resources
(`PuckClient/Resources/ChatWeb`, synced by `pet-app/scripts/sync-chat-web.sh`),
loaded via `WKWebView.loadFileURL` (`ClientChatWebView.swift`) and driven by a
native JS↔Swift bridge -- `ClientWindowStore`/`ChatSession` stay the real-time
source of truth exactly as they are today, they just gain a second UI
consumer. Full design in `.claude/plans/optimized-mapping-curry.md` (local to
byeolki's machine, not committed) -- ported here as work lands.

**`file://` + WKWebView gotchas found empirically (Phase 0 spike), matter for
any future static bundle loaded this way**:
- WKWebView silently refuses to execute `<script type="module">` under
  `file://` -- navigation succeeds, no error surfaces anywhere (not
  `WKNavigationDelegate`, not `window.onerror`), the script just never runs.
  Fix: build as a classic (non-module) bundle. Vite's `rollupOptions.output`
  `{format: "iife", inlineDynamicImports: true}` does this, but Vite's HTML
  plugin still hardcodes `type="module" crossorigin` on the injected
  `<script>` tag regardless of the actual output format -- a postbuild step
  has to rewrite it (`chat-web/scripts/strip-module-script-tag.mjs`).
- That rewritten tag must keep `defer` (not become a bare classic script):
  `type="module"` scripts execute after the document parses, and dropping
  that guarantee makes `document.getElementById("root")` run before `<body>`
  exists, which is React error #299 ("target container is not a DOM
  element"), not any kind of loading failure.
- When a script has no `crossorigin`/CORS attributes (which this one now
  doesn't, by necessity), WKWebView reports any runtime error inside it as a
  bare `"Script error."` with no file/line/message -- by design, not a bug.
  Debugging needs errors caught and logged explicitly from inside the bundle
  (`try/catch` around the entry point, `console.error` the real
  `error.message`/`error.stack`) rather than relying on `window.onerror`.

## 2026-08-13: workspace trimmed to editor-only UI

workspace is embedded in PuckClient purely as the `code_editor` view (WKWebView),
so surfaces that duplicated PuckClient's own chat/settings were dead weight --
one, `CommandDock`'s agent input, was actively broken there:
`gateway-workspace-api.ts`'s `runCommand` just threw
("Editor View에서는 에이전트 명령을 직접 실행하지 않습니다").

- Removed: `CommandDock` (replaced by a minimal read-only status strip),
  `WorkspaceTitlebar`'s "Workspace ALPHA" brand chrome (redundant inside
  another app's window), `SettingsPanel`'s "모델" field (nothing has consumed
  `WorkspaceSettings.model` since ai-module was retired).
- Kept: the API key field (still the one non-env-var way to hand ACP a Claude
  key), file-size-limit/log-level/recent-projects (still workspace's own
  domain) -- these weren't in scope, just the agent-brain duplication was.
- Backing IPC (`agent:run`/`agent:cancel`, `WorkspaceController.setAgentCommands`)
  removed to match; `agent:status`/`agent:working-paths` kept (still real ACP
  readiness feedback).

## 2026-08-13: one point color across workspace and pet-app -- pumpkin orange

workspace's accent had drifted to blue (`#3291ff`) while pet-app's ClientPalette
used orange (`#ed8c33`), so the two apps' UIs no longer matched even though
PuckClient embeds workspace's editor directly. Unified on pet-app's existing
orange rather than workspace's blue, since orange was already the app's brand
color (see the removed "Figma color matching" scope note in `pet-app/design.md`).

- workspace: `src/renderer/styles.css`'s `--blue`/`--blue-soft` renamed to
  `--brand`/`--brand-soft` and repointed to `#ed8c33`; the handful of
  hardcoded blue rgba/hex tints (focus rings, status-pulse glow) converted to
  the same orange.
- pet-app: `ClientPalette.light/.dark/.glass` all now use the identical
  `#ed8c33` accent (previously `.dark` alone had drifted to workspace's blue).
  **Superseded 2026-08-14**: `.glass` no longer exists (design system v2
  above deleted it); the accent value itself is still `#ed8c33`.

## 2026-08-12: workspace becomes a plain editor; pet-app's F15 brain is permanent

pet-app's temporary F15 agent core (`Puck/Agent/AgentRunner.swift`, Swift +
OpenAI) is now the single, permanent decision-maker for all user commands.
ai-module was never started, so instead of building it and retiring F15, we
retired the ai-module design and kept F15. workspace no longer judges "what
kind of request is this" — it only executes `code_editor` once, for whatever
text pet-app's CodeEditorDelegate already decided is a coding task.

- Implementation: `workspace/src/agent-host/direct-code-editor-runtime.ts`
  (`DirectCodeEditorRuntime`), wired in `workspace/src/agent-host/agent-runner.ts`.
- Removed: `AiModuleRuntime`, `MockAgentRuntime`, `petAppProxy`, the
  `--direct-code-editor`/`--mock-ai` flags, the `runtime_config_request` RPC.
- Delegation path: pet-app's `CodeEditorDelegate.execute` sends the existing
  `user_input`/`agent_done` socket messages (no protocol change needed) rather
  than a new `tool_dispatch` direction.
- Details: `workspace/docs/architecture.md` "AI 실행 경계"; plan repo
  `02_pet-app.md` F15, `프로젝트_개요.md` §2.

## 2026-08-12: PuckClient adopts workspace's design, not the other way around

**Superseded 2026-08-14**: the `#090909`/`#111111` surfaces and 12px/6px
corner radii below were replaced wholesale by design system v2 (see the
2026-08-14 entry above) -- they are no longer the source of truth for
anything. Kept here for history.

Earlier the client window's `ClientPalette`/`ClientTheme` were pushed toward a
Figma reference and workspace's renderer theme was pulled to match *that*.
This reversed: workspace's actual shadcn theme (blue `#3291ff` accent,
`#090909`/`#111111` surfaces, 12px/6px corner radii) is now the source of
truth, and pet-app's `ClientPalette.dark`/`ClientTheme` were ported to match
it pixel-for-pixel. The client window's default size also grew to 1440x900
(from 1100x740) since the sidebar + file tree + Monaco + chat compete for
width once the embedded editor pane is open.

## 2026-08-12: repo consolidation

`protocol`, `pet-app`, `workspace`, `ai-module` merged into one monorepo,
[Speaki-e/puck](https://github.com/Speaki-e/puck) (git subtree, history
preserved). The four standalone repos are archived on GitHub (read-only).
`landing` and `plan` (spec repo) stay separate on purpose. See plan repo
`프로젝트_개요.md` for the up-to-date system/team tables.
