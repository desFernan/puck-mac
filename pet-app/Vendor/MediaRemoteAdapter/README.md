# MediaRemoteAdapter

Vendored from <https://github.com/ungive/mediaremote-adapter> (BSD 3-Clause,
see LICENSE), built from commit `3ac3d4bdf862c7b5399b4fba4df5689f5c38609a`.

## Why this is here

It is the only way left to find out what the machine is playing.

macOS knows -- Control Centre shows it, for a browser tab as readily as for
Music -- but the framework that answers the question, MediaRemote, stopped
answering third parties in macOS 15.4. It does not fail: it returns an empty
answer, which is worse, because there is nothing to report to the user.

The adapter gets a real answer by running the query inside `/usr/bin/perl`,
whose code signing identity is `com.apple.perl`, and processes signed as
`com.apple.*` are still allowed to ask. Perl is handed the framework as an
argument and loads it; nothing here is linked into Puck.

Without it Puck can only ask Music and Spotify by name over AppleScript, which
leaves out everything played in a browser -- which is most of what most people
listen to.

## What is here

- `MediaRemoteAdapter.framework` -- built universal (x86_64 + arm64), because
  Puck ships universal and the upstream Homebrew bottle is arm64 only.
- `mediaremote-adapter.pl` -- upstream, unmodified. The entry point.
- `LICENSE` -- upstream, unmodified.

## Rebuilding

There is no upstream release artifact to download; the Homebrew bottle is
per-architecture. To rebuild from a checkout of the upstream repository:

```sh
clang -dynamiclib -fobjc-arc -fvisibility=default -arch x86_64 -arch arm64 \
  -Iinclude -Isrc \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  -o MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  src/adapter/*.m src/private/MediaRemote.m src/utility/*.m
```

then complete the bundle (Info.plist with identifier
`com.vandenbe.MediaRemoteAdapter`, the `Versions/Current` symlinks) and
ad-hoc sign it. Re-signing ad-hoc is fine -- perl loads it either way, which
matters because Puck's own install script signs everything it ships ad-hoc.

## What breaks it

An OS update that closes the perl route. If that happens the panel falls back
to asking Music and Spotify directly, and browsers go quiet again.
