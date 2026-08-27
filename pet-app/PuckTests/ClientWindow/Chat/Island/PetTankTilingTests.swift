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

    // MARK: - The folded band's water

    private let band = CGSize(width: 1200, height: PetTankView.collapsedHeight)

    /// Redrawn on every frame a pet walks across it, so anything placed by
    /// chance would shimmer. Two calls, the same answer.
    func testTheWaterIsDrawnTheSameWayEveryFrame() {
        XCTAssertEqual(PetTankView.bubbles(across: band), PetTankView.bubbles(across: band))
        XCTAssertEqual(PetTankView.rays(across: band), PetTankView.rays(across: band))
    }

    /// A wider window gets more light coming through it, not wider shafts.
    func testAWiderBandGetsMoreRaysRatherThanBiggerOnes() {
        let narrow = PetTankView.rays(across: CGSize(width: 400, height: band.height))
        let wide = PetTankView.rays(across: CGSize(width: 1600, height: band.height))

        XCTAssertGreaterThan(wide.count, narrow.count)
        XCTAssertEqual(
            wide[0].path.boundingRect.width,
            narrow[0].path.boundingRect.width,
            accuracy: 0.0001
        )
    }

    /// Bubbles rise through the water above the pet, not across its own line.
    func testBubblesStayOffThePetsLine() {
        for bubble in PetTankView.bubbles(across: band) {
            XCTAssertGreaterThanOrEqual(bubble.minY, 0)
            XCTAssertLessThan(bubble.maxY, band.height * 0.75, "a bubble is not something the pet walks into")
        }
    }

    /// A band that is not on screen has nothing to draw, and neither ray nor
    /// bubble may divide by its width.
    func testNothingToDrawInAnEmptyBand() {
        let empty = CGSize(width: 0, height: PetTankView.collapsedHeight)
        XCTAssertTrue(PetTankView.rays(across: empty).isEmpty)
        XCTAssertTrue(PetTankView.bubbles(across: empty).isEmpty)
        XCTAssertTrue(PetTankView.rays(across: CGSize(width: 800, height: 0)).isEmpty)
        XCTAssertTrue(PetTankView.bubbles(across: CGSize(width: 800, height: 0)).isEmpty)
    }
}
