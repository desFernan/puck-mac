//
//  ToyThumbnailTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Menu-bar thumbnails: the artwork's proportions have to survive.
//

import XCTest
@testable import Puck

final class ToyThumbnailTests: XCTestCase {
    func test_squareArtwork_fillsTheBox() {
        let size = ToyThumbnail.fittedSize(imagePixelSize: CGSize(width: 512, height: 512), boundingSide: 18)

        XCTAssertEqual(size, CGSize(width: 18, height: 18))
    }

    /// The wand is 310x804. Fitting that into a square box is what made the
    /// toy LAYER render as a sliver (see ToyCatalogue's header); the same
    /// mistake in a menu icon squashes it instead. Height leads, width follows.
    func test_tallArtwork_keepsItsProportions() {
        let size = ToyThumbnail.fittedSize(imagePixelSize: CGSize(width: 310, height: 804), boundingSide: 18)

        XCTAssertEqual(size.height, 18, accuracy: 0.001)
        XCTAssertEqual(size.width, 18 * 310 / 804, accuracy: 0.001)
        XCTAssertLessThan(size.width, size.height)
    }

    func test_wideArtwork_isBoundedByItsWidth() {
        let size = ToyThumbnail.fittedSize(imagePixelSize: CGSize(width: 800, height: 200), boundingSide: 18)

        XCTAssertEqual(size.width, 18, accuracy: 0.001)
        XCTAssertEqual(size.height, 4.5, accuracy: 0.001)
    }

    func test_degenerateArtwork_isRejectedRatherThanDividedByZero() {
        XCTAssertEqual(ToyThumbnail.fittedSize(imagePixelSize: .zero, boundingSide: 18), .zero)
        XCTAssertEqual(
            ToyThumbnail.fittedSize(imagePixelSize: CGSize(width: 10, height: 0), boundingSide: 18),
            .zero
        )
    }

    func test_missingArtwork_yieldsNoImageRatherThanABlankOne() {
        // A menu item with a blank 18pt gap where an icon should be reads as a
        // broken build; no image at all just reads as a plain text item.
        let absent = Toy(name: "no-such-toy", height: 44, play: .throwAndCatch)

        XCTAssertNil(ToyThumbnail.image(for: absent))
    }
}
