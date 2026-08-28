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

        XCTAssertEqual(scale, notchHeight / NotchPanelGeometry.openHeight, accuracy: 0.0001)
    }

    /// A display whose notch is somehow as deep as the open panel should
    /// leave the content alone rather than blow it up.
    func testTheContentIsNeverScaledUp() {
        let scale = NotchShell<EmptyView>.contentScale(
            notchHeight: NotchPanelGeometry.openHeight * 3
        )

        XCTAssertEqual(scale, 1)
    }

    /// A screen that reports no notch at all must not fold the content
    /// inside out.
    func testANonsenseNotchDepthStaysInRange() {
        XCTAssertEqual(NotchShell<EmptyView>.contentScale(notchHeight: 0), 0)
        XCTAssertEqual(NotchShell<EmptyView>.contentScale(notchHeight: -40), 0)
    }
}
