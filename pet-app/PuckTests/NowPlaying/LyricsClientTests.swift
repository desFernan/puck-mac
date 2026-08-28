//
//  LyricsClientTests.swift
//  PuckTests
//
//  Asking a lyrics index for words, and coping with the usual answer, which
//  is that it has none.
//

import XCTest
@testable import Puck

final class LyricsClientTests: XCTestCase {
    private let track = NowPlaying(
        title: "Creep", artist: "Radiohead", album: "Pablo Honey",
        isPlaying: true, position: 30, duration: 238.6, source: .music
    )

    // MARK: - The requests

    func test_theExactLookupCarriesTheTrackAndItsLength() throws {
        let url = try XCTUnwrap(LyricsClient.exactURL(for: track))
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        XCTAssertEqual(query.first { $0.name == "track_name" }?.value, "Creep")
        XCTAssertEqual(query.first { $0.name == "artist_name" }?.value, "Radiohead")
        // The index stores whole seconds; a fractional one matches nothing.
        XCTAssertEqual(query.first { $0.name == "duration" }?.value, "239")
    }

    func test_theSearchDoesNotCarryTheLength() throws {
        let url = try XCTUnwrap(LyricsClient.searchURL(for: track))
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        XCTAssertNil(
            query.first { $0.name == "duration" },
            "the length is exactly what the exact lookup was too strict about"
        )
    }

    // MARK: - The answers

    func test_itReadsASingleRecord() throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            "trackName": "Creep", "syncedLyrics": "[00:19.16] When you were here before",
        ])

        XCTAssertEqual(
            LyricsClient.firstSyncedLyrics(in: payload),
            "[00:19.16] When you were here before"
        )
    }

    /// Search answers with a list, and the first result is not always the one
    /// with words on a clock.
    func test_itTakesTheFirstSearchResultThatHasSyncedWords() throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            ["trackName": "Creep", "plainLyrics": "no timings here"],
            ["trackName": "Creep", "syncedLyrics": ""],
            ["trackName": "Creep", "syncedLyrics": "[00:19.16] the right one"],
        ])

        XCTAssertEqual(LyricsClient.firstSyncedLyrics(in: payload), "[00:19.16] the right one")
    }

    func test_anIndexWithNothingToSayIsNotAnError() throws {
        let notFound = try JSONSerialization.data(withJSONObject: [
            "statusCode": 404, "name": "TrackNotFound",
        ])

        XCTAssertNil(LyricsClient.firstSyncedLyrics(in: notFound))
        XCTAssertNil(LyricsClient.firstSyncedLyrics(in: Data()))
        XCTAssertNil(LyricsClient.firstSyncedLyrics(in: Data("not json".utf8)))
    }

    // MARK: - The two requests together

    func test_aMissOnTheExactLookupFallsBackToSearch() async throws {
        var asked: [String] = []
        var client = LyricsClient()
        client.data = { url in
            asked.append(url.path)
            if url.path.hasSuffix("/get") {
                return try JSONSerialization.data(withJSONObject: ["statusCode": 404])
            }
            return try JSONSerialization.data(withJSONObject: [
                ["syncedLyrics": "[00:01.00]found by searching"],
            ])
        }

        let lyrics = await client.lyrics(for: track)

        XCTAssertEqual(asked, ["/api/get", "/api/search"])
        XCTAssertEqual(lyrics?.line(at: 5)?.text, "found by searching")
    }

    /// And a hit does not go on to search -- two requests where one would do
    /// is two requests every time a song changes.
    func test_aHitDoesNotSearchAsWell() async throws {
        var asked: [String] = []
        var client = LyricsClient()
        client.data = { url in
            asked.append(url.path)
            return try JSONSerialization.data(withJSONObject: ["syncedLyrics": "[00:01.00]found at once"])
        }

        _ = await client.lyrics(for: track)

        XCTAssertEqual(asked, ["/api/get"])
    }

    /// Plenty of music is simply not in the index. That is the ordinary case
    /// and the panel shows the song either way.
    func test_aTrackWithNoLyricsAnywhereIsNil() async {
        var client = LyricsClient()
        client.data = { _ in try JSONSerialization.data(withJSONObject: ["statusCode": 404]) }

        let lyrics = await client.lyrics(for: track)

        XCTAssertNil(lyrics)
    }

    /// A network that never answers must not leave the caller waiting.
    func test_aFailingRequestIsNotACrash() async {
        struct Nope: Error {}
        var client = LyricsClient()
        client.data = { _ in throw Nope() }

        let lyrics = await client.lyrics(for: track)

        XCTAssertNil(lyrics)
    }
}
