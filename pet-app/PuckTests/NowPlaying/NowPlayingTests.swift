//
//  NowPlayingTests.swift
//  PuckTests
//
//  What is playing, and what counts as a change of it.
//

import XCTest
@testable import Puck

final class NowPlayingTests: XCTestCase {
    private func track(
        title: String = "리무진",
        artist: String = "비오",
        album: String = "single",
        position: TimeInterval = 30,
        duration: TimeInterval = 200
    ) -> NowPlaying {
        NowPlaying(
            title: title, artist: artist, album: album,
            isPlaying: true, position: position, duration: duration, source: .music
        )
    }

    func test_progressIsHowFarThrough() {
        XCTAssertEqual(track(position: 50, duration: 200).progress, 0.25, accuracy: 0.0001)
        XCTAssertEqual(track(position: 0, duration: 200).progress, 0)
        XCTAssertEqual(track(position: 200, duration: 200).progress, 1)
    }

    /// A stream reports no length. An empty bar is the honest answer; a full
    /// one says the song is over, and a divide by zero is not an answer.
    func test_aTrackWithNoLengthShowsNoProgress() {
        XCTAssertEqual(track(position: 90, duration: 0).progress, 0)
    }

    /// Position is read on a timer, so it differs every tick. Comparing the
    /// whole value to decide whether to refetch lyrics would refetch
    /// constantly.
    func test_theSameSongAtADifferentPositionIsTheSameSong() {
        XCTAssertTrue(track(position: 10).isSameTrack(as: track(position: 90)))
    }

    func test_aDifferentSongIsNot() {
        XCTAssertFalse(track().isSameTrack(as: track(title: "다른 곡")))
        XCTAssertFalse(track().isSameTrack(as: track(artist: "다른 사람")))
        XCTAssertFalse(track().isSameTrack(as: nil))
    }

    /// A live album and a studio one share a title and an artist, and have
    /// different lyrics timings.
    func test_theAlbumCounts() {
        XCTAssertFalse(track(album: "studio").isSameTrack(as: track(album: "live")))
    }
}
