//
//  NowPlayingStoreTests.swift
//  PuckTests
//
//  Keeping up with what is playing, and not showing the last song's words
//  over this one.
//

import XCTest
@testable import Puck

@MainActor
final class NowPlayingStoreTests: XCTestCase {
    private func track(_ title: String, position: TimeInterval = 0) -> NowPlaying {
        NowPlaying(
            title: title, artist: "누구", album: "어디",
            isPlaying: true, position: position, duration: 200, source: .music
        )
    }

    private let words = SyncedLyrics.parse("[00:00.00]첫 줄\n[00:30.00]둘째 줄")

    /// The words follow the clock.
    func test_theLyricShownIsTheOneBeingSung() async {
        let store = NowPlayingStore()
        store.read = { self.track("한 곡", position: 45) }
        store.fetchLyrics = { _ in self.words }

        store.start()
        await settle(store)

        XCTAssertEqual(store.currentLyric, "둘째 줄")
    }

    /// A song with nothing in the index still shows: most music is not in it.
    func test_aSongWithNoWordsStillPlays() async {
        let store = NowPlayingStore()
        store.read = { self.track("색인에 없는 곡") }
        store.fetchLyrics = { _ in nil }

        store.start()
        await settle(store)

        XCTAssertEqual(store.track?.title, "색인에 없는 곡")
        XCTAssertNil(store.currentLyric)
    }

    /// Position changes every tick, so refetching on any change at all would
    /// ask the index once a second forever.
    func test_theIndexIsAskedOncePerSongRatherThanPerTick() async {
        let store = NowPlayingStore()
        var position: TimeInterval = 0
        store.read = { self.track("한 곡", position: position) }
        let asked = Counter()
        store.fetchLyrics = { _ in await asked.bump(); return self.words }

        store.start()
        await settle(store)
        for _ in 0..<4 {
            position += 10
            store.refresh()
            await settle(store)
        }

        let count = await asked.value
        XCTAssertEqual(count, 1)
    }

    /// The song can change while the index is being asked, and the previous
    /// song's words landing over the new one is worse than none.
    func test_wordsThatArriveLateForAnOldSongAreDropped() async {
        let store = NowPlayingStore()
        store.read = { self.track("첫 곡") }
        store.fetchLyrics = { asked in
            // Slow enough that the song changes underneath it.
            try? await Task.sleep(nanoseconds: 120_000_000)
            return asked.title == "첫 곡" ? self.words : nil
        }

        store.start()
        // The song changes while the index is still being asked about the
        // first one.
        store.read = { self.track("둘째 곡") }
        store.refresh()
        await settle(store, seconds: 0.4)

        XCTAssertEqual(store.track?.title, "둘째 곡")
        XCTAssertNil(store.currentLyric, "the first song's words must not appear over the second")
    }

    /// Nothing playing is a state, not a failure.
    func test_nothingPlaying() async {
        let store = NowPlayingStore()
        store.read = { nil }
        store.fetchLyrics = { _ in self.words }

        store.start()
        await settle(store)

        XCTAssertNil(store.track)
        XCTAssertNil(store.currentLyric)
    }

    private func settle(_ store: NowPlayingStore, seconds: TimeInterval = 0.2) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Counts across the actor hop the fetch makes.
    private actor Counter {
        private(set) var value = 0
        func bump() { value += 1 }
    }
}
