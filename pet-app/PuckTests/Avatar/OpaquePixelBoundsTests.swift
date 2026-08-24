//
//  OpaquePixelBoundsTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Measuring where an avatar PNG's artwork actually is inside its canvas.
//

import XCTest
import AppKit
@testable import Puck

final class OpaquePixelBoundsTests: XCTestCase {
    /// An image of `size` that is fully transparent except for `opaque`,
    /// which is filled solid. `opaque` is given in top-left coordinates, the
    /// same convention the measurement returns.
    private func image(size: CGSize, opaque: CGRect) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
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

    func test_findsTheArtworkInsideATransparentCanvas() throws {
        let opaque = CGRect(x: 20, y: 40, width: 60, height: 80)
        let subject = try image(size: CGSize(width: 200, height: 200), opaque: opaque)

        let measured = try XCTUnwrap(OpaquePixelBounds.of(subject))

        XCTAssertEqual(measured, opaque)
    }

    func test_fullyOpaqueImageMeasuresTheWholeCanvas() throws {
        let size = CGSize(width: 64, height: 48)
        let subject = try image(size: size, opaque: CGRect(origin: .zero, size: size))

        let measured = try XCTUnwrap(OpaquePixelBounds.of(subject))

        XCTAssertEqual(measured, CGRect(origin: .zero, size: size))
    }

    /// A pet with no visible pixels has no outline to keep on screen; callers
    /// fall back to the layer box rather than to an empty rect.
    func test_fullyTransparentImageHasNoBounds() throws {
        let subject = try image(size: CGSize(width: 32, height: 32), opaque: .zero)

        XCTAssertNil(OpaquePixelBounds.of(subject))
    }

    /// Asymmetric padding is the whole reason this exists — the dummy avatar
    /// has empty canvas down one side only, and assuming symmetry would put
    /// the pet's edge in the wrong place.
    func test_measuresAsymmetricPadding() throws {
        let subject = try image(
            size: CGSize(width: 100, height: 100),
            opaque: CGRect(x: 0, y: 10, width: 40, height: 90)
        )

        let measured = try XCTUnwrap(OpaquePixelBounds.of(subject))

        XCTAssertEqual(measured.minX, 0, "artwork runs right up to the left edge")
        XCTAssertEqual(measured.maxX, 40)
    }

    // MARK: - Downsampling

    /// Sources far larger than the measuring resolution are scanned small and
    /// scaled back up — the scan is ~20x cheaper and the result still has to
    /// be accurate to well under a rendered point.
    func test_aLargeImageIsStillMeasuredAccurately() throws {
        let size = CGFloat(OpaquePixelBounds.measurementResolution) * 5
        let opaque = CGRect(x: size * 0.25, y: size * 0.1, width: size * 0.5, height: size * 0.8)
        let subject = try image(size: CGSize(width: size, height: size), opaque: opaque)

        let measured = try XCTUnwrap(OpaquePixelBounds.of(subject))

        // One measuring pixel covers `size / measurementResolution` source ones.
        let tolerance = size / CGFloat(OpaquePixelBounds.measurementResolution)
        XCTAssertEqual(measured.minX, opaque.minX, accuracy: tolerance)
        XCTAssertEqual(measured.minY, opaque.minY, accuracy: tolerance)
        XCTAssertEqual(measured.maxX, opaque.maxX, accuracy: tolerance)
        XCTAssertEqual(measured.maxY, opaque.maxY, accuracy: tolerance)
    }

    /// Rounding is outward on every side, so the measured box never cuts into
    /// artwork that the downscale merged into a partly-covered edge pixel.
    func test_downsamplingNeverUndercutsTheArtwork() throws {
        let size = CGFloat(OpaquePixelBounds.measurementResolution) * 4
        let opaque = CGRect(x: 101, y: 203, width: 307, height: 401) // deliberately not round
        let subject = try image(size: CGSize(width: size, height: size), opaque: opaque)

        let measured = try XCTUnwrap(OpaquePixelBounds.of(subject))

        XCTAssertLessThanOrEqual(measured.minX, opaque.minX)
        XCTAssertLessThanOrEqual(measured.minY, opaque.minY)
        XCTAssertGreaterThanOrEqual(measured.maxX, opaque.maxX)
        XCTAssertGreaterThanOrEqual(measured.maxY, opaque.maxY)
    }

    func test_smallImagesAreNotScaled() throws {
        let opaque = CGRect(x: 3, y: 4, width: 10, height: 12)
        let subject = try image(size: CGSize(width: 32, height: 32), opaque: opaque)

        let measured = try XCTUnwrap(OpaquePixelBounds.of(subject))

        XCTAssertEqual(measured, opaque, "no downscale, so no rounding either")
    }
}
