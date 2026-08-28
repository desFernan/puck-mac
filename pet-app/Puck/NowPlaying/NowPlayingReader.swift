//
//  NowPlayingReader.swift
//  Puck
//
//  One answer to "what is playing", from whichever place can give one.
//
//  The order matters. A music app is asked outright and answers with
//  everything -- title, artist, playhead, cover -- so it wins whenever it is
//  actually playing. A browser can only be caught making a sound and read for
//  a tab title, which is less, so it is the fallback rather than the first
//  question.
//
//  A paused music app loses to a browser that is making noise: what you can
//  hear is what the panel should be about.
//

import AppKit
import Foundation

enum NowPlayingReader {
    /// Injected so the pieces can be driven in tests without a music app, a
    /// browser, or a sound card.
    struct Sources {
        var musicApp: () -> NowPlaying? = { MusicApps.read() }
        var appsMakingSound: () -> Set<String> = { AudioActivity.appsMakingSound() }
        var runningApps: () -> Set<String> = {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
        var browserTitle: (Browser) -> String? = { MusicApps.run($0.titleScript) }
    }

    static func read(using sources: Sources = Sources()) -> NowPlaying? {
        let fromApp = sources.musicApp()
        // A music app that is actually playing is the best answer there is.
        if let fromApp, fromApp.isPlaying { return fromApp }

        if let fromBrowser = readBrowser(using: sources) { return fromBrowser }

        // Nothing audible anywhere, so fall back to the paused music app --
        // showing what is cued up beats showing nothing.
        return fromApp
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
