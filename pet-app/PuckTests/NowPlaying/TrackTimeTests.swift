//
//  TrackTimeTests.swift
//  PuckTests
//
//  Seconds as a clock reads them, including the ones a music app only
//  reports for a frame.
//

import XCTest
@testable import Puck

final class TrackTimeTests: XCTestCase {
    func testMinutesAndSeconds() {
        XCTAssertEqual(TrackTime.text(0), "0:00")
        XCTAssertEqual(TrackTime.text(9), "0:09")
        XCTAssertEqual(TrackTime.text(83), "1:23")
        XCTAssertEqual(TrackTime.text(600), "10:00")
    }

    /// A long mix or a podcast, where minutes alone stop meaning anything.
    func testHoursAppearOnlyWhenThereAreSome() {
        XCTAssertEqual(TrackTime.text(3599), "59:59")
        XCTAssertEqual(TrackTime.text(3600), "1:00:00")
        XCTAssertEqual(TrackTime.text(3661), "1:01:01")
    }

    /// Seeking can report a negative position for a frame, and a stream
    /// reports no length at all. Neither should print as a broken clock.
    func testNonsenseReadsAsZero() {
        XCTAssertEqual(TrackTime.text(-4), "0:00")
        XCTAssertEqual(TrackTime.text(.nan), "0:00")
        XCTAssertEqual(TrackTime.text(.infinity), "0:00")
    }

    /// Rounded down, so the clock never shows a second the track has not
    /// reached.
    func testPartialSecondsRoundDown() {
        XCTAssertEqual(TrackTime.text(59.9), "0:59")
    }
}
