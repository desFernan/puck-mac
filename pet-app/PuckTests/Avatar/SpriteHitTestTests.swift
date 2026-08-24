//
//  SpriteHitTestTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Unwinding a sprite's transform and .resizeAspect letterboxing to find
//  where a click landed inside the artwork.
//
//  Every one of these is a way the same click can end up somewhere different
//  in the picture: the pet mirrored while facing left, flipped hanging from a
//  ceiling, turned on its side climbing, a wand mid-spin, or letterboxed
//  because the art and the layer aren't the same shape.
//

import XCTest
@testable import Puck

final class SpriteHitTestTests: XCTestCase {
    private let square = CGSize(width: 100, height: 100)

    private func unit(
        _ point: CGPoint,
        transform: CGAffineTransform = .identity,
        layerSize: CGSize? = nil,
        imagePixelSize: CGSize? = nil
    ) -> CGPoint? {
        SpriteHitTest.unitPoint(
            forLayerPoint: point,
            transform: transform,
            layerSize: layerSize ?? square,
            imagePixelSize: imagePixelSize ?? square
        )
    }

    func test_theCentreOfTheLayerIsTheCentreOfTheArtwork() throws {
        let result = try XCTUnwrap(unit(CGPoint(x: 50, y: 50)))

        XCTAssertEqual(result.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.y, 0.5, accuracy: 0.001)
    }

    func test_cornersMapToCorners() throws {
        let topLeft = try XCTUnwrap(unit(CGPoint(x: 0, y: 0)))

        XCTAssertEqual(topLeft.x, 0, accuracy: 0.001)
        XCTAssertEqual(topLeft.y, 0, accuracy: 0.001)
    }

    func test_pointsOutsideTheLayerMiss() {
        XCTAssertNil(unit(CGPoint(x: -10, y: 50)))
        XCTAssertNil(unit(CGPoint(x: 50, y: 130)))
    }

    // MARK: - Transforms

    /// Facing left mirrors the sprite, so a click on the left of the screen
    /// is a click on the artwork's RIGHT half.
    func test_aMirroredSpriteMapsTheClickToTheOtherSide() throws {
        let mirrored = CGAffineTransform(scaleX: -1, y: 1)

        let left = try XCTUnwrap(unit(CGPoint(x: 20, y: 50), transform: mirrored))

        XCTAssertEqual(left.x, 0.8, accuracy: 0.001)
    }

    /// Hanging from a ceiling flips it vertically.
    func test_aVerticallyFlippedSpriteMapsTopToBottom() throws {
        let flipped = CGAffineTransform(scaleX: 1, y: -1)

        let top = try XCTUnwrap(unit(CGPoint(x: 50, y: 10), transform: flipped))

        XCTAssertEqual(top.y, 0.9, accuracy: 0.001)
    }

    /// Climbing turns the sprite 90 degrees; a click above the centre is then
    /// on one side of the artwork rather than its top.
    func test_aRotatedSpriteMapsAroundTheTurn() throws {
        let rotated = CGAffineTransform(rotationAngle: .pi / 2)

        let above = try XCTUnwrap(unit(CGPoint(x: 50, y: 20), transform: rotated))

        XCTAssertEqual(above.x, 0.2, accuracy: 0.001)
        XCTAssertEqual(above.y, 0.5, accuracy: 0.001)
    }

    /// A bounce squashed flat, or a flip caught exactly edge-on, has no
    /// inverse -- and nothing visible to click either.
    func test_aFlattenedSpriteCannotBeHit() {
        XCTAssertNil(unit(CGPoint(x: 50, y: 50), transform: CGAffineTransform(scaleX: 0, y: 1)))
    }

    // MARK: - Letterboxing

    /// A wide image in a square layer is drawn centred with dead bands above
    /// and below; clicks there are on nothing at all.
    func test_theLetterboxBandsAreNotPartOfTheArtwork() throws {
        let wide = CGSize(width: 200, height: 100) // fits to width, half the height

        XCTAssertNil(unit(CGPoint(x: 50, y: 5), imagePixelSize: wide), "the band above the picture")
        XCTAssertNil(unit(CGPoint(x: 50, y: 95), imagePixelSize: wide), "the band below it")

        let inside = try XCTUnwrap(unit(CGPoint(x: 50, y: 50), imagePixelSize: wide))
        XCTAssertEqual(inside.y, 0.5, accuracy: 0.001)
    }

    /// The wand's shape: tall art in a tall layer of the same proportions has
    /// no letterbox at all, so the mapping is direct.
    func test_matchingProportionsHaveNoLetterbox() throws {
        let tall = CGSize(width: 310, height: 804)
        let layer = CGSize(width: 31, height: 80.4)

        let quarter = try XCTUnwrap(unit(CGPoint(x: 7.75, y: 20.1), layerSize: layer, imagePixelSize: tall))

        XCTAssertEqual(quarter.x, 0.25, accuracy: 0.01)
        XCTAssertEqual(quarter.y, 0.25, accuracy: 0.01)
    }

    func test_degenerateSizesAreNotHits() {
        XCTAssertNil(unit(CGPoint(x: 0, y: 0), layerSize: .zero))
        XCTAssertNil(unit(CGPoint(x: 0, y: 0), imagePixelSize: .zero))
    }
}
