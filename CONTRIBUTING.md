# Contributing

Thanks for looking. Puck is a macOS desktop pet that is also an AI agent, and
this repository is the one the other ports follow from.

## Where to start

- **A question, or an idea you want to talk through first** — the [Discussions tab](https://github.com/desFernan/puck-mac/discussions), or [Discord](https://discord.gg/nGqtBGP857).
  Discussions is searchable, Discord is faster; either is fine.
- **Something to work on** — issues labelled [`good first issue`](https://github.com/desFernan/puck-mac/issues?q=is%3Aopen+label%3A%22good+first+issue%22) are scoped small and do not
  assume you know the codebase.
- **A bug** — open an issue and say what you did, what happened, and what you
  expected. Your OS version and how you installed it help more than a stack
  trace on its own.

For anything larger than a fix, say so in an issue before you write it. Not as
a gate — so nobody writes the same thing twice, and so we can tell you early
if it is heading somewhere the design does not go.

## Build and test

```sh
sh pet-app/scripts/install.sh   # builds + signs both apps into /Applications
sh pet-app/scripts/test.sh      # PuckTests + a PuckClient build
```

You need Xcode, `xcodegen`, and an Apple Development certificate — a free
personal team is enough. A stable signature is what keeps the Accessibility
grant alive across rebuilds, so signing with a different identity means
granting it again.

`test.sh` is unattended and exits nonzero on any failure. Tests needing
something a machine may lack (`node`, a `claude` or `codex` CLI) skip rather
than fail — a skip is not a pass, and the output says which is which.

## Porting between platforms

This is one product with several implementations — [Windows](https://github.com/desFernan/puck-windows) and [Linux](https://github.com/desFernan/puck-linux) — and a Rust
rewrite besides. When commits land on one of them, a bot opens or updates a
`needs-port- from-<repo>` issue here listing what arrived. Those issues are
the backlog of what this port is missing, and they are the easiest place to
find work: every entry has a working implementation on another platform that
you can read before you write a line.

A port does not have to be a translation. The platform's own idiom wins over
matching the original file-for-file. What has to match is the behaviour a user
sees, and the tool names and wire formats the agent depends on.

## Commits and pull requests

Commit subjects here read as one imperative sentence saying what changes for
the person using it — "Let the app decide how big the pet is", not "update
sizing logic". Most also carry a conventional-commit prefix (`feat(avatar):`,
`fix(bridge):`, `docs:`). Recent history is the reference; match what you see
there.

Keep a pull request to one change. If you find a second thing on the way, a
second PR is easier to review and easier to revert.

Run `sh pet-app/scripts/test.sh` before you open it. CI runs them again, but
finding it yourself is faster than a round trip.

## Artwork and assets

Do not add artwork, icons, fonts or audio unless you made them or they are CC0
or public domain, and say which in the pull request. The code is MIT; the
assets beside it are not necessarily — see [LICENSE-ASSETS.md](LICENSE-ASSETS.md). A custom avatar you made for
yourself belongs in your own customisation folder, or in a Discussions post,
rather than in this repository.
