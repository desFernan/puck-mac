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

    // MARK: - Where the playhead actually is

    private let started = MediaRemoteReader.Payload.date("2026-08-29T02:37:41Z")!

    private func playing(_ elapsed: Double, duration: Double = 233.7) -> MediaRemoteReader.Payload? {
        payload("""
        {"title":"a song","playing":true,"elapsedTime":\(elapsed),
         "duration":\(duration),"playbackRate":1,
         "timestamp":"2026-08-29T02:37:41Z"}
        """)
    }

    /// The reported fault: a browser playing a video reports its position
    /// once, when playback starts, and then says nothing. Asking again a
    /// minute later returns the same zero and the same timestamp, so the
    /// progress bar sat still through the whole song. How long ago it was
    /// reported is the missing half.
    func testThePlayheadAdvancesFromWhenItWasLastReported() {
        let position = playing(0)?.position(now: started.addingTimeInterval(45))

        XCTAssertEqual(position ?? -1, 45, accuracy: 0.001)
    }

    /// A player that does keep its position up to date must not have the gap
    /// added twice.
    func testAFreshlyReportedPositionIsLeftAlone() {
        let position = playing(90)?.position(now: started)

        XCTAssertEqual(position ?? -1, 90, accuracy: 0.001)
    }

    /// A paused player is already where it says it is; the wall clock keeps
    /// going and the playhead does not.
    func testAPausedPlayheadDoesNotMove() {
        let paused = payload("""
        {"title":"a song","playing":false,"elapsedTime":30,"duration":200,
         "timestamp":"2026-08-29T02:37:41Z"}
        """)

        XCTAssertEqual(paused?.position(now: started.addingTimeInterval(600)) ?? -1, 30, accuracy: 0.001)
    }

    /// Half speed covers half the ground.
    func testPlaybackSpeedIsAccountedFor() {
        let half = payload("""
        {"title":"a song","playing":true,"elapsedTime":0,"duration":200,
         "playbackRate":0.5,"timestamp":"2026-08-29T02:37:41Z"}
        """)

        XCTAssertEqual(half?.position(now: started.addingTimeInterval(60)) ?? -1, 30, accuracy: 0.001)
    }

    /// A track left playing past its stated length should sit at the end
    /// rather than draw a bar past full.
    func testThePlayheadStopsAtTheEnd() {
        let position = playing(0, duration: 100)?.position(now: started.addingTimeInterval(500))

        XCTAssertEqual(position ?? -1, 100, accuracy: 0.001)
    }

    /// A machine whose clock moved backwards is not a track playing in
    /// reverse.
    func testAClockThatWentBackwardsDoesNotRewind() {
        let position = playing(20)?.position(now: started.addingTimeInterval(-3600))

        XCTAssertEqual(position ?? -1, 20, accuracy: 0.001)
    }

    /// A player that sends no timestamp still shows the position it gave.
    func testNoTimestampMeansTakeThePositionAsGiven() {
        let position = payload("""
        {"title":"a song","playing":true,"elapsedTime":12,"duration":200}
        """)?.position(now: started.addingTimeInterval(45))

        XCTAssertEqual(position ?? -1, 12, accuracy: 0.001)
    }

    /// Both shapes the adapter sends, since one parser rejects the other.
    func testBothTimestampShapesParse() {
        XCTAssertNotNil(MediaRemoteReader.Payload.date("2026-08-29T02:37:41Z"))
        XCTAssertNotNil(MediaRemoteReader.Payload.date("2026-08-29T02:37:41.532Z"))
        XCTAssertNil(MediaRemoteReader.Payload.date("not a date"))
    }
}
