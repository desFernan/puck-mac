//
//  ScreenGroundTests.swift
//  Puck
//
//  Two displays, without a second monitor to plug in.
//
//  The arrangement used throughout: a 1920x1080 primary, and a 1280x1024
//  display to its right whose bottom edge is 56pt higher. Every coordinate is
//  the pet's own space -- top-left origin, Y down -- so "higher" is a smaller
//  maxY, and the space below the second display's floor belongs to no screen
//  at all. That empty step is what every one of these tests is about.
//

import XCTest
@testable import Puck

final class ScreenGroundTests: XCTestCase {
    private let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let taller = CGRect(x: 1920, y: 0, width: 1280, height: 1024)
    private var displays: [CGRect] { [primary, taller] }
    /// A pet 100 wide standing on its feet, as elsewhere in the suite.
    private let pet = CGRect(x: -50, y: -120, width: 100, height: 120)

    func test_union_isTheBoxAroundEveryDisplay() {
        XCTAssertEqual(ScreenGround.union(displays), CGRect(x: 0, y: 0, width: 3200, height: 1080))
    }

    func test_union_ofNothing_isZeroRatherThanTheNullRect() {
        XCTAssertEqual(ScreenGround.union([]), .zero)
    }

    func test_theBoxContainsPointsThatAreOnNoDisplayAtAll() {
        // Bottom-right corner of the box: past the shorter display's floor.
        let void = CGPoint(x: 2500, y: 1070)
        XCTAssertTrue(ScreenGround.union(displays).contains(void))
        XCTAssertFalse(ScreenGround.hasGround(under: void, in: displays))
    }

    func test_hasGround_isTrueAboveADisplay() {
        XCTAssertTrue(ScreenGround.hasGround(under: CGPoint(x: 2500, y: 400), in: displays))
    }

    func test_hasGround_looksDownOnly_soAThrownPetIsStillOnItsScreen() {
        XCTAssertTrue(ScreenGround.hasGround(under: CGPoint(x: 900, y: -400), in: displays))
    }

    func test_artworkHasGround_isFalseWithHalfThePetOverTheStep() {
        // Feet on the taller display, right side of the drawing past its edge
        // -- and past its edge is 56pt of nothing.
        let atTheEdge = CGPoint(x: taller.maxX - 10, y: taller.maxY)
        XCTAssertTrue(ScreenGround.hasGround(under: atTheEdge, in: displays))
        XCTAssertFalse(ScreenGround.artworkHasGround(at: atTheEdge, visualBounds: pet, in: displays))
    }

    func test_area_isTheDisplayThePetStandsOn_notTheBox() {
        // A standing pet's feet are exactly on maxY, which CGRect.contains
        // excludes -- the nearest-area answer has to be the same display.
        XCTAssertEqual(ScreenGround.area(at: CGPoint(x: 2500, y: taller.maxY), in: displays), taller)
        XCTAssertEqual(ScreenGround.area(at: CGPoint(x: 900, y: primary.maxY), in: displays), primary)
    }

    func test_area_ofAPointOnNoDisplay_isTheNearestOne() {
        XCTAssertEqual(ScreenGround.area(at: CGPoint(x: 2500, y: 1075), in: displays), taller)
    }

    func test_standable_bringsAPetInTheVoidBackOntoTheNearestDisplay() {
        let stranded = CGPoint(x: 2500, y: 1075)
        let rescued = ScreenGround.standable(stranded, visualBounds: pet, in: displays)
        XCTAssertEqual(rescued.y, taller.maxY)
        XCTAssertTrue(ScreenGround.artworkHasGround(at: rescued, visualBounds: pet, in: displays))
    }

    func test_standable_pushesTheWholeDrawingOnScreen_notJustTheFeet() {
        // Feet just inside the taller display, most of the drawing past it.
        let overhanging = CGPoint(x: taller.maxX - 5, y: taller.maxY)
        let rescued = ScreenGround.standable(overhanging, visualBounds: pet, in: displays)
        XCTAssertEqual(rescued.x, taller.maxX - 50)
    }

    func test_ledge_isTheHigherFloorAhead() {
        let onThePrimary = CGPoint(x: primary.maxX - 20, y: primary.maxY)
        let ledge = ScreenGround.ledge(beyond: onThePrimary, directionX: 1, visualBounds: pet, in: displays)
        XCTAssertEqual(ledge?.y, taller.maxY)
        // Far enough in that the whole drawing lands on the taller display.
        XCTAssertEqual(ledge?.x, taller.minX + 50)
    }

    func test_ledge_isNilWhenTheDisplayAheadIsNotHigher() {
        let level = [primary, CGRect(x: 1920, y: 0, width: 1280, height: 1080)]
        let onThePrimary = CGPoint(x: primary.maxX - 20, y: primary.maxY)
        XCTAssertNil(ScreenGround.ledge(beyond: onThePrimary, directionX: 1, visualBounds: pet, in: level))
    }

    func test_ledge_isNilAtTheEndOfTheWorld() {
        let onTheTaller = CGPoint(x: taller.maxX - 20, y: taller.maxY)
        XCTAssertNil(ScreenGround.ledge(beyond: onTheTaller, directionX: 1, visualBounds: pet, in: displays))
    }

    func test_ledge_looksOnlyInTheDirectionOfTravel() {
        let onThePrimary = CGPoint(x: primary.maxX - 20, y: primary.maxY)
        XCTAssertNil(ScreenGround.ledge(beyond: onThePrimary, directionX: -1, visualBounds: pet, in: displays))
    }

    /// A single display keeps every answer it had before there was a list.
    func test_oneDisplay_hasGroundEverywhereInsideItself() {
        XCTAssertTrue(ScreenGround.artworkHasGround(at: CGPoint(x: 960, y: 1080), visualBounds: pet, in: [primary]))
        XCTAssertEqual(ScreenGround.area(at: CGPoint(x: 960, y: 1080), in: [primary]), primary)
        XCTAssertNil(ScreenGround.ledge(beyond: CGPoint(x: 960, y: 1080), directionX: 1, visualBounds: pet, in: [primary]))
    }
}
