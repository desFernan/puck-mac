//
//  PetHomeReportTests.swift
//  PuckTests
//
//  What the window tells pet-app about the island. Three facts that only
//  mean anything together.
//

import XCTest
@testable import Puck

final class PetHomeReportTests: XCTestCase {
    private let island = CGRect(x: 200, y: 700, width: 600, height: 90)

    private func space() throws -> GlobalScreenSpace {
        try XCTUnwrap(GlobalScreenSpace(appKitFrames: [CGRect(x: 0, y: 0, width: 1440, height: 900)]))
    }

    /// A resize produces a rect per layout pass. Reporting an unchanged one
    /// puts a message on the socket that carries no news.
    func test_anUnchangedFrameIsNotNews() {
        var report = PetHomeReport()

        XCTAssertTrue(report.setTankFrame(island))
        XCTAssertFalse(report.setTankFrame(island))
    }

    /// A closed window has no tank whatever its last reported frame was. The
    /// pet was left standing on one that no longer existed, floating in the
    /// space where the window had been.
    func test_aClosedWindowHasNoTankHoweverRecentlyItReportedOne() throws {
        var report = PetHomeReport()
        report.setTankFrame(island)
        XCTAssertNotNil(report.wireRect(in: try space()))

        report.setWindowIsOpen(false)

        XCTAssertNil(report.wireRect(in: try space()), "the frame is stale the moment the window goes")
    }

    /// Closing is not the same as being sent to the back, but it implies it:
    /// a window that is gone is not the one being looked at either.
    func test_closingAlsoStopsItBeingTheWindowInFront() {
        var report = PetHomeReport()
        report.setWindowIsFrontmost(true)

        report.setWindowIsOpen(false)

        XCTAssertFalse(report.windowIsFrontmost)
    }

    /// And the two really are separate: pinning keeps the pet home while the
    /// window sits behind something else.
    func test_aWindowBehindAnotherStillHasATank() throws {
        var report = PetHomeReport()
        report.setTankFrame(island)
        report.setWindowIsFrontmost(false)

        XCTAssertNotNil(report.wireRect(in: try space()))
        XCTAssertFalse(report.isPetVisible(in: try space()), "there, but not being looked at")
    }

    /// There has to be an island before there is a pet standing on one.
    func test_thePetIsNotVisibleWithNowhereToStand() throws {
        var report = PetHomeReport()
        report.setWindowIsFrontmost(true)

        XCTAssertFalse(report.isPetVisible(in: try space()))

        report.setTankFrame(island)
        XCTAssertTrue(report.isPetVisible(in: try space()))
    }

    /// AppKit's Y grows upward and the pet's grows down, so the island's top
    /// edge is its maxY on one side of the wire and its minY on the other.
    func test_theRectCrossesIntoThePetsOwnSpace() throws {
        var report = PetHomeReport()
        report.setTankFrame(island)

        let wire = try XCTUnwrap(report.wireRect(in: try space()))

        XCTAssertEqual(wire.y, 900 - island.maxY, accuracy: 0.0001, "the island's top edge, measured downward")
        XCTAssertEqual(wire.x, island.minX, accuracy: 0.0001)
        XCTAssertEqual(wire.width, island.width, accuracy: 0.0001)
        XCTAssertEqual(wire.height, island.height, accuracy: 0.0001)
    }
}
