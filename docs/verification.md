# Verification and release gates

This file is the current source of truth for deciding whether Puck is ready to
ship.

## Automated gate

Run from a clean checkout:

```sh
sh pet-app/scripts/test.sh
```

The gate passes only when the command exits with status 0, Xcode reports no
test failures, and the separate PuckClient scheme builds. The same command runs
on every pull request and every push to `main` through the `macOS tests` GitHub
Actions workflow.

The suite includes two architecture regressions that matter to the current
single-repository app:

- `IdleFrameRatePolicyTests` keeps the CALayer/FSM heartbeat at 30 Hz while
  active and 15 Hz after sustained idle. This replaces the obsolete
  RealityKit-era 60 Hz assumption without disabling timer-driven behavior.
- `AcpAgentProcessSandboxTests` launches a real child process, proves it can
  write inside the selected project, and proves an attempted sibling write
  does not create a file. Protocol event checks remain as defense in depth.

## Manual release smoke test

Automated tests cannot prove that permissions, vendor logins, animation, and
window interaction work in a signed desktop session. Before a release, record
one pass of every item below on the supported macOS version:

- Build and install both apps from a clean checkout with
  `pet-app/scripts/install.sh`.
- Launch Puck and PuckClient; confirm the pet moves, becomes idle, and resumes
  smoothly after interaction.
- Send one chat turn through each model provider that the release supports.
- Open a project, read and edit a file in the native editor, then run
  `code_editor` on that project.
- Ask the agent to explain a function in that project and confirm the code
  tour runs end to end: the editor highlights and scrolls to each range, the
  pet walks to the pane and points at it, its bubble says one line per stop
  and follows it as it moves, and the full explanation lands in the chat. No
  automated test covers this -- the highlight is applied by a live text view
  and the walk needs a screen.
- Ask `code_editor` to write to a sibling directory and confirm the operation
  is denied and no file is created there.
- Trigger an approval-required tool and confirm allow and deny both resume the
  waiting turn correctly.
- Remove or hide an optional vendor CLI and confirm the UI reports that only
  `code_editor` is unavailable rather than breaking the rest of the app.

## Recording a release

Two releases have shipped with this section as a table of "Pending" rows that
nobody filled in, which is worse than not having it: it reads as a gate and
enforces nothing. So there is no table. The automated half is enforced by CI
on every push, visible on the commit; the manual half above is a checklist to
walk before tagging, and what it produced belongs in the release notes where
the people downloading it can read it.
