//
//  DockInsetTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The pet's "ground" (roamableArea's bottom edge) used to be the literal
//  bottom of the physical screen, which is exactly where the Dock sits --
//  since the Dock's window level is higher than our overlay's, the pet's
//  lower half rendered *underneath* the Dock instead of standing in front of
//  it -- it looked buried/stuck into the Dock. This computes
//  how much to leave clear at the bottom, from NSScreen's own
//  frame/visibleFrame difference, without touching GlobalScreenSpace's
//  screen-space model (which several other subsystems depend on the
//  invariant "primary screen frame starts at (0,0)" for).
//

import XCTest
import CoreGraphics
@testable import Puck

final class DockInsetTests: XCTestCase {
    func test_dockAtTheBottom_returnsItsHeight() {
        // AppKit bottom-left origin: the Dock eats into the frame from y=0 up.
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = CGRect(x: 0, y: 70, width: 1440, height: 830)

        XCTAssertEqual(DockInset.bottomInset(screenFrame: screenFrame, visibleFrame: visibleFrame), 70)
    }

    func test_dockHiddenOrOnASide_returnsZero() {
        // visibleFrame's bottom matches screenFrame's -- nothing eating into
        // the bottom edge (auto-hidden Dock, or positioned left/right).
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 875)

        XCTAssertEqual(DockInset.bottomInset(screenFrame: screenFrame, visibleFrame: visibleFrame), 0)
    }

    func test_neverNegative() {
        // Defensive: a visibleFrame reported below the screen frame (shouldn't
        // happen, but this is arithmetic on OS-reported values) doesn't produce
        // a negative inset that would grow the roamable area instead of shrinking it.
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = CGRect(x: 0, y: -10, width: 1440, height: 900)

        XCTAssertEqual(DockInset.bottomInset(screenFrame: screenFrame, visibleFrame: visibleFrame), 0)
    }
}
