//
//  NowPlayingReader.swift
//  Puck
//
//  One answer to "what is playing", from whichever place can give one.
//
//  Three places, in descending order of how much they know.
//
//  The system itself knows everything and covers every app, browsers
//  included, so it is asked first. Reaching it needs the vendored adapter --
//  see MediaRemoteReader -- which an OS update could close off, so the two
//  older routes stay as fallbacks rather than being deleted.
//
//  Failing that, Music and Spotify are asked by name over AppleScript. They
//  answer with everything about themselves and nothing about anyone else.
//
//  Failing that, a browser is caught making a sound and read for its front
//  tab's title, which is a name and no more. A paused music app loses to a
//  browser that is making noise: what you can hear is what the panel should
//  be about.
//

import AppKit
import Foundation

enum NowPlayingReader {
    /// Injected so the pieces can be driven in tests without a music app, a
    /// browser, or a sound card.
    struct Sources {
        var system: () -> (track: NowPlaying, artwork: Data?)? = { MediaRemoteReader.read() }
        var musicApp: () -> NowPlaying? = { MusicApps.read() }
        var appsMakingSound: () -> Set<String> = { AudioActivity.appsMakingSound() }
        var runningApps: () -> Set<String> = {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
        var browserTitle: (Browser) -> String? = { MusicApps.run($0.titleScript) }
    }

    /// What is playing, and its cover when whatever answered had one.
    static func read(using sources: Sources = Sources()) -> (track: NowPlaying, artwork: Data?)? {
        // The system knows about every player there is, so a real answer
        // from it ends the question.
        if let fromSystem = sources.system() { return fromSystem }

        let fromApp = sources.musicApp()
        // A music app that is actually playing is the best answer there is.
        if let fromApp, fromApp.isPlaying { return (fromApp, nil) }

        if let fromBrowser = readBrowser(using: sources) { return (fromBrowser, nil) }

        // Nothing audible anywhere, so fall back to the paused music app --
        // showing what is cued up beats showing nothing.
        return fromApp.map { ($0, nil) }
    }

    private static func readBrowser(using sources: Sources) -> NowPlaying? {
        guard let browser = Browser.makingSound(
            among: sources.appsMakingSound(),
            running: sources.runningApps()
        ),
              let raw = sources.browserTitle(browser),
              let parsed = BrowserTitle.parse(raw)
        else { return nil }
        return NowPlaying(
            title: parsed.title,
            artist: parsed.artist,
            album: "",
            // It was caught making a sound, which is the only reason it is
            // here at all.
            isPlaying: true,
            // No playhead: a tab title says what, never how far.
            position: 0,
            duration: 0,
            source: .browser(browser)
        )
    }
}
