//
//  DummyAvatarGrabbableTests.swift
//  PuckTests
//
//  Whether the committed dummy pack can actually be grabbed.
//
//  The pack is generated art rather than a drawing somebody framed by eye, so
//  how much of its canvas the character fills is a property of the generator
//  and can regress silently: the pet still appears, still animates, still
//  walks, and is simply too small and too far from where the click lands to
//  pick up. Nothing else in the suite would notice.
//
//  These ask the same two questions the runtime asks, of the same pieces --
//  the alpha mask and the layer-to-artwork mapping -- against the real PNG and
//  the real manifest.
//

import CoreGraphics
import ImageIO
import XCTest
@testable import Puck

final class DummyAvatarGrabbableTests: XCTestCase {
    private var packageDirectory: URL {
        RepositorySources.url("Resources/Avatars/dummy")
    }

    private func manifest() throws -> AvatarManifest {
        let data = try Data(contentsOf: packageDirectory.appendingPathComponent("manifest.json"))
        return try AvatarLoader.load(manifestData: data).manifest
    }

    private func image(_ stem: String) throws -> CGImage {
        let url = packageDirectory.appendingPathComponent("\(stem).png")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), "no \(stem).png")
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// The clip the pet spends most of its time in, which is also the one a
    /// user reaches for.
    private func idleStem() throws -> String {
        let manifest = try manifest()
        guard case .name(let stem)? = manifest.clips["idle"] else {
            return try XCTUnwrap(nil as String?, "the manifest has no idle clip")
        }
        return stem
    }

    /// How much of the canvas the character actually occupies.
    ///
    /// The app fits the whole PNG into a layer sized from the manifest hitbox,
    /// so this fraction *is* the pet's size on screen and the size of what can
    /// be clicked. The pack this replaced filled 96%; a generated one that
    /// measured its scale over thrown sweat drops and gusts of wind filled
    /// 58%, which put the pet at a third of the area and made it hard to grab.
    func test_theCharacterFillsMostOfItsCanvas() throws {
        let image = try image(try idleStem())
        let opaque = try XCTUnwrap(OpaquePixelBounds.of(image), "the idle clip is blank")

        let widthFraction = opaque.width / CGFloat(image.width)
        let heightFraction = opaque.height / CGFloat(image.height)

        XCTAssertGreaterThan(widthFraction, 0.7, "the character is small in its own canvas")
        XCTAssertGreaterThan(heightFraction, 0.7, "the character is short in its own canvas")
    }

    /// The middle of the drawn character has to answer "yes, that is me" to
    /// the same mapping the runtime uses -- layer point through the aspect fit
    /// into the artwork, then the alpha mask.
    func test_theMiddleOfThePetIsAHit() throws {
        let manifest = try manifest()
        let image = try image(try idleStem())
        let mask = try XCTUnwrap(AlphaHitMask(image: image), "the idle clip has no drawn pixels")
        let opaque = try XCTUnwrap(OpaquePixelBounds.of(image))

        let layerSize = CGSize(
            width: manifest.hitbox.width * manifest.scale,
            height: manifest.hitbox.height * manifest.scale
        )
        let imageSize = CGSize(width: image.width, height: image.height)

        // The artwork's own middle, as a fraction of the image.
        let middle = CGPoint(x: opaque.midX / imageSize.width, y: opaque.midY / imageSize.height)

        // Back out to the layer point that lands there, the way
        // SpriteHitTest.unitPoint maps it forward.
        let fit = min(layerSize.width / imageSize.width, layerSize.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * fit, height: imageSize.height * fit)
        let layerPoint = CGPoint(
            x: middle.x * drawn.width - drawn.width / 2 + layerSize.width / 2,
            y: middle.y * drawn.height - drawn.height / 2 + layerSize.height / 2
        )

        let unit = try XCTUnwrap(
            SpriteHitTest.unitPoint(
                forLayerPoint: layerPoint,
                transform: .identity,
                layerSize: layerSize,
                imagePixelSize: imageSize
            ),
            "the middle of the artwork fell outside the layer"
        )

        XCTAssertTrue(mask.isDrawn(atUnit: unit), "the middle of the pet is not clickable")
    }

    /// And it has to be a target worth aiming at. 130pt was what the previous
    /// pack came out at; anything much under that is a pet people miss.
    func test_theDrawnPetIsBigEnoughToAimAt() throws {
        let manifest = try manifest()
        let image = try image(try idleStem())
        let opaque = try XCTUnwrap(OpaquePixelBounds.of(image))

        let layerSize = CGSize(
            width: manifest.hitbox.width * manifest.scale,
            height: manifest.hitbox.height * manifest.scale
        )
        let fit = min(layerSize.width / CGFloat(image.width), layerSize.height / CGFloat(image.height))

        XCTAssertGreaterThan(opaque.width * fit, 100, "the pet is narrow on screen")
        XCTAssertGreaterThan(opaque.height * fit, 100, "the pet is short on screen")
    }
}
