//
//  AlphaHitMaskTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Hit testing against what is actually drawn, not the box around it.
//

import XCTest
@testable import Puck

final class AlphaHitMaskTests: XCTestCase {
    /// An image with `opaque` filled solid and the rest transparent.
    /// `opaque` is in top-left coordinates, matching what the mask reports.
    private func image(size: CGSize, opaque: CGRect) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(
            x: opaque.minX,
            y: size.height - opaque.maxY,
            width: opaque.width,
            height: opaque.height
        ))
        return try XCTUnwrap(context.makeImage())
    }

    /// The case the whole thing exists for: a shape in the middle of a big
    /// transparent canvas. The corners are inside the image and inside its
    /// bounding box, and must still not count as hits.
    func test_transparentCanvasAroundTheArtworkIsNotAHit() throws {
        let mask = try XCTUnwrap(AlphaHitMask(image: image(
            size: CGSize(width: 200, height: 200),
            opaque: CGRect(x: 80, y: 80, width: 40, height: 40)
        )))

        XCTAssertTrue(mask.isDrawn(atUnit: CGPoint(x: 0.5, y: 0.5)), "the middle is drawn")
        for corner in [CGPoint(x: 0.05, y: 0.05), CGPoint(x: 0.95, y: 0.05),
                       CGPoint(x: 0.05, y: 0.95), CGPoint(x: 0.95, y: 0.95)] {
            XCTAssertFalse(mask.isDrawn(atUnit: corner), "empty canvas at \(corner) counted as a hit")
        }
    }

    /// Top-left origin, like every other coordinate in the app: a shape in
    /// the top half must read as being in the top half.
    func test_theMaskUsesATopLeftOrigin() throws {
        let mask = try XCTUnwrap(AlphaHitMask(image: image(
            size: CGSize(width: 100, height: 100),
            opaque: CGRect(x: 0, y: 0, width: 100, height: 20) // the TOP strip
        )))

        XCTAssertTrue(mask.isDrawn(atUnit: CGPoint(x: 0.5, y: 0.05)))
        XCTAssertFalse(mask.isDrawn(atUnit: CGPoint(x: 0.5, y: 0.95)))
    }

    func test_pointsOutsideTheImageAreNeverHits() throws {
        let mask = try XCTUnwrap(AlphaHitMask(image: image(
            size: CGSize(width: 64, height: 64),
            opaque: CGRect(x: 0, y: 0, width: 64, height: 64)
        )))

        XCTAssertFalse(mask.isDrawn(atUnit: CGPoint(x: -0.1, y: 0.5)))
        XCTAssertFalse(mask.isDrawn(atUnit: CGPoint(x: 1.5, y: 0.5)))
        XCTAssertFalse(mask.isDrawn(atUnit: CGPoint(x: 0.5, y: -0.2)))
    }

    /// Tolerance dilates the silhouette, so grabbing something small isn't a
    /// test of aim.
    func test_toleranceForgivesJustMissing() throws {
        let mask = try XCTUnwrap(AlphaHitMask(image: image(
            size: CGSize(width: 100, height: 100),
            opaque: CGRect(x: 40, y: 40, width: 20, height: 20)
        )))
        let justOutside = CGPoint(x: 0.34, y: 0.5)

        XCTAssertFalse(mask.isDrawn(atUnit: justOutside), "precondition: a clean miss")
        XCTAssertTrue(mask.isDrawn(atUnit: justOutside, tolerance: 0.1), "tolerance should forgive this")
    }

    func test_toleranceDoesNotForgiveAWideMiss() throws {
        let mask = try XCTUnwrap(AlphaHitMask(image: image(
            size: CGSize(width: 100, height: 100),
            opaque: CGRect(x: 40, y: 40, width: 20, height: 20)
        )))

        XCTAssertFalse(mask.isDrawn(atUnit: CGPoint(x: 0.02, y: 0.02), tolerance: 0.05))
    }

    /// A fully transparent image has nothing to click; callers fall back to
    /// their bounding box rather than getting a mask that always says no.
    func test_aFullyTransparentImageHasNoMask() throws {
        XCTAssertNil(AlphaHitMask(image: try image(size: CGSize(width: 32, height: 32), opaque: .zero)))
    }

    /// The mask is deliberately coarse -- it answers "did the user mean to
    /// click this", where a pixel either way is meaningless.
    func test_theMaskIsSampledCoarsely() throws {
        let mask = try XCTUnwrap(AlphaHitMask(image: image(
            size: CGSize(width: 1200, height: 1200),
            opaque: CGRect(x: 0, y: 0, width: 1200, height: 1200)
        )))

        XCTAssertLessThanOrEqual(mask.width, AlphaHitMask.resolution)
        XCTAssertLessThanOrEqual(mask.height, AlphaHitMask.resolution)
    }
}
