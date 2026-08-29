//
//  MediaRemoteReaderTests.swift
//  PuckTests
//
//  Reading the adapter's answer, including the shapes it takes when nothing
//  useful is playing.
//

import XCTest
@testable import Puck

final class MediaRemoteReaderTests: XCTestCase {
    private func payload(_ json: String) -> MediaRemoteReader.Payload? {
        MediaRemoteReader.Payload(json: Data(json.utf8))
    }

    /// A real answer, trimmed of its artwork: a browser tab, which is the
    /// whole reason this route exists.
    func testABrowserTabIsReadLikeAnyOtherPlayer() {
        let track = payload("""
        {"playbackRate":1,"album":"","elapsedTime":41.5,
         "bundleIdentifier":"company.thebrowser.dia","processIdentifier":47485,
         "title":"HELP!! - Kobo Kanaeru (Cover)","duration":190.9,
         "artist":"KMNZ_NEROM","playing":true}
        """)?.nowPlaying()

        XCTAssertEqual(track?.title, "HELP!! - Kobo Kanaeru (Cover)")
        XCTAssertEqual(track?.artist, "KMNZ_NEROM")
        XCTAssertEqual(track?.isPlaying, true)
        XCTAssertEqual(track?.position, 41.5)
        XCTAssertEqual(track?.duration, 190.9)
        XCTAssertEqual(track?.source.reportsPosition, true, "the system route knows the playhead")
    }

    /// A player that is registered but idle -- a tab that finished playing
    /// something an hour ago -- answers with no title. There is nothing to
    /// show for it, and showing an empty line is worse than showing nothing.
    func testARegisteredButIdlePlayerIsNothing() {
        XCTAssertNil(payload("""
        {"bundleIdentifier":"company.thebrowser.dia","playing":false}
        """)?.nowPlaying())
    }

    /// Fields the adapter omits are ordinary: a podcast has no album, a live
    /// stream no duration. None of them should lose the rest of the answer.
    func testMissingFieldsDoNotLoseTheTrack() {
        let track = payload("""
        {"title":"Some Stream","bundleIdentifier":"com.apple.Safari"}
        """)?.nowPlaying()

        XCTAssertEqual(track?.title, "Some Stream")
        XCTAssertEqual(track?.artist, "")
        XCTAssertEqual(track?.duration, 0)
        XCTAssertEqual(track?.isPlaying, false)
    }

    /// The cover arrives with the track rather than being fetched after it.
    func testArtworkComesBackDecoded() {
        let base64 = Data("not really a jpeg".utf8).base64EncodedString()

        let artwork = payload("{\"title\":\"x\",\"artworkData\":\"\(base64)\"}")?.artwork

        XCTAssertEqual(artwork.map { String(decoding: $0, as: UTF8.self) }, "not really a jpeg")
    }

    /// Anything that is not the adapter's JSON -- a crash, an OS update that
    /// closed the route -- must read as "no answer" so the older ways of
    /// asking get their turn.
    func testGarbageIsNoAnswer() {
        XCTAssertNil(payload(""))
        XCTAssertNil(payload("not json at all"))
        XCTAssertNil(payload("[1,2,3]"))
    }

    /// An app nobody can look up still gets a name, because the panel prints
    /// one next to the time.
    func testAnUnknownPlayerStillGetsAName() {
        XCTAssertEqual(
            MediaRemoteReader.Payload.appName("com.example.SomePlayer"),
            "SomePlayer"
        )
        XCTAssertEqual(MediaRemoteReader.Payload.appName(""), "")
    }
}
