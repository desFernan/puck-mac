//
//  SpeechBubblePlacementTests.swift
//  Puck
//
//  The bubble used to be placed once at show time; the frame loop now
//  re-runs this rule every frame, so the geometry is worth pinning down.
//

import XCTest
import CoreGraphics
@testable import Puck

final class SpeechBubblePlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let size = CGSize(width: 200, height: 100)

    /// The pet's position is its ground point, so the bubble sits above the
    /// hitbox rather than over the pet's face.
    func test_sitsAboveThePetsHead() {
        let origin = SpeechBubblePlacement.origin(
            petGroundPoint: CGPoint(x: 500, y: 100),
            petHeight: 120,
            bubbleSize: size,
            visibleFrame: screen
        )

        XCTAssertEqual(origin.x, 400, "centred on the pet")
        XCTAssertEqual(origin.y, 100 + 120 + SpeechBubblePlacement.gap)
    }

    /// A pet in the corner would otherwise put half its speech off screen.
    func test_clampsToTheVisibleFrame() {
        let origin = SpeechBubblePlacement.origin(
            petGroundPoint: CGPoint(x: 5, y: 100),
            petHeight: 120,
            bubbleSize: size,
            visibleFrame: screen
        )

        XCTAssertEqual(origin.x, SpeechBubblePlacement.margin, "left edge, with the margin")
    }

    /// Near the top it flips below the pet instead of being shoved down over
    /// its head.
    func test_flipsBelowThePetWhenThereIsNoRoomAbove() {
        let origin = SpeechBubblePlacement.origin(
            petGroundPoint: CGPoint(x: 500, y: 700),
            petHeight: 120,
            bubbleSize: size,
            visibleFrame: screen
        )

        XCTAssertEqual(origin.y, 700 - 100 - SpeechBubblePlacement.gap, "below the ground point")
    }
}
