//
//  ToyApproachTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Where the pet stands to play with the toy, so it doesn't stand on top of it.
//

import XCTest
@testable import Puck

final class ToyApproachTests: XCTestCase {
    /// A 40x40 toy resting on a floor at y = 500: its centre is 20 above it.
    private let toy = CGPoint(x: 500, y: 480)
    private let toyBounds = CGRect(x: -20, y: -20, width: 40, height: 40)
    /// A pet 100 wide, standing on its feet.
    private let petBounds = CGRect(x: -50, y: -120, width: 100, height: 120)
    private let floor: CGFloat = 500

    private func approach(from petX: CGFloat) -> CGPoint {
        ToyApproach.standingPosition(
            toyPosition: toy,
            toyBounds: toyBounds,
            petPosition: CGPoint(x: petX, y: floor),
            petBounds: petBounds
        )
    }

    /// The whole point: the pet's feet stay on the ground the toy rests on,
    /// not up at the toy's centre, which is standing on top of it.
    func test_thePetWalksToTheSurfaceTheToyRestsOn() {
        XCTAssertEqual(approach(from: 100).y, floor)
        XCTAssertEqual(approach(from: 900).y, floor)
    }

    func test_thePetStopsBesideTheToyNotInsideIt() {
        let fromLeft = approach(from: 100)

        // Toy's left edge is at 480; the pet's artwork reaches 50 to its
        // right, plus the gap.
        XCTAssertEqual(fromLeft.x, 500 - 20 - 50 - ToyApproach.gap)
        XCTAssertLessThan(fromLeft.x + petBounds.maxX, toy.x + toyBounds.minX + 0.001, "overlapping the toy")
    }

    func test_thePetApproachesFromWhicheverSideItIsAlreadyOn() {
        XCTAssertLessThan(approach(from: 100).x, toy.x, "came from the left, stays on the left")
        XCTAssertGreaterThan(approach(from: 900).x, toy.x, "came from the right, stays on the right")
    }

    func test_theTwoOutlinesNeverOverlap() {
        for petX in stride(from: CGFloat(0), through: 1000, by: 50) {
            let standing = approach(from: petX)
            let pet = petBounds.offsetBy(dx: standing.x, dy: 0)
            let toyRect = toyBounds.offsetBy(dx: toy.x, dy: 0)

            XCTAssertFalse(
                pet.intersects(toyRect),
                "the pet is standing on the toy when approaching from x=\(petX)"
            )
        }
    }

    /// Asymmetric artwork (which the real pet has) must still be handled by
    /// its actual edges rather than by an assumed half-width.
    func test_usesTheRealOutlineEdgesNotAnAssumedHalfWidth() {
        let leaning = CGRect(x: -10, y: -120, width: 100, height: 120) // 90 to the right, 10 to the left

        let fromLeft = ToyApproach.standingPosition(
            toyPosition: toy, toyBounds: toyBounds,
            petPosition: CGPoint(x: 0, y: floor), petBounds: leaning
        )

        XCTAssertEqual(fromLeft.x, 500 - 20 - 90 - ToyApproach.gap, "the far-sticking-out side is what matters")
    }

    /// A toy with no measured outline (the drawn-circle fallback before it
    /// loads) must not send the pet somewhere absurd.
    func test_azeroSizedToyStillGivesASaneSpot() {
        let standing = ToyApproach.standingPosition(
            toyPosition: toy, toyBounds: .zero,
            petPosition: CGPoint(x: 100, y: floor), petBounds: petBounds
        )

        XCTAssertEqual(standing.y, toy.y, "no outline, so its centre is all there is")
        XCTAssertLessThan(standing.x, toy.x)
    }
}
