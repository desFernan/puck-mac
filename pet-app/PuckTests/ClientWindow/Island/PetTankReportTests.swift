//
//  PetTankReportTests.swift
//  Puck
//
//  Where the pet's home is, as the window reports it. One rect: the island
//  is drawn above the split rather than inside its columns, so there is one
//  view to report and nothing to union.
//

import XCTest
import CoreGraphics
@testable import Puck

final class PetTankReportTests: XCTestCase {
    func test_theReportedFrameIsTheTank() {
        let store = ClientWindowStore(sender: UserInputSender(transport: { nil }))

        store.setTankFrame(CGRect(x: 200, y: 800, width: 600, height: 90))

        XCTAssertEqual(store.tankFrame, CGRect(x: 200, y: 800, width: 600, height: 90))
    }

    /// The island moves and resizes -- the window is resized, the lever is
    /// dragged -- and the pet is sent wherever it ends up.
    func test_aNewFrameReplacesTheOldOne() {
        let store = ClientWindowStore(sender: UserInputSender(transport: { nil }))
        store.setTankFrame(CGRect(x: 200, y: 800, width: 600, height: 90))

        store.setTankFrame(CGRect(x: 200, y: 780, width: 900, height: 110))

        XCTAssertEqual(store.tankFrame, CGRect(x: 200, y: 780, width: 900, height: 110))
    }

    /// The strip goes off screen with the window; nil is how it says so.
    func test_clearingTheFrameLeavesNoTank() {
        let store = ClientWindowStore(sender: UserInputSender(transport: { nil }))
        store.setTankFrame(CGRect(x: 200, y: 800, width: 600, height: 90))

        store.setTankFrame(nil)

        XCTAssertNil(store.tankFrame)
    }

    func test_nothingReportedMeansNoTank() {
        let store = ClientWindowStore(sender: UserInputSender(transport: { nil }))

        XCTAssertNil(store.tankFrame)
    }

    /// Closing the window takes the tank with it -- the pet was left standing
    /// in the space where the window had been.
    func test_aClosedWindowHasNoTank() {
        let store = ClientWindowStore(sender: UserInputSender(transport: { nil }))
        store.setTankFrame(CGRect(x: 200, y: 800, width: 600, height: 90))

        store.setWindowIsOpen(false)

        XCTAssertFalse(store.windowIsOpen)
        XCTAssertFalse(store.windowIsFrontmost, "a closed window is not the one being looked at either")
    }

    /// The segments are remembered, so reopening does not depend on a layout
    /// pass arriving before the pet is asked for.
    func test_reopeningRestoresTheTank() {
        let store = ClientWindowStore(sender: UserInputSender(transport: { nil }))
        let frame = CGRect(x: 200, y: 800, width: 600, height: 90)
        store.setTankFrame(frame)
        store.setWindowIsOpen(false)

        store.setWindowIsOpen(true)

        XCTAssertTrue(store.windowIsOpen)
        XCTAssertEqual(store.tankFrame, frame)
    }
}
