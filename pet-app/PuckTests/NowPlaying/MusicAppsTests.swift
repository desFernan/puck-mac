//
//  MusicAppsTests.swift
//  PuckTests
//
//  Reading a music app's answer. The scripts themselves need a music app;
//  what they hand back is arithmetic, and that is what is pinned here.
//

import XCTest
@testable import Puck

final class MusicAppsTests: XCTestCase {
    private let answer = """
    리무진 (feat. MINO & 그레이)
    비오
    Limousine
    playing
    41.5
    213.0
    """

    func test_itReadsEveryField() throws {
        let track = try XCTUnwrap(MusicApps.parse(answer, source: .music))

        XCTAssertEqual(track.title, "리무진 (feat. MINO & 그레이)")
        XCTAssertEqual(track.artist, "비오")
        XCTAssertEqual(track.album, "Limousine")
        XCTAssertTrue(track.isPlaying)
        XCTAssertEqual(track.position, 41.5)
        XCTAssertEqual(track.duration, 213)
        XCTAssertEqual(track.source, .music)
    }

    func test_pausedIsNotPlaying() throws {
        let paused = answer.replacingOccurrences(of: "playing", with: "paused")

        XCTAssertFalse(try XCTUnwrap(MusicApps.parse(paused, source: .music)).isPlaying)
    }

    /// A podcast or a voice memo has no artist and no album, which is legal
    /// and common -- it must not lose the track.
    func test_aTrackWithNoArtistIsStillATrack() throws {
        let sparse = "어떤 팟캐스트\n\n\nplaying\n10\n600"

        let track = try XCTUnwrap(MusicApps.parse(sparse, source: .music))
        XCTAssertEqual(track.title, "어떤 팟캐스트")
        XCTAssertEqual(track.artist, "")
    }

    /// A half-read answer is a panel showing half a song.
    func test_aShortAnswerIsNoAnswer() {
        XCTAssertNil(MusicApps.parse("", source: .music))
        XCTAssertNil(MusicApps.parse("이름만\n비오", source: .music))
        XCTAssertNil(MusicApps.parse("\n\n\nplaying\n1\n2", source: .music), "no title is no track")
    }

    /// Spotify reports its duration in milliseconds; nothing downstream
    /// should have to know which app answered.
    func test_spotifysDurationIsBroughtIntoSeconds() {
        XCTAssertTrue(MusicApps.script(for: .spotify).contains("/ 1000"))
        XCTAssertFalse(MusicApps.script(for: .music).contains("/ 1000"))
    }

    /// Every field is asked for defensively, or an error partway through
    /// loses the fields after it too.
    func test_theScriptSurvivesAFieldItCannotRead() {
        let script = MusicApps.script(for: .music)

        XCTAssertGreaterThanOrEqual(
            script.components(separatedBy: "try").count - 1, 4,
            "title, artist, album and current-track are each guarded"
        )
    }
}
