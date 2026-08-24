//
//  BallHeadCollisionTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  A ball falling near the character should hit its head instead of
//  passing straight through to the floor.
//

import XCTest
@testable import Puck

final class BallHeadCollisionTests: XCTestCase {
    private let characterPosition = CGPoint(x: 500, y: 800) // ground/feet point
    private let avatarSize = CGSize(width: 130, height: 140)

    func test_ballDirectlyAboveTheHead_landsAtHeadHeight() {
        let y = BallHeadCollision.landingY(ballX: 500, ballHalfWidth: 0, characterPosition: characterPosition, avatarSize: avatarSize)

        XCTAssertEqual(y, 800 - 140)
    }

    func test_ballWithinHalfTheAvatarWidth_stillHitsTheHead() {
        let y = BallHeadCollision.landingY(ballX: 500 + 64, ballHalfWidth: 0, characterPosition: characterPosition, avatarSize: avatarSize)

        XCTAssertEqual(y, 660)
    }

    func test_ballOutsideTheAvatarWidth_missesEntirely() {
        let y = BallHeadCollision.landingY(ballX: 500 + 200, ballHalfWidth: 0, characterPosition: characterPosition, avatarSize: avatarSize)

        XCTAssertNil(y)
    }

    func test_ballJustOutsideTheHalfWidth_misses() {
        let y = BallHeadCollision.landingY(ballX: 500 + 66, ballHalfWidth: 0, characterPosition: characterPosition, avatarSize: avatarSize)

        XCTAssertNil(y)
    }
}

/// A toy with real width bonks the head when it *overlaps* it, not only when
/// its middle is over it (the pumpkin is ~40pt wide).
final class BallHeadCollisionWidthTests: XCTestCase {
    private let pet = CGPoint(x: 500, y: 400)
    private let avatar = CGSize(width: 130, height: 133)

    private func landing(ballX: CGFloat, halfWidth: CGFloat) -> CGFloat? {
        BallHeadCollision.landingY(
            ballX: ballX,
            ballHalfWidth: halfWidth,
            characterPosition: pet,
            avatarSize: avatar
        )
    }

    /// Middle just past the head's edge, but half the toy still over it.
    func test_aToyGrazingTheHeadStillHitsIt() {
        XCTAssertNil(landing(ballX: 570, halfWidth: 0), "a point there misses, as it should")
        XCTAssertNotNil(landing(ballX: 570, halfWidth: 20), "but a 40pt-wide toy is visibly overlapping")
    }

    func test_aToyClearOfTheHeadStillMisses() {
        XCTAssertNil(landing(ballX: 600, halfWidth: 20), "35pt clear of the head's edge")
    }

    /// The boundary itself: edges exactly touching counts as a hit.
    func test_edgesExactlyTouchingCounts() {
        XCTAssertNotNil(landing(ballX: 500 + 65 + 20, halfWidth: 20))
        XCTAssertNil(landing(ballX: 500 + 65 + 20.01, halfWidth: 20))
    }

    func test_widthWorksOnBothSides() {
        XCTAssertNotNil(landing(ballX: 500 - 65 - 19, halfWidth: 20))
        XCTAssertNil(landing(ballX: 500 - 65 - 21, halfWidth: 20))
    }

    /// Where it lands is unchanged -- only whether it lands.
    func test_theLandingHeightIsStillTheTopOfTheAvatar() {
        XCTAssertEqual(landing(ballX: 500, halfWidth: 20), pet.y - avatar.height)
    }
}
