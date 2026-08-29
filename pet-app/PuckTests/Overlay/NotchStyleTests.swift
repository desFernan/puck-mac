//
//  NotchStyleTests.swift
//  PuckTests
//
//  The two claims the palette makes that are worth holding it to.
//

import SwiftUI
import XCTest
@testable import Puck

final class NotchStyleTests: XCTestCase {
    /// The reported fault: the light along the top edge is what makes a
    /// closed notch read as part of the machine, but across an open panel
    /// the same gradient is a bright streak that makes it look like a window
    /// drawn on the screen. It belongs to the closed shape only.
    func testTheTopLightIsClosedOnly() {
        XCTAssertEqual(NotchShell<EmptyView>.topLightOpacity(isOpen: false), 1)
        XCTAssertEqual(NotchShell<EmptyView>.topLightOpacity(isOpen: true), 0)
    }

    /// A surface has to get brighter as it goes from resting to pointed at
    /// to on, or the three states it is meant to tell apart are not told
    /// apart. Written down because they are three separate constants that
    /// nothing else would keep in order.
    func testASurfaceBrightensThroughItsStates() {
        XCTAssertLessThan(opacity(NotchStyle.surface), opacity(NotchStyle.surfaceHovered))
        XCTAssertLessThan(opacity(NotchStyle.surfaceHovered), opacity(NotchStyle.surfaceActive))
        XCTAssertLessThan(opacity(NotchStyle.border), opacity(NotchStyle.borderActive))
    }

    /// Secondary text must stay quieter than the line it sits under, and
    /// figures quieter again.
    func testTextRecedesDownTheHierarchy() {
        XCTAssertLessThan(opacity(NotchStyle.mutedForeground), opacity(NotchStyle.foreground))
        XCTAssertLessThan(opacity(NotchStyle.subtleForeground), opacity(NotchStyle.mutedForeground))
    }

    private func opacity(_ color: Color) -> CGFloat {
        NSColor(color).usingColorSpace(.deviceRGB)?.alphaComponent ?? -1
    }
}
