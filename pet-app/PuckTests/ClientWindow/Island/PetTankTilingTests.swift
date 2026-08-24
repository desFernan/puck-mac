//
//  PetTankTilingTests.swift
//  PuckTests
//
//  How the seabed is laid across the island.
//

import XCTest
@testable import Puck

final class PetTankTilingTests: XCTestCase {
    /// A 6:1 picture in a 90pt-tall island is 540pt per copy.
    private let aspect: CGFloat = 6

    func testOneCopyCoversAnIslandNarrowerThanThePicture() {
        let tiles = PetTankView.tiles(across: CGSize(width: 400, height: 90), aspect: aspect)

        XCTAssertEqual(tiles.count, 1)
        XCTAssertEqual(tiles[0].height, 90)
    }

    /// Every copy is the same width, and the run is centred: an island 1.3
    /// copies wide shows the middle of the scene, not its left end.
    func testTheRunIsCentredSoBothEndsAreTrimmedEqually() {
        let size = CGSize(width: 700, height: 90)
        let tiles = PetTankView.tiles(across: size, aspect: aspect)

        XCTAssertEqual(tiles.count, 2)
        let overhangLeft = -tiles[0].minX
        let overhangRight = (tiles[1].maxX - PetTankView.tileOverlap) - size.width
        XCTAssertEqual(overhangLeft, overhangRight, accuracy: 0.001)
    }

    /// The island is covered edge to edge whatever its width -- a gap at
    /// either end would show the window's ground through the picture.
    func testEveryWidthIsCoveredEndToEnd() {
        for width in stride(from: 200.0, through: 3000.0, by: 37.0) {
            let tiles = PetTankView.tiles(across: CGSize(width: width, height: 90), aspect: aspect)
            XCTAssertLessThanOrEqual(tiles.first!.minX, 0, "left edge uncovered at \(width)")
            XCTAssertGreaterThanOrEqual(tiles.last!.maxX, width, "right edge uncovered at \(width)")
        }
    }

    /// Copies overlap rather than merely touching: two rectangles sharing an
    /// edge are antialiased separately, and the join shows as a pale line.
    func testCopiesOverlapSoTheJoinDoesNotShow() {
        let tiles = PetTankView.tiles(across: CGSize(width: 1600, height: 90), aspect: aspect)

        XCTAssertGreaterThan(tiles.count, 1)
        for (left, right) in zip(tiles, tiles.dropFirst()) {
            XCTAssertGreaterThan(left.maxX, right.minX, "copies must overlap, not merely meet")
        }
    }

    /// A zero-sized island is one that is not on screen; nothing to draw is
    /// an answer, and a divide by its height is not.
    func testNothingToDrawInAnEmptyIsland() {
        XCTAssertTrue(PetTankView.tiles(across: CGSize(width: 0, height: 90), aspect: aspect).isEmpty)
        XCTAssertTrue(PetTankView.tiles(across: CGSize(width: 800, height: 0), aspect: aspect).isEmpty)
    }
}
