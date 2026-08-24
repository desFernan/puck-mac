//
//  PerchOnWindowTests.swift
//  Puck
//
//  What the pet does when the surface underfoot goes *behind* a window
//  rather than away: it falls, as it always did, and then goes up onto that
//  window's top edge instead of resting on top of the user's content
//  (2026-08-22).
//

import XCTest
import CoreGraphics
@testable import Puck

final class PerchOnWindowTests: XCTestCase {
    private func window(_ frame: CGRect, id: CGWindowID) -> WindowInfo {
        WindowInfo(windowID: id, ownerPID: 1, ownerName: nil, title: nil, layer: 0, frame: frame)
    }

    func test_coveringWindow_isTheFrontmostOneThePetsBodyLandsInside() {
        let front = window(CGRect(x: 0, y: 0, width: 500, height: 500), id: 1)
        let behind = window(CGRect(x: 0, y: 0, width: 800, height: 800), id: 2)

        XCTAssertEqual(
            WindowSupport.coveringWindow(standingAt: CGPoint(x: 100, y: 300), petHeight: 120, in: [front, behind])?.windowID,
            1
        )
        XCTAssertEqual(
            WindowSupport.coveringWindow(standingAt: CGPoint(x: 600, y: 700), petHeight: 120, in: [front, behind])?.windowID,
            2,
            "outside the front one, still inside the one behind it"
        )
        XCTAssertNil(
            WindowSupport.coveringWindow(standingAt: CGPoint(x: 900, y: 900), petHeight: 120, in: [front, behind])
        )
    }

    /// The measurement that made the fix miss: the chat window ends at y=939
    /// on a 956-tall screen, so a pet on the floor has its feet *below* it and
    /// everything else inside it -- sitting squarely on the message box.
    func test_coveringWindow_countsAPetWhoseFeetClearTheBottomEdge() {
        let chat = window(CGRect(x: 15, y: 39, width: 1440, height: 900), id: 9)

        XCTAssertNil(
            WindowSupport.coveringWindow(standingAt: CGPoint(x: 700, y: 950), petHeight: 0, in: [chat]),
            "feet alone are below the window"
        )
        XCTAssertEqual(
            WindowSupport.coveringWindow(standingAt: CGPoint(x: 700, y: 950), petHeight: 120, in: [chat])?.windowID,
            9
        )
    }

    func test_perchTarget_keepsThePetWhereItIs_whenTheWindowIsWideEnough() {
        let win = window(CGRect(x: 100, y: 300, width: 800, height: 600), id: 1)

        XCTAssertEqual(
            WindowSupport.perchTarget(on: win, from: CGPoint(x: 500, y: 900), roamableTop: 0, avatarHeight: 120, petHalfWidth: 50),
            CGPoint(x: 500, y: 300),
            "straight up onto the edge above where it landed"
        )
    }

    func test_perchTarget_pullsThePetInSoItsWholeBodyIsOverTheEdge() {
        let win = window(CGRect(x: 100, y: 300, width: 800, height: 600), id: 1)

        XCTAssertEqual(
            WindowSupport.perchTarget(on: win, from: CGPoint(x: 110, y: 900), roamableTop: 0, avatarHeight: 120, petHalfWidth: 50),
            CGPoint(x: 150, y: 300)
        )
        XCTAssertEqual(
            WindowSupport.perchTarget(on: win, from: CGPoint(x: 890, y: 900), roamableTop: 0, avatarHeight: 120, petHalfWidth: 50),
            CGPoint(x: 850, y: 300)
        )
    }

    /// The same headroom rule climbing uses: standing on the top edge of a
    /// near-fullscreen window would clip the pet off the top of the screen.
    func test_perchTarget_isNilWithoutRoomForThePetAboveTheEdge() {
        let tall = window(CGRect(x: 0, y: 40, width: 1000, height: 900), id: 1)

        XCTAssertNil(
            WindowSupport.perchTarget(on: tall, from: CGPoint(x: 500, y: 900), roamableTop: 0, avatarHeight: 120, petHalfWidth: 50)
        )
    }

    /// A window narrower than the pet has no edge worth standing on.
    func test_perchTarget_isNilWhenTheWindowIsNarrowerThanThePet() {
        let narrow = window(CGRect(x: 400, y: 300, width: 60, height: 400), id: 1)

        XCTAssertNil(
            WindowSupport.perchTarget(on: narrow, from: CGPoint(x: 430, y: 900), roamableTop: 0, avatarHeight: 120, petHalfWidth: 50)
        )
    }
}
