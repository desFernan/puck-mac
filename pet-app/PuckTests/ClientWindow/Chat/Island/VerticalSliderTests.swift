//
//  VerticalSliderTests.swift
//  PuckTests
//
//  The arithmetic behind the island's size lever, which is drawn by hand
//  rather than by AppKit: where a value sits on the bar, and what a point on
//  the bar means. Both run upside down -- up is more, and screen coordinates
//  run the other way -- which is exactly the kind of thing to get backwards.
//

import XCTest
@testable import Puck

final class VerticalSliderTests: XCTestCase {
    private let range: ClosedRange<Double> = 32...200

    func test_fraction_isZeroAtTheBottomAndOneAtTheTop() {
        XCTAssertEqual(VerticalSlider.fraction(of: 32, in: range), 0)
        XCTAssertEqual(VerticalSlider.fraction(of: 200, in: range), 1)
        XCTAssertEqual(VerticalSlider.fraction(of: 116, in: range), 0.5, accuracy: 0.0001)
    }

    /// A value from somewhere else -- a stale default, a smaller island --
    /// must not draw the knob off the end of the bar.
    func test_fraction_isClampedToTheBar() {
        XCTAssertEqual(VerticalSlider.fraction(of: -50, in: range), 0)
        XCTAssertEqual(VerticalSlider.fraction(of: 5000, in: range), 1)
    }

    /// An empty range would divide by zero. It happens: the island can be
    /// dragged down to where its ceiling meets the pet's floor.
    func test_fraction_survivesAnEmptyRange() {
        XCTAssertEqual(VerticalSlider.fraction(of: 40, in: 40...40), 0)
    }

    func test_value_atTheTopOfTheBar_isTheMaximum() {
        let value = VerticalSlider.value(atY: 0, height: 100, knob: 12, in: range)

        XCTAssertEqual(value, 200, accuracy: 0.0001)
    }

    func test_value_atTheBottomOfTheBar_isTheMinimum() {
        let value = VerticalSlider.value(atY: 100, height: 100, knob: 12, in: range)

        XCTAssertEqual(value, 32, accuracy: 0.0001)
    }

    /// The knob's centre only travels between half a knob from each end, so
    /// the middle of the bar is the middle of the scale.
    func test_value_inTheMiddle_isTheMiddleOfTheScale() {
        let value = VerticalSlider.value(atY: 50, height: 100, knob: 12, in: range)

        XCTAssertEqual(value, 116, accuracy: 0.0001)
    }

    /// A drag that leaves the bar keeps pushing in that direction rather than
    /// wrapping round or jumping.
    func test_value_beyondTheBar_isClamped() {
        XCTAssertEqual(VerticalSlider.value(atY: -400, height: 100, knob: 12, in: range), 200, accuracy: 0.0001)
        XCTAssertEqual(VerticalSlider.value(atY: 400, height: 100, knob: 12, in: range), 32, accuracy: 0.0001)
    }
}
