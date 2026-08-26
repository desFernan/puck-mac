//
//  PetTankTilingTests.swift
//  PuckTests
//
//  How the seabed is laid across the island.
//

import XCTest
@testable import Puck

final class PetTankHeightLimitTests: XCTestCase {
    /// The shipped seabed: 3596x447, eight points across for every point
    /// down. On a Retina display one point of island costs two pixels of
    /// picture, so 447 pixels is 223 points of island and no more.
    func test_theDragStopsWhereThePictureStopsBeingAbleToFillIt() {
        let limit = PetTankView.maximumHeight(artworkPixelHeight: 447, displayScale: 2)

        XCTAssertEqual(limit, 223.5, accuracy: 0.001)
        XCTAssertLessThan(limit, PetTankView.maximumIslandHeight, "the design ceiling was the bug")
    }

    /// Below that limit the picture is drawn smaller than it is, which is
    /// where it looks its best -- so nothing about the range people already
    /// use changes.
    func test_theIslandOpensAndSitsWellInsideTheLimit() {
        let limit = PetTankView.maximumHeight(artworkPixelHeight: 447, displayScale: 2)

        XCTAssertGreaterThan(limit, PetTankView.islandHeight)
        XCTAssertGreaterThan(limit, PetTankView.minimumIslandHeight)
    }

    /// A 1x display asks half as many pixels of the same picture, so the same
    /// artwork allows a taller island -- up to the design's own ceiling,
    /// which is where "a shelf, not a pane" takes over from sharpness.
    func test_aDisplayThatAsksForFewerPixelsGetsTheDesignsOwnCeiling() {
        XCTAssertEqual(
            PetTankView.maximumHeight(artworkPixelHeight: 447, displayScale: 1),
            PetTankView.maximumIslandHeight
        )
    }

    /// Somebody's own picture, dropped in the customisation folder. A taller
    /// one buys back the full range; a tiny one must still leave an island
    /// the pet fits in, magnified or not -- an island below the floor is
    /// refused outright, and a refusal looks like the pet ignoring the window.
    func test_aCustomPictureMovesTheLimitWithIt() {
        XCTAssertEqual(
            PetTankView.maximumHeight(artworkPixelHeight: 2000, displayScale: 2),
            PetTankView.maximumIslandHeight
        )
        XCTAssertEqual(
            PetTankView.maximumHeight(artworkPixelHeight: 40, displayScale: 2),
            PetTankView.minimumIslandHeight
        )
    }

    /// No picture at all: the island is its own plain ground, and there is
    /// nothing that could be blown up.
    func test_withNoPictureTheCeilingIsTheOnlyLimit() {
        XCTAssertEqual(
            PetTankView.maximumHeight(artworkPixelHeight: 0, displayScale: 2),
            PetTankView.maximumIslandHeight
        )
        XCTAssertEqual(
            PetTankView.maximumHeight(artworkPixelHeight: 447, displayScale: 0),
            PetTankView.maximumIslandHeight
        )
    }
}

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

    // MARK: - The folded band

    private func bandTiles(width: CGFloat) -> [CGRect] {
        PetTankView.bandTiles(
            across: CGSize(width: width, height: PetTankView.collapsedHeight),
            aspect: aspect
        )
    }

    /// The band shows the bottom of the scene -- the sand the pet stands on.
    /// The water above it hangs off the top and is clipped away.
    func testEveryCopySitsOnTheBandsFloorWithTheRestAbove() {
        for tile in bandTiles(width: 1600) {
            XCTAssertEqual(tile.maxY, PetTankView.collapsedHeight, accuracy: 0.0001)
            XCTAssertLessThan(tile.minY, 0, "the water above the sand is clipped, not squashed in")
        }
    }

    /// Cropped, never squashed: a copy keeps the picture's own proportions
    /// and the band takes a slice out of it.
    func testEveryCopyKeepsThePicturesAspect() {
        for tile in bandTiles(width: 1600) {
            XCTAssertEqual((tile.width - PetTankView.tileOverlap) / tile.height, aspect, accuracy: 0.0001)
        }
    }

    /// Only `bandCrop` of the picture's height is inside the band. This is
    /// what keeps the stones the size of stones: filling the width with one
    /// copy instead blows them up to the size of the pet.
    func testTheBandShowsOnlyItsCropOfThePicture() {
        let tile = bandTiles(width: 1600)[0]

        XCTAssertEqual(PetTankView.collapsedHeight / tile.height, PetTankView.bandCrop, accuracy: 0.0001)
    }

    /// No gap at either end, the same rule the island's own tiling follows.
    func testTheBandIsCoveredEndToEnd() {
        for width in stride(from: 200.0, through: 3000.0, by: 37.0) {
            let tiles = bandTiles(width: width)
            XCTAssertLessThanOrEqual(tiles.first!.minX, 0, "left edge uncovered at \(width)")
            XCTAssertGreaterThanOrEqual(tiles.last!.maxX, width, "right edge uncovered at \(width)")
        }
    }

    func testNothingToDrawInAnEmptyBand() {
        XCTAssertTrue(PetTankView.bandTiles(across: CGSize(width: 0, height: 28), aspect: aspect).isEmpty)
        XCTAssertTrue(PetTankView.bandTiles(across: CGSize(width: 800, height: 0), aspect: aspect).isEmpty)
    }
}
