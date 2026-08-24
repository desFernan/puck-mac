# Decisions log

Cross-cutting decisions that don't belong inline in a code comment, and that
something in the source points at. Newest first. Each entry: what changed, why,
and where the implementation lives.

Only entries the current code still refers to are kept. This repository begins
at a mirror of the old one (Speaki-e/puck, archived), and a long tail of
entries about `workspace`, `protocol`, `ai-module` and `chat-web` -- four
repositories deleted in August 2026 -- described a codebase nobody here can
open. They are in that repository's history if anyone needs them.

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
