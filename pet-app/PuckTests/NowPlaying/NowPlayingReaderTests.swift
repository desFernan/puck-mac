//
//  NowPlayingReaderTests.swift
//  PuckTests
//
//  Which of the two places that can answer gets to.
//

import XCTest
@testable import Puck

final class NowPlayingReaderTests: XCTestCase {
    private func track(playing: Bool) -> NowPlaying {
        NowPlaying(
            title: "앱에서 나오는 곡", artist: "누구", album: "어디",
            isPlaying: playing, position: 10, duration: 200, source: .music
        )
    }

    private let chromeSound: Set<String> = ["com.google.Chrome"]

    /// Every case here has Chrome open; which browser is running is its own
    /// question, covered in BrowserTitleTests.
    private func sources() -> NowPlayingReader.Sources {
        var sources = NowPlayingReader.Sources()
        sources.runningApps = { ["com.google.Chrome"] }
        return sources
    }

    /// A music app that is playing answers with everything, so it wins.
    func testAPlayingMusicAppBeatsABrowser() {
        var sources = self.sources()
        sources.musicApp = { self.track(playing: true) }
        sources.appsMakingSound = { self.chromeSound }
        sources.browserTitle = { _ in "Radiohead - Creep - YouTube" }

        XCTAssertEqual(NowPlayingReader.read(using: sources)?.title, "앱에서 나오는 곡")
    }

    /// What you can hear is what the panel should be about: a paused music
    /// app loses to a browser making noise.
    func testABrowserMakingNoiseBeatsAPausedMusicApp() {
        var sources = self.sources()
        sources.musicApp = { self.track(playing: false) }
        sources.appsMakingSound = { self.chromeSound }
        sources.browserTitle = { _ in "Radiohead - Creep - YouTube" }

        let read = NowPlayingReader.read(using: sources)

        XCTAssertEqual(read?.title, "Creep")
        XCTAssertEqual(read?.artist, "Radiohead")
        XCTAssertTrue(read?.isPlaying == true)
    }

    /// A browser sitting silent is not playing anything, whatever its tab
    /// happens to be called.
    func testASilentBrowserIsNotRead() {
        var sources = self.sources()
        sources.musicApp = { self.track(playing: false) }
        sources.appsMakingSound = { [] }
        sources.browserTitle = { _ in "Radiohead - Creep - YouTube" }

        XCTAssertEqual(NowPlayingReader.read(using: sources)?.title, "앱에서 나오는 곡")
    }

    /// With nothing audible at all, what is cued up beats showing nothing.
    func testAPausedMusicAppIsBetterThanNothing() {
        var sources = self.sources()
        sources.musicApp = { self.track(playing: false) }
        sources.appsMakingSound = { [] }
        sources.browserTitle = { _ in nil }

        XCTAssertEqual(NowPlayingReader.read(using: sources)?.isPlaying, false)
    }

    /// A browser knows a name, never a playhead, so the panel must not be
    /// told there is a position to draw.
    func testABrowserClaimsNoPlayhead() {
        var sources = self.sources()
        sources.musicApp = { nil }
        sources.appsMakingSound = { self.chromeSound }
        sources.browserTitle = { _ in "Some Song - YouTube" }

        let read = NowPlayingReader.read(using: sources)

        XCTAssertEqual(read?.source.reportsPosition, false)
        XCTAssertEqual(read?.duration, 0)
    }

    /// Nothing anywhere is nothing, not an empty-titled track.
    func testNothingAtAll() {
        var sources = self.sources()
        sources.musicApp = { nil }
        sources.appsMakingSound = { self.chromeSound }
        sources.browserTitle = { _ in "" }

        XCTAssertNil(NowPlayingReader.read(using: sources))
    }
}
