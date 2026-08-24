//
//  ScreenBoundsTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Keeping the pet on screen and bouncing it off the edges, measured by the
//  artwork's own outline rather than the layer's bounding box.
//

import XCTest
@testable import Puck

final class ScreenBoundsTests: XCTestCase {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
    /// A 100pt-wide pet standing on its position: 50pt either side, 120 tall.
    private let outline = CGRect(x: -50, y: -120, width: 100, height: 120)

    // MARK: - Containment

    func test_contain_stopsTheOutlineAtTheEdge_notTheCentre() {
        let contained = ScreenBounds.contain(CGPoint(x: 980, y: 400), visualBounds: outline, in: area)

        // 950, not 1000: at 1000 the right half of the pet is off screen.
        XCTAssertEqual(contained.x, 950)
    }

    func test_contain_stopsAtTheLeftEdgeToo() {
        let contained = ScreenBounds.contain(CGPoint(x: 10, y: 400), visualBounds: outline, in: area)

        XCTAssertEqual(contained.x, 50)
    }

    func test_contain_leavesAPositionAlreadyInsideAlone() {
        let contained = ScreenBounds.contain(CGPoint(x: 500, y: 400), visualBounds: outline, in: area)

        XCTAssertEqual(contained, CGPoint(x: 500, y: 400))
    }

    /// The outline is measured from the artwork, so it needn't be centred on
    /// the pet's position -- a character leaning right has more of itself on
    /// one side, and the edge it stops at differs accordingly.
    func test_contain_respectsAnAsymmetricOutline() {
        let leaningRight = CGRect(x: -20, y: -120, width: 100, height: 120)

        let atRight = ScreenBounds.contain(CGPoint(x: 990, y: 0), visualBounds: leaningRight, in: area)
        let atLeft = ScreenBounds.contain(CGPoint(x: 0, y: 0), visualBounds: leaningRight, in: area)

        XCTAssertEqual(atRight.x, 920, "80pt of artwork sits to the right of the position")
        XCTAssertEqual(atLeft.x, 20, "and 20pt to the left")
    }

    func test_contain_neverMovesThePetVertically() {
        let contained = ScreenBounds.contain(CGPoint(x: -500, y: 12_345), visualBounds: outline, in: area)

        XCTAssertEqual(contained.y, 12_345, "vertical placement belongs to landing surfaces")
    }

    // MARK: - Bouncing

    func test_bounce_reversesDirectionAtTheRightEdge() {
        let bounce = ScreenBounds.bounceHorizontally(
            position: CGPoint(x: 960, y: 0), // 10pt past the 950 limit
            velocity: 800,
            visualBounds: outline,
            in: area
        )

        XCTAssertLessThan(bounce.velocity, 0, "heading back the other way")
        XCTAssertEqual(bounce.velocity, -800 * ScreenBounds.restitution, accuracy: 0.001, "having lost energy")
        XCTAssertEqual(bounce.position.x, 940, "reflected back inside by how far it overshot")
    }

    func test_bounce_reversesDirectionAtTheLeftEdge() {
        let bounce = ScreenBounds.bounceHorizontally(
            position: CGPoint(x: 30, y: 0), // 20pt past the 50 limit
            velocity: -600,
            visualBounds: outline,
            in: area
        )

        XCTAssertEqual(bounce.velocity, 600 * ScreenBounds.restitution, accuracy: 0.001)
        XCTAssertEqual(bounce.position.x, 70)
    }

    func test_bounce_leavesAPetInTheMiddleAlone() {
        let bounce = ScreenBounds.bounceHorizontally(
            position: CGPoint(x: 500, y: 0),
            velocity: 800,
            visualBounds: outline,
            in: area
        )

        XCTAssertEqual(bounce.velocity, 800)
        XCTAssertEqual(bounce.position.x, 500)
    }

    /// A slow nudge into the wall should settle against it (velocity 0).
    /// Bouncing at any speed leaves the pet buzzing on the edge in
    /// ever-smaller hops.
    func test_bounce_belowTheMinimumSpeed_restsAgainstTheEdge() {
        let bounce = ScreenBounds.bounceHorizontally(
            position: CGPoint(x: 955, y: 0),
            velocity: 40,
            visualBounds: outline,
            in: area
        )

        XCTAssertEqual(bounce.velocity, 0)
        XCTAssertEqual(bounce.position.x, 950, "resting exactly on the limit")
    }

    /// Repeated bounces have to run out of energy rather than continuing
    /// forever.
    func test_bounce_repeated_eventuallySettles() {
        var position = CGPoint(x: 960, y: 0)
        var velocity: CGFloat = 900

        for _ in 0..<20 {
            let bounce = ScreenBounds.bounceHorizontally(
                position: position, velocity: velocity, visualBounds: outline, in: area
            )
            position = bounce.position
            velocity = bounce.velocity
            // Drive it straight back into the same wall each time.
            if velocity != 0 {
                position = CGPoint(x: 960, y: 0)
                velocity = abs(velocity)
            }
        }

        XCTAssertEqual(velocity, 0, "the bouncing dies out")
    }

    // MARK: - Ceiling

    /// Thrown up hard, the pet must come off the top
    /// of the screen instead of leaving it.
    func test_ceiling_bouncesTheHeadOffTheTop() {
        // The outline reaches 120pt above the position, so the head meets
        // y=0 when the position is at 120.
        let bounce = ScreenBounds.bounceOffCeiling(
            position: CGPoint(x: 500, y: 110), // 10pt too high
            velocity: -700, // negative = travelling upward
            visualBounds: outline,
            in: area
        )

        XCTAssertGreaterThan(bounce.velocity, 0, "now heading back down")
        XCTAssertEqual(bounce.velocity, 700 * ScreenBounds.restitution, accuracy: 0.001)
        XCTAssertEqual(bounce.position.y, 130, "reflected back down by its overshoot")
    }

    func test_ceiling_ignoresAPetFallingDownward() {
        let bounce = ScreenBounds.bounceOffCeiling(
            position: CGPoint(x: 500, y: 110),
            velocity: 400, // falling
            visualBounds: outline,
            in: area
        )

        XCTAssertEqual(bounce.velocity, 400, "coming down is a landing, not a ceiling hit")
        XCTAssertEqual(bounce.position.y, 110, "and it is left where it was")
    }

    func test_ceiling_ignoresAPetBelowTheCeiling() {
        let bounce = ScreenBounds.bounceOffCeiling(
            position: CGPoint(x: 500, y: 400),
            velocity: -700,
            visualBounds: outline,
            in: area
        )

        XCTAssertEqual(bounce.velocity, -700)
    }

    /// A tall avatar's head reaches the ceiling before a short one's, so the
    /// bounce point follows the measured outline rather than the position.
    func test_ceiling_limitFollowsTheOutlineHeight() {
        let tall = CGRect(x: -50, y: -300, width: 100, height: 300)
        let rising = CGPoint(x: 500, y: 290)

        let bounce = ScreenBounds.bounceOffCeiling(
            position: rising,
            velocity: -700,
            visualBounds: tall,
            in: area
        )

        // Its head is at 290 - 300 = -10, already through the ceiling at 0,
        // so the limit it reflects about is 300 rather than its own position.
        XCTAssertEqual(bounce.velocity, 700 * ScreenBounds.restitution, "bounced back downward")
        XCTAssertEqual(bounce.position.y, 2 * 300 - 290, "reflected about the tall outline's limit")

        // The same point, with the short outline this file's other tests use,
        // is nowhere near the ceiling -- which is the whole claim: the limit
        // follows the measured outline, not the position.
        let short = ScreenBounds.bounceOffCeiling(
            position: rising,
            velocity: -700,
            visualBounds: outline,
            in: area
        )

        XCTAssertEqual(short.velocity, -700, "a short avatar at the same point has not reached it")
        XCTAssertEqual(short.position.y, rising.y)
    }

    func test_ceiling_belowTheMinimumSpeed_stopsAtTheCeiling() {
        let bounce = ScreenBounds.bounceOffCeiling(
            position: CGPoint(x: 500, y: 115),
            velocity: -40,
            visualBounds: outline,
            in: area
        )

        XCTAssertEqual(bounce.velocity, 0)
        XCTAssertEqual(bounce.position.y, 120)
    }

    // MARK: - bounceOffFloor (a hard
    // landing should bounce a couple of times and slide, not stop dead the
    // instant it touches down)

    func test_floor_bouncesAHardImpactOffTheGround() {
        let bounce = ScreenBounds.bounceOffFloor(
            position: CGPoint(x: 500, y: 210), // 10pt past the floor
            velocity: 700, // positive = falling
            floorY: 200
        )

        XCTAssertLessThan(bounce.velocity, 0, "now heading back up")
        XCTAssertEqual(bounce.velocity, -700 * ScreenBounds.landingRestitution, accuracy: 0.001)
        XCTAssertEqual(bounce.position.y, 190, "reflected back up by its overshoot")
    }

    func test_floor_ignoresAPetTravellingUpward() {
        let bounce = ScreenBounds.bounceOffFloor(position: CGPoint(x: 500, y: 210), velocity: -400, floorY: 200)

        XCTAssertEqual(bounce.velocity, -400, "already heading away from the floor")
        XCTAssertEqual(bounce.position.y, 210, "left where it was")
    }

    func test_floor_ignoresAPetAboveTheFloor() {
        let bounce = ScreenBounds.bounceOffFloor(position: CGPoint(x: 500, y: 100), velocity: 700, floorY: 200)

        XCTAssertEqual(bounce.velocity, 700)
        XCTAssertEqual(bounce.position.y, 100)
    }

    func test_floor_belowTheMinimumBounceSpeed_restsOnTheFloor() {
        let bounce = ScreenBounds.bounceOffFloor(position: CGPoint(x: 500, y: 205), velocity: 200, floorY: 200)

        XCTAssertEqual(bounce.velocity, 0)
        XCTAssertEqual(bounce.position.y, 200)
    }

    /// Landing loses more energy per bounce than a wall/ceiling hit does -- a
    /// soft flop onto the ground, not a rubber ball off a wall.
    func test_floor_restitutionIsLowerThanWallBounce() {
        XCTAssertLessThan(ScreenBounds.landingRestitution, ScreenBounds.restitution)
    }

    func test_floor_repeated_eventuallySettles() {
        var position = CGPoint(x: 0, y: 210)
        var velocity: CGFloat = 900
        var bouncedAtLeastOnce = false

        for _ in 0..<20 {
            let bounce = ScreenBounds.bounceOffFloor(position: position, velocity: velocity, floorY: 200)
            position = bounce.position
            velocity = bounce.velocity
            // Drive it straight back down into the same floor each time.
            if velocity != 0 {
                bouncedAtLeastOnce = true
                position = CGPoint(x: 0, y: 210)
                velocity = abs(velocity)
            }
        }

        XCTAssertEqual(velocity, 0, "the bouncing dies out")
        XCTAssertTrue(bouncedAtLeastOnce)
    }

    /// Degenerate but reachable via the size slider: an avatar scaled wider
    /// than the display has no position that fits. It must still end up
    /// somewhere visible rather than at an inverted clamp.
    func test_contain_petWiderThanTheScreen_pinsToTheLeftEdge() {
        let huge = CGRect(x: -900, y: -200, width: 1800, height: 200)

        let contained = ScreenBounds.contain(CGPoint(x: 500, y: 0), visualBounds: huge, in: area)

        XCTAssertEqual(contained.x, 900, "its left edge sits on the screen's left edge")
    }
}
