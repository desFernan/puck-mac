//
//  NotchPanelGeometryTests.swift
//  PuckTests
//
//  Opening and closing a panel by pointing at it, which is a hysteresis
//  problem wearing a hover's clothes.
//

import XCTest
@testable import Puck

final class NotchPanelGeometryTests: XCTestCase {
    /// A notch at the top middle of a 3440x1440 screen, in AppKit's space.
    private let notch = CGRect(x: 1627, y: 1410, width: 185, height: 30)

    // MARK: - The window

    /// One size, always. A window that resized on hover would take the cursor
    /// out of itself on the frame it shrank, which is a panel that flickers.
    func test_theWindowIsAlwaysTheOpenSize() {
        let frame = NotchPanelGeometry.windowFrame(notch: notch)

        XCTAssertEqual(frame.width, NotchPanelGeometry.openWidth)
        XCTAssertEqual(frame.height, NotchPanelGeometry.openHeight)
    }

    /// Hanging from the notch, centred on it: the panel comes out of the
    /// notch, so its top edge is the notch's.
    func test_theWindowHangsFromTheNotch() {
        let frame = NotchPanelGeometry.windowFrame(notch: notch)

        XCTAssertEqual(frame.midX, notch.midX, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, notch.maxY, accuracy: 0.5)
    }

    // MARK: - Opening and closing

    private func open(at cursor: CGPoint, isOpen: Bool) -> Bool {
        NotchPanelGeometry.shouldBeOpen(cursor: cursor, notch: notch, isOpen: isOpen)
    }

    func test_pointingAtTheNotchOpensIt() {
        XCTAssertTrue(open(at: CGPoint(x: notch.midX, y: notch.midY), isOpen: false))
    }

    func test_pointingElsewhereDoesNot() {
        XCTAssertFalse(open(at: CGPoint(x: 100, y: 100), isOpen: false))
        XCTAssertFalse(open(at: CGPoint(x: notch.midX, y: notch.minY - 200), isOpen: false))
    }

    /// The notch's bottom edge is the top of the screen's content, so a
    /// pointer moving up to it stops exactly on the boundary. Without slack
    /// the panel would open only if you overshot into the bezel.
    func test_arrivingAtItsEdgeCounts() {
        XCTAssertTrue(open(at: CGPoint(x: notch.midX, y: notch.minY - 1), isOpen: false))
    }

    /// Once open, the panel is what the pointer is heading for -- closing the
    /// moment it leaves the notch would shut it before it arrived.
    func test_movingDownIntoThePanelKeepsItOpen() {
        let insidePanel = CGPoint(x: notch.midX, y: notch.maxY - NotchPanelGeometry.openHeight + 20)

        XCTAssertTrue(open(at: insidePanel, isOpen: true))
        XCTAssertFalse(open(at: insidePanel, isOpen: false), "but it could not have opened from there")
    }

    /// The same position answering differently depending on which way it is
    /// moving is the whole point: it is what stops the edge flickering.
    func test_theTwoAnswersDifferInTheGapBetweenThem() {
        let inPanelNotNotch = CGPoint(x: notch.midX - 150, y: notch.maxY - 60)

        XCTAssertTrue(open(at: inPanelNotNotch, isOpen: true))
        XCTAssertFalse(open(at: inPanelNotNotch, isOpen: false))
    }

    func test_leavingAltogetherClosesIt() {
        XCTAssertFalse(open(at: CGPoint(x: notch.midX, y: 400), isOpen: true))
    }

    /// The window is the only thing that clips the panel, so it has to be at
    /// least as tall as what is drawn in it. Set as a measured number once,
    /// this drifted the moment a band changed and the bottom row was cut off.
    func testTheWindowIsTallEnoughForWhatIsDrawnInIt() {
        let content = NotchPanelGeometry.topInset
            + NotchPanelGeometry.musicBandHeight
            + NotchPanelGeometry.actionBandHeight
            + NotchPanelGeometry.bottomInset

        XCTAssertGreaterThanOrEqual(NotchPanelGeometry.openHeight, content)
    }

    /// Wide enough that what opens reads as a panel coming out of the notch
    /// rather than as the notch itself growing downward.
    func testTheOpenPanelIsWiderThanAnyNotch() {
        // Wider than the widest hardware notch by a clear margin.
        XCTAssertGreaterThan(NotchPanelGeometry.openWidth, 220)
    }

    /// The reported fault: shut, the panel opened from most of the width of
    /// the open panel -- the size it is not. Arriving is measured against the
    /// notch, and a point outside the notch is not arriving at it however
    /// much of the open panel would cover it.
    func testAPointOutsideTheNotchDoesNotOpenAShutPanel() {
        let notch = CGRect(x: 1628, y: 1400, width: 185, height: 34)
        // Inside the open panel's width, well outside the notch's.
        let beside = CGPoint(x: notch.maxX + 60, y: notch.midY)

        XCTAssertTrue(NotchPanelGeometry.windowFrame(notch: notch).contains(beside),
                      "the point has to be one the open panel would cover, or this proves nothing")
        XCTAssertFalse(NotchPanelGeometry.shouldBeOpen(cursor: beside, notch: notch, isOpen: false))
    }

    /// The same point keeps an already-open panel open, which is the
    /// hysteresis this pair exists for.
    func testTheSamePointKeepsAnOpenPanelOpen() {
        let notch = CGRect(x: 1628, y: 1400, width: 185, height: 34)
        let beside = CGPoint(x: notch.maxX + 60, y: notch.midY)

        XCTAssertTrue(NotchPanelGeometry.shouldBeOpen(cursor: beside, notch: notch, isOpen: true))
    }

    /// Pointing at the notch itself opens it, which is the whole feature.
    func testPointingAtTheNotchOpensIt() {
        let notch = CGRect(x: 1628, y: 1400, width: 185, height: 34)

        XCTAssertTrue(NotchPanelGeometry.shouldBeOpen(
            cursor: CGPoint(x: notch.midX, y: notch.midY), notch: notch, isOpen: false
        ))
    }
}
