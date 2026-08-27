//
//  OverlayCoordinatesTests.swift
//  PuckTests
//
//  Three spaces, two of which flip Y against the third.
//

import XCTest
@testable import Puck

final class OverlayCoordinatesTests: XCTestCase {
    /// An overlay window on a secondary display: not at the origin, so a
    /// conversion that forgets to move as well as flip is visible here and
    /// invisible on the primary one.
    private let window = CGRect(x: 1440, y: 200, width: 1920, height: 1080)

    /// The property that matters and that nothing checked: the two are
    /// inverses. They were written in different files, and a pair of
    /// inverses kept apart is a pair that drifts.
    func test_windowLocalAndGlobalAppKitAreInverses() {
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 960, y: 540), CGPoint(x: 1920, y: 1080), CGPoint(x: -30, y: 2000)] {
            let roundTrip = OverlayCoordinates.windowLocal(
                fromGlobalAppKit: OverlayCoordinates.globalAppKit(fromWindowLocal: point, windowFrame: window),
                windowFrame: window
            )
            XCTAssertEqual(roundTrip.x, point.x, accuracy: 0.0001, "x drifted for \(point)")
            XCTAssertEqual(roundTrip.y, point.y, accuracy: 0.0001, "y drifted for \(point)")
        }
    }

    /// The pet's feet at the bottom of the window are at the *bottom* in
    /// AppKit's space too -- which is the smaller Y there, not the larger.
    func test_theBottomOfTheWindowIsTheBottomInBothSpaces() {
        let feet = CGPoint(x: 100, y: window.height)

        let appKit = OverlayCoordinates.globalAppKit(fromWindowLocal: feet, windowFrame: window)

        XCTAssertEqual(appKit.y, window.minY, "window-local Y grows downward and AppKit's grows up")
        XCTAssertEqual(appKit.x, window.minX + 100)
    }

    /// A click at the window's own top-left corner is window-local (0, 0),
    /// wherever that window is.
    func test_theWindowsCornerIsTheOriginOfItsOwnSpace() {
        let corner = CGPoint(x: window.minX, y: window.maxY)

        let local = OverlayCoordinates.windowLocal(fromGlobalAppKit: corner, windowFrame: window)

        XCTAssertEqual(local.x, 0, accuracy: 0.0001)
        XCTAssertEqual(local.y, 0, accuracy: 0.0001)
    }

    /// Quartz and window-local both point Y down, so this is a move and not a
    /// flip -- but the window's origin has to be moved into Quartz's space
    /// first, and that is a flip. A bare subtraction only works for a window
    /// on the primary display, which is how this went wrong before.
    func test_quartzToOverlayLocalUsesTheWindowsOriginInQuartzSpace() throws {
        let space = try XCTUnwrap(GlobalScreenSpace(
            appKitFrames: [CGRect(x: 0, y: 0, width: 1440, height: 900), window]
        ))
        let windowTopLeftInQuartz = space.normalized(fromAppKit: CGPoint(x: window.minX, y: window.maxY))

        let atCorner = OverlayCoordinates.overlayLocal(
            fromQuartz: windowTopLeftInQuartz,
            windowFrame: window,
            in: space
        )

        XCTAssertEqual(atCorner.x, 0, accuracy: 0.0001)
        XCTAssertEqual(atCorner.y, 0, accuracy: 0.0001)
    }
}
