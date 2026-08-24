//
//  FlipAnimationTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  The paper-flip turn's pure math.
//

import XCTest
@testable import Puck

final class FlipAnimationTests: XCTestCase {
    private let right: CGFloat = 0
    private let left: CGFloat = .pi

    func test_startsAtTheAngleItTurnsFrom() {
        let angle = FlipAnimation.angle(elapsed: 0, from: right, to: left, duration: 0.12)

        XCTAssertEqual(FlipAnimation.horizontalScale(atAngle: angle), 1, accuracy: 0.0001)
    }

    func test_endsAtTheAngleItTurnsTo() {
        let angle = FlipAnimation.angle(elapsed: 0.12, from: right, to: left, duration: 0.12)

        XCTAssertEqual(FlipAnimation.horizontalScale(atAngle: angle), -1, accuracy: 0.0001)
    }

    func test_isEdgeOnHalfwayThrough() {
        let angle = FlipAnimation.angle(elapsed: 0.06, from: right, to: left, duration: 0.12)

        XCTAssertEqual(FlipAnimation.horizontalScale(atAngle: angle), 0, accuracy: 0.0001)
    }

    func test_pastTheEnd_staysSettled() {
        let angle = FlipAnimation.angle(elapsed: 10, from: right, to: left, duration: 0.12)

        XCTAssertEqual(angle, left, accuracy: 0.0001)
    }

    /// A cosine sweep spends longer near full width than a linear one would —
    /// that's what makes it read as a rotating sheet rather than a squash.
    func test_widthLingersNearFullEarlyInTheTurn() {
        let quarter = FlipAnimation.angle(elapsed: 0.03, from: right, to: left, duration: 0.12)

        let scale = FlipAnimation.horizontalScale(atAngle: quarter)
        XCTAssertEqual(scale, 0.7071, accuracy: 0.001, "cos(45°), not the 0.5 a linear ramp would give")
    }

    // MARK: - Turning back mid-turn

    /// The reason the turn is tracked as an angle at all: at the halfway
    /// point the sprite's scale is exactly 0, and anything interpolating in
    /// scale-space multiplies through that zero and can never come back out.
    func test_turningBackFromEdgeOn_recoversToFullWidth() {
        let edgeOn = FlipAnimation.angle(elapsed: 0.06, from: right, to: left, duration: 0.12)
        let back = FlipAnimation.duration(from: edgeOn, to: right)

        let finished = FlipAnimation.angle(elapsed: back, from: edgeOn, to: right, duration: back)

        XCTAssertEqual(FlipAnimation.horizontalScale(atAngle: finished), 1, accuracy: 0.0001)
    }

    /// A turn that only has to cover half the arc takes half the time, so
    /// changing direction repeatedly doesn't get progressively more sluggish.
    func test_aPartialTurnIsProportionallyShorter() {
        let halfway: CGFloat = .pi / 2

        XCTAssertEqual(FlipAnimation.duration(from: halfway, to: right), FlipAnimation.duration / 2, accuracy: 0.0001)
        XCTAssertEqual(FlipAnimation.duration(from: right, to: left), FlipAnimation.duration, accuracy: 0.0001)
    }

    func test_aZeroLengthTurnDoesNotDivideByZero() {
        let angle = FlipAnimation.angle(elapsed: 0.5, from: right, to: right, duration: 0)

        XCTAssertEqual(angle, right, accuracy: 0.0001)
    }

    func test_facingAngles() {
        XCTAssertEqual(FlipAnimation.angle(facing: .right), 0)
        XCTAssertEqual(FlipAnimation.angle(facing: .left), .pi)
    }
}
