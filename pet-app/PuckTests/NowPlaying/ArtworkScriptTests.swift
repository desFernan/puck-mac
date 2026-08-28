//
//  ArtworkScriptTests.swift
//  PuckTests
//
//  The two apps hand over a cover in two different ways, and the scripts
//  have to ask each one in its own words.
//

import XCTest
@testable import Puck

final class ArtworkScriptTests: XCTestCase {
    /// Spotify's covers live on the web, so what is asked for is an address.
    func testSpotifyIsAskedForAnAddress() {
        let script = MusicApps.spotifyArtworkScript()

        XCTAssertTrue(script.contains("tell application \"Spotify\""))
        XCTAssertTrue(script.contains("artwork url of current track"))
    }

    /// Music's covers are bytes, so it is asked to write them where they can
    /// be read back whole.
    func testMusicIsAskedToWriteTheBytesOut() {
        let file = URL(fileURLWithPath: "/tmp/puck-cover-test")

        let script = MusicApps.musicArtworkScript(writingTo: file)

        XCTAssertTrue(script.contains("raw data of artwork 1 of current track"))
        XCTAssertTrue(script.contains("/tmp/puck-cover-test"))
        XCTAssertTrue(script.contains("close access f"), "the file must be closed even so")
    }

    /// Skipping through tracks starts a read before the last has finished,
    /// and two of them sharing a path means one reads the other's bytes.
    func testEachReadGetsItsOwnFile() {
        XCTAssertNotEqual(MusicApps.artworkFile(), MusicApps.artworkFile())
    }

    /// A track with no art is the ordinary case -- a podcast, a stream -- and
    /// the script must come back empty rather than fail the whole read.
    func testNoArtworkIsSurvivable() {
        for script in [MusicApps.spotifyArtworkScript(),
                       MusicApps.musicArtworkScript(writingTo: MusicApps.artworkFile())] {
            XCTAssertTrue(script.contains("on error"), script)
        }
    }
}
