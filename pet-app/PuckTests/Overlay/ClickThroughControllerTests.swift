//
//  ClickThroughControllerTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  The head region used for petting.
//
//  Clicking the pet is no longer a rectangle at all -- it is measured against
//  the artwork's silhouette (AlphaHitMask), so the padded-AABB tests that
//  used to live here went with `shouldAllowClicks`. Petting deliberately
//  stays a rectangle: it asks "is the cursor over the pet's head?", which is
//  a region of the body rather than a set of drawn pixels, and stroking the
//  air just above the hair should still count.
//
//  `characterScreenPosition` is the character's ground/feet point -- the same
//  convention CharacterBody.position uses everywhere -- in AppKit *global*
//  space (bottom-left origin, Y increasing upward), so the body extends
//  upward from it and the head is the top slice.
//

import XCTest
import CoreGraphics
@testable import Puck

final class ClickThroughHeadRectTests: XCTestCase {
    private let ground = CGPoint(x: 500, y: 200)
    private let hitbox = CGSize(width: 130, height: 133)

    private func head(isUpsideDown: Bool = false) -> CGRect {
        ClickThroughController.headRect(
            characterScreenPosition: ground,
            hitboxSize: hitbox,
            isUpsideDown: isUpsideDown
        )
    }

    func test_theHeadIsTheTopSliceOfTheBody() {
        let rect = head()

        XCTAssertEqual(rect.maxY, ground.y + hitbox.height, accuracy: 0.001, "should reach the top of the head")
        XCTAssertEqual(rect.height, hitbox.height * ClickThroughController.headFraction, accuracy: 0.001)
        XCTAssertGreaterThan(rect.minY, ground.y, "must not reach down to the feet")
    }

    func test_theHeadSpansTheBodysFullWidth() {
        let rect = head()

        XCTAssertEqual(rect.minX, ground.x - hitbox.width / 2, accuracy: 0.001)
        XCTAssertEqual(rect.width, hitbox.width, accuracy: 0.001)
    }

    /// Hanging from a ceiling the body extends downward, so the head is the
    /// bottom slice -- the same flip SpriteAvatar applies when drawing it.
    func test_upsideDownTheHeadIsTheBottomSlice() {
        let rect = head(isUpsideDown: true)

        XCTAssertEqual(rect.minY, ground.y - hitbox.height, accuracy: 0.001)
        XCTAssertLessThan(rect.maxY, ground.y, "must not reach up to the feet")
    }

    func test_thePetsFeetAreNotItsHead() {
        XCTAssertFalse(head().contains(ground), "stroking the feet is not petting")
    }

    /// An avatar that hasn't loaded has no head to stroke -- an empty rect
    /// rather than a degenerate one somewhere at the origin.
    func test_aZeroSizedAvatarHasNoHead() {
        let rect = ClickThroughController.headRect(characterScreenPosition: ground, hitboxSize: .zero)

        XCTAssertEqual(rect, .zero)
    }
}
