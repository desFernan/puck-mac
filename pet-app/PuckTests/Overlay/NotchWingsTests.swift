//
//  NotchWingsTests.swift
//  PuckTests
//
//  The two constraints the shut notch's contents have to keep.
//

import SwiftUI
import XCTest
@testable import Puck

final class NotchWingsTests: XCTestCase {
    /// A MacBook notch, and the deeper menu bar a display without one gets.
    private let depths: [CGFloat] = [32, 34, 37, 24]

    /// Whatever is drawn beside the notch has to fit the space that was made
    /// for it. Grown past the wing it would sit under the hardware, where on
    /// a real MacBook there is a camera and nothing is visible at all.
    func testTheCoverFitsInsideItsWing() {
        for depth in depths {
            let wings = NotchWings(
                artwork: nil,
                isPlaying: true,
                notchSize: CGSize(width: 185, height: depth)
            )

            XCTAssertLessThanOrEqual(
                wings.coverSide, NotchPanelGeometry.wingWidth,
                "a \(depth)pt notch gives a cover wider than the wing holding it"
            )
        }
    }

    /// And the bars, which are narrower but sized independently.
    func testTheBarsFitInsideTheirWing() {
        XCTAssertLessThanOrEqual(NotchEqualizer.width, NotchPanelGeometry.wingWidth)
    }

    /// The cover must not shrink to nothing on a shallow menu bar: the wing
    /// exists so a cover can be recognised, and four points of artwork is a
    /// smudge.
    func testTheCoverStaysBigEnoughToRecogniseOnAShallowBar() {
        let wings = NotchWings(
            artwork: nil,
            isPlaying: true,
            notchSize: CGSize(width: 185, height: 16)
        )

        XCTAssertGreaterThanOrEqual(wings.coverSide, 12)
    }

    // MARK: - The bars

    /// The reported fault: the bars stopped the moment the panel was opened.
    /// Opening replaces the whole hosted view, and a repeating animation
    /// attached to a value that did not change does not survive being
    /// rebuilt. A height that is a function of the time cannot stop, so this
    /// asks the same bar for two different moments and expects two answers.
    func testABarKeepsMovingAcrossAnyRebuild() {
        let bar = NotchEqualizer.bars[0]

        let samples = stride(from: 0.0, through: 2.0, by: 0.1).map { bar.height(at: $0) }

        XCTAssertGreaterThan(Set(samples.map { Int($0 * 1000) }).count, 10,
                             "the bar is standing still")
    }

    /// It has to stay inside the space it was given, whatever the clock says.
    func testABarNeverLeavesItsOwnRange() {
        for bar in NotchEqualizer.bars {
            for step in stride(from: 0.0, through: 5.0, by: 0.01) {
                let height = bar.height(at: step)
                XCTAssertGreaterThanOrEqual(height, bar.low - 0.0001)
                XCTAssertLessThanOrEqual(height, bar.high + 0.0001)
            }
        }
    }

    /// It has to reach both ends, or the range it declares is not the range
    /// it uses and the meter looks stuck part way.
    func testABarReachesBothEnds() {
        for bar in NotchEqualizer.bars {
            let samples = stride(from: 0.0, through: bar.period, by: bar.period / 200)
                .map { bar.height(at: $0) }

            XCTAssertLessThan(samples.min() ?? 1, bar.low + (bar.high - bar.low) * 0.02)
            XCTAssertGreaterThan(samples.max() ?? 0, bar.high - (bar.high - bar.low) * 0.02)
        }
    }

    /// Three bars moving as one read as a single block flexing, so no two of
    /// them may be at the same place at the same time.
    func testTheBarsDoNotMoveTogether() {
        let atOnce = NotchEqualizer.bars.map { $0.height(at: 12.34) }

        XCTAssertEqual(Set(atOnce.map { Int($0 * 1000) }).count, atOnce.count)
    }
}
