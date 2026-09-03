//
//  NotchShellTests.swift
//  PuckTests
//
//  That the panel closes as one thing.
//

import SwiftUI
import XCTest
@testable import Puck

final class NotchShellTests: XCTestCase {
    /// The reported fault: the shell shrank into the bezel while the content
    /// inside kept its size and slid up out of it, so the two halves of the
    /// same close disagreed about what was happening. The content collapses
    /// by the shell's own height ratio instead.
    func testTheContentCollapsesByTheSameRatioAsTheShell() {
        let notchHeight: CGFloat = 32

        let scale = NotchShell<EmptyView>.contentScale(notchHeight: notchHeight)

        XCTAssertEqual(
            scale,
            notchHeight / NotchPanelGeometry.openHeight(notchDepth: notchHeight),
            accuracy: 0.0001
        )
    }

    /// The content is never blown up, whatever the notch's depth.
    ///
    /// The panel now grows to clear a deeper housing, so the shut shape can
    /// no longer be taller than the open one and the clamp should never have
    /// anything to do -- which is worth checking rather than assuming, since
    /// it is a relationship between two numbers that are set apart.
    func testTheContentIsNeverScaledUp() {
        for depth in stride(from: CGFloat(1), through: 400, by: 7) {
            XCTAssertLessThanOrEqual(
                NotchShell<EmptyView>.contentScale(notchHeight: depth),
                1,
                "a \(depth)pt notch scales the content up"
            )
        }
    }

    /// A screen that reports no notch at all must not fold the content
    /// inside out.
    func testANonsenseNotchDepthStaysInRange() {
        XCTAssertEqual(NotchShell<EmptyView>.contentScale(notchHeight: 0), 0)
        XCTAssertEqual(NotchShell<EmptyView>.contentScale(notchHeight: -40), 0)
    }
}
