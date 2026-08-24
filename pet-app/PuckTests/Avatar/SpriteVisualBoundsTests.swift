//
//  SpriteVisualBoundsTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Mapping an image's opaque pixels through .resizeAspect into the rectangle
//  the pet actually occupies on screen.
//

import XCTest
@testable import Puck

final class SpriteVisualBoundsTests: XCTestCase {
    /// The simple case: image and layer share an aspect ratio, so there's no
    /// letterboxing and the only correction is the artwork's own padding.
    func test_inLayer_scalesOpaquePixelsWhenAspectRatiosMatch() {
        let visible = SpriteVisualBounds.inLayer(
            opaquePixels: CGRect(x: 100, y: 200, width: 800, height: 600),
            imagePixelSize: CGSize(width: 1000, height: 1000),
            layerSize: CGSize(width: 100, height: 100)
        )

        XCTAssertEqual(visible, CGRect(x: 10, y: 20, width: 80, height: 60))
    }

    /// A fully opaque image fills its layer exactly.
    func test_inLayer_opaqueEverywhere_isTheWholeLayer() {
        let visible = SpriteVisualBounds.inLayer(
            opaquePixels: CGRect(x: 0, y: 0, width: 200, height: 200),
            imagePixelSize: CGSize(width: 200, height: 200),
            layerSize: CGSize(width: 130, height: 130)
        )

        XCTAssertEqual(visible, CGRect(x: 0, y: 0, width: 130, height: 130))
    }

    /// .resizeAspect fits without distorting, so a wide image in a square
    /// layer is centred with empty bands above and below. Ignoring that puts
    /// the pet's "edge" well outside anything drawn.
    func test_inLayer_letterboxesAWideImageInASquareLayer() {
        let visible = SpriteVisualBounds.inLayer(
            opaquePixels: CGRect(x: 0, y: 0, width: 200, height: 100),
            imagePixelSize: CGSize(width: 200, height: 100),
            layerSize: CGSize(width: 100, height: 100)
        )

        // Fits to width (scale 0.5), so it's 50 tall and centred: 25 down.
        XCTAssertEqual(visible, CGRect(x: 0, y: 25, width: 100, height: 50))
    }

    func test_inLayer_pillarboxesATallImageInASquareLayer() {
        let visible = SpriteVisualBounds.inLayer(
            opaquePixels: CGRect(x: 0, y: 0, width: 100, height: 200),
            imagePixelSize: CGSize(width: 100, height: 200),
            layerSize: CGSize(width: 100, height: 100)
        )

        XCTAssertEqual(visible, CGRect(x: 25, y: 0, width: 50, height: 100))
    }

    /// The FSM's position is the pet's ground point: bottom-centre of the
    /// layer. Y grows downward, so the artwork sits at negative Y from there.
    func test_relativeToGroundPoint_isCentredAboveTheFeet() {
        let relative = SpriteVisualBounds.relativeToGroundPoint(
            opaquePixels: CGRect(x: 0, y: 0, width: 100, height: 100),
            imagePixelSize: CGSize(width: 100, height: 100),
            layerSize: CGSize(width: 100, height: 100)
        )

        XCTAssertEqual(relative, CGRect(x: -50, y: -100, width: 100, height: 100))
    }

    /// Padding on one side only shifts the outline off-centre — which is the
    /// whole reason the outline is measured rather than assumed symmetric.
    func test_relativeToGroundPoint_offCentreArtworkGivesAnOffCentreOutline() {
        let relative = SpriteVisualBounds.relativeToGroundPoint(
            opaquePixels: CGRect(x: 50, y: 0, width: 50, height: 100),
            imagePixelSize: CGSize(width: 100, height: 100),
            layerSize: CGSize(width: 100, height: 100)
        )

        XCTAssertEqual(relative, CGRect(x: 0, y: -100, width: 50, height: 100))
    }

    func test_inLayer_zeroSizedImage_fallsBackToTheLayerBox() {
        let visible = SpriteVisualBounds.inLayer(
            opaquePixels: .zero,
            imagePixelSize: .zero,
            layerSize: CGSize(width: 130, height: 133)
        )

        XCTAssertEqual(visible, CGRect(x: 0, y: 0, width: 130, height: 133))
    }
}
