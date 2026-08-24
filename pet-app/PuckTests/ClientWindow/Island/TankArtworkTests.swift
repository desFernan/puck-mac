//
//  TankArtworkTests.swift
//  PuckTests
//
//  The picture the island is filled with. A missing resource is not a build
//  error -- the lookup returns nil and the island falls back to its plain
//  ground -- so it is checked here and in scripts/check-resources.sh for the
//  app bundles.
//

import XCTest
@testable import Puck

final class TankArtworkTests: XCTestCase {
    func test_theArtwork_isInTheBundle() {
        XCTAssertNotNil(TankArtwork.image())
    }

    /// Wide and shallow, because the island is a strip: an image anywhere
    /// near square would crop to a keyhole of itself at this height.
    func test_theArtwork_isWiderThanItIsTall() throws {
        let image = try XCTUnwrap(TankArtwork.image())

        XCTAssertGreaterThan(image.size.width, image.size.height * 2)
    }

    /// Asked for on every frame the island draws.
    func test_theArtwork_isCached() throws {
        let first = try XCTUnwrap(TankArtwork.image())
        let second = try XCTUnwrap(TankArtwork.image())

        XCTAssertTrue(first === second)
    }

    /// The island's layout divides by this.
    func test_aspect_isTheImagesProportions() throws {
        let image = try XCTUnwrap(TankArtwork.image())

        XCTAssertEqual(TankArtwork.aspect(image), image.size.width / image.size.height, accuracy: 0.0001)
    }

    func test_aspect_survivesAZeroHeightImage() {
        XCTAssertEqual(TankArtwork.aspect(NSImage(size: .zero)), 1)
    }
}
