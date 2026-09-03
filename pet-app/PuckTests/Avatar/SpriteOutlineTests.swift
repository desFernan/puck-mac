//
//  SpriteOutlineTests.swift
//  PuckTests
//
//  The sticker edge: that it appears, that it follows the silhouette, and
//  that failing to draw it never loses the pet.
//

import CoreGraphics
import XCTest
@testable import Puck

final class SpriteOutlineTests: XCTestCase {
    /// A square of opaque red in the middle of a transparent image, which is
    /// the simplest thing with a silhouette to trace.
    private func blob(size: Int = 100, inset: Int = 30) -> CGImage {
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2))
        return context.makeImage()!
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (data[0], data[1], data[2], data[3])
    }

    /// The edge is grown outward, so the image has to get bigger on every
    /// side. Kept inside the original bounds it would be an edge eating the
    /// character rather than surrounding it.
    func testTheImageGrowsOnEverySide() {
        let source = blob()

        let outlined = SpriteOutline.outlined(source)

        let grew = Int(SpriteOutline.padding(for: source)) * 2
        XCTAssertEqual(outlined.width, source.width + grew)
        XCTAssertEqual(outlined.height, source.height + grew)
    }

    /// The reported fault: the outline was sliced flat across the top of the
    /// ears. The canvas was widened by the dilation's reach alone, but the
    /// blur after it reaches about three times its own radius further, and a
    /// sprite trimmed to its artwork touches its bounds on every side -- so
    /// the soft outer part of the edge was cropped away all round.
    func testThereIsRoomForTheSoftPartOfTheEdge() {
        let source = blob()

        XCTAssertGreaterThan(
            SpriteOutline.padding(for: source),
            SpriteOutline.thickness(for: source),
            "the blur reaches past the dilation and needs the room to do it"
        )
    }

    /// And the proof of it: a character that touches its own top edge must
    /// still get an edge above it that fades out rather than stopping dead.
    func testAnEdgeTouchingCharacterStillGetsAFullOutline() {
        // Opaque all the way to the top of the image, like a trimmed sprite.
        let context = CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 30, y: 30, width: 40, height: 70))
        let source = context.makeImage()!
        let room = Int(SpriteOutline.padding(for: source))

        let outlined = SpriteOutline.outlined(source)

        // Just above where the character's own top edge ended up.
        let justAbove = pixel(outlined, x: 50 + room, y: room - 1)
        XCTAssertGreaterThan(justAbove.a, 100, "the edge stops dead at the top")
        // And it has faded by the outer boundary rather than being cut.
        let atTheVeryTop = pixel(outlined, x: 50 + room, y: 0)
        XCTAssertLessThan(atTheVeryTop.a, justAbove.a, "the edge is cropped rather than fading out")
    }

    /// Thickness scales with the sprite, so a package drawn small and one
    /// drawn large get the same visual weight once both are shown at the
    /// standard size.
    func testThicknessFollowsTheSpriteSize() {
        let small = SpriteOutline.thickness(for: blob(size: 100))
        let large = SpriteOutline.thickness(for: blob(size: 400))

        XCTAssertGreaterThan(large, small)
        XCTAssertGreaterThanOrEqual(small, 1, "a sprite must never get a zero-width edge")
    }

    /// Just outside the character there should now be white, where there was
    /// nothing at all.
    func testThereIsWhiteWhereThereWasNothing() {
        let source = blob(size: 100, inset: 30)
        let room = Int(SpriteOutline.padding(for: source))

        let outlined = SpriteOutline.outlined(source)

        // One pixel outside the blob's left edge, in the outlined image's
        // coordinates (everything has shifted right by the padding).
        let sample = pixel(outlined, x: 30 + room - 1, y: 50 + room)
        XCTAssertGreaterThan(sample.a, 200, "nothing was drawn beside the character")
        XCTAssertGreaterThan(sample.r, 200)
        XCTAssertGreaterThan(sample.g, 200)
        XCTAssertGreaterThan(sample.b, 200)
    }

    /// The character itself is not painted over: an edge that covered the
    /// drawing would be a white blob.
    func testTheCharacterIsStillOnTop() {
        let source = blob(size: 100, inset: 30)
        let room = Int(SpriteOutline.padding(for: source))

        let outlined = SpriteOutline.outlined(source)

        let middle = pixel(outlined, x: 50 + room, y: 50 + room)
        XCTAssertGreaterThan(middle.r, 200)
        XCTAssertLessThan(middle.g, 60, "the red centre came back white")
        XCTAssertLessThan(middle.b, 60)
    }

    /// Far outside stays empty -- the edge is a rim, not a background.
    func testTheCornersStayEmpty() {
        let outlined = SpriteOutline.outlined(blob(size: 100, inset: 30))

        XCTAssertLessThan(pixel(outlined, x: 1, y: 1).a, 20)
    }
}
