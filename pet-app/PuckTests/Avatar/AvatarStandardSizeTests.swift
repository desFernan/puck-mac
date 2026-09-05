//
//  AvatarStandardSizeTests.swift
//  PuckTests
//
//  One size for every avatar, whatever its manifest claims.
//

import XCTest
@testable import Puck

final class AvatarStandardSizeTests: XCTestCase {
    /// The reported fault: how big the pet came out depended on numbers each
    /// package chose for itself, so two avatars stood a head apart on the
    /// same screen at the same setting. Two packages that declare very
    /// different hitboxes now draw at the same height.
    func testEveryAvatarIsTheSameHeight() {
        let bundled = AvatarStandardSize.size(hitbox: CGSize(width: 130, height: 133))
        let imported = AvatarStandardSize.size(hitbox: CGSize(width: 251, height: 300))

        XCTAssertEqual(bundled.height, imported.height)
        XCTAssertEqual(bundled.height, AvatarStandardSize.height)
    }

    /// The shape still comes from the manifest: a wide character stays wide
    /// and a narrow one stays narrow, they are just the same height.
    func testTheShapeStillComesFromTheManifest() {
        let wide = AvatarStandardSize.size(hitbox: CGSize(width: 200, height: 100))
        let narrow = AvatarStandardSize.size(hitbox: CGSize(width: 100, height: 200))

        XCTAssertEqual(wide.width / wide.height, 2, accuracy: 0.001)
        XCTAssertEqual(narrow.width / narrow.height, 0.5, accuracy: 0.001)
    }

    /// The size setting means the same thing for every avatar now, which is
    /// the other half of the point.
    func testScaleMultipliesTheStandard() {
        let half = AvatarStandardSize.size(hitbox: CGSize(width: 130, height: 133), scale: 0.5)
        let double = AvatarStandardSize.size(hitbox: CGSize(width: 251, height: 300), scale: 2)

        XCTAssertEqual(half.height, AvatarStandardSize.height * 0.5, accuracy: 0.001)
        XCTAssertEqual(double.height, AvatarStandardSize.height * 2, accuracy: 0.001)
    }

    /// A package claiming a 10:1 hitbox is a mistake or a joke, and must not
    /// become a banner across the desktop.
    func testAnAbsurdShapeIsCapped() {
        let banner = AvatarStandardSize.size(hitbox: CGSize(width: 2000, height: 100))

        XCTAssertEqual(
            banner.width / banner.height,
            AvatarStandardSize.maximumAspectRatio,
            accuracy: 0.001
        )
    }

    /// A hand-edited manifest with nothing usable in it still has to draw
    /// something, or the pet is invisible with no way to tell why.
    func testANonsenseHitboxStillDraws() {
        for hitbox in [CGSize(width: 0, height: 0), CGSize(width: -5, height: 200)] {
            let size = AvatarStandardSize.size(hitbox: hitbox)

            XCTAssertGreaterThan(size.width, 0, "\(hitbox)")
            XCTAssertGreaterThan(size.height, 0, "\(hitbox)")
        }
    }

    /// A size setting of zero would make the pet vanish with no way back.
    func testZeroScaleStillLeavesSomethingOnScreen() {
        let size = AvatarStandardSize.size(hitbox: CGSize(width: 130, height: 133), scale: 0)

        XCTAssertGreaterThan(size.height, 0)
    }

    /// The drawn height divides back to the scale that produced it.
    ///
    /// Not arithmetic for its own sake: going into its tank the pet remembers
    /// the scale it had on the desktop, and there is nowhere to read that from
    /// -- the size slider hands a scale straight in and nothing keeps it -- so
    /// AppDelegate+Tank derives it back out of the drawn size. It divided by
    /// the manifest's own hitbox height, which was the same thing until every
    /// avatar started being drawn at one standard height, and after that the
    /// pet came out of the tank at a size that had nothing to do with the one
    /// it went in at.
    func testTheDrawnHeightDividesBackToItsScale() {
        for hitbox in [CGSize(width: 130, height: 133), CGSize(width: 251, height: 300), CGSize(width: 400, height: 100)] {
            for scale in [0.1, 0.5, 1.0, 2.4] {
                let drawn = AvatarStandardSize.size(hitbox: hitbox, scale: CGFloat(scale))

                XCTAssertEqual(
                    Double(drawn.height / AvatarStandardSize.height),
                    scale,
                    accuracy: 0.0001,
                    "\(hitbox) at \(scale)"
                )
            }
        }
    }
}
