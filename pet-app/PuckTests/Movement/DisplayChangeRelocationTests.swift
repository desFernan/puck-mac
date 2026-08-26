//
//  DisplayChangeRelocationTests.swift
//  PuckTests
//
//  The display changed under the pet. It has to end up somewhere it can be
//  seen, in an area that matches the screen it is now on.
//

import XCTest
@testable import Puck

final class DisplayChangeRelocationTests: XCTestCase {
    /// The pet's outline: 40 wide, 80 tall, standing on its own feet.
    private let visualBounds = CGRect(x: -20, y: -80, width: 40, height: 80)
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    private func contained(_ position: CGPoint, in area: CGRect? = nil) -> CGPoint {
        DisplayChangeRelocation.contained(position, visualBounds: visualBounds, in: area ?? screen)
    }

    /// The reported bug. A 1080-tall display becomes a 900-tall one; the pet
    /// was standing on the old floor, which is now 180pt below anything drawn.
    func testAShorterScreenBringsThePetBackOntoIt() {
        let position = contained(CGPoint(x: 600, y: 1080))

        XCTAssertEqual(position.y, 900, "the pet stands on the new floor")
        XCTAssertEqual(position.x, 600, "and keeps the place it had")
    }

    /// A narrower screen: the pet was near the old right edge, which is past
    /// the new one, and half of it would hang off.
    func testANarrowerScreenPullsThePetInByItsOwnOutline() {
        let position = contained(CGPoint(x: 1900, y: 900))

        XCTAssertEqual(position.x, 1420, "the pet's right edge, not its feet, is what stops at 1440")
        XCTAssertEqual(position.y, 900)
    }

    /// Nothing to do: a pet already inside the new screen stays exactly where
    /// it is. A display change is not a reason to move it.
    func testAPetAlreadyOnScreenIsLeftAlone() {
        XCTAssertEqual(contained(CGPoint(x: 700, y: 500)), CGPoint(x: 700, y: 500))
    }

    /// Above the top edge is as wrong as below the bottom one: the head goes
    /// no higher than the ceiling.
    func testAPetAboveTheAreaComesDownToWhereItsHeadFits() {
        let position = contained(CGPoint(x: 700, y: 10))

        XCTAssertEqual(position.y, 80, "feet an avatar's height below the top edge")
    }

    /// An area shorter than the pet: there is nowhere it fits, and standing
    /// on the floor with its head out is better than hanging below it.
    func testAnAreaShorterThanThePetPutsItOnTheFloor() {
        let shelf = CGRect(x: 200, y: 40, width: 800, height: 50)

        XCTAssertEqual(contained(CGPoint(x: 600, y: 400), in: shelf).y, shelf.maxY)
    }

    // MARK: - Standing on the new surface

    private func standing(
        _ position: CGPoint,
        in area: CGRect? = nil,
        onSurfaceUnder surfaceY: @escaping (CGPoint) -> CGFloat
    ) -> CGPoint {
        DisplayChangeRelocation.standing(
            position,
            visualBounds: visualBounds,
            in: area ?? screen,
            onSurfaceUnder: surfaceY
        )
    }

    /// The reported bug, the other way round from the one containment was
    /// written for. A 900-tall display becomes a 1080-tall one; the pet is
    /// inside the new area the moment it grows, so containment leaves it
    /// exactly where it was -- standing on a line 180pt above the floor with
    /// nothing under it.
    func testATallerScreenPutsThePetDownOnTheNewFloor() {
        let taller = CGRect(x: 0, y: 0, width: 1440, height: 1080)

        let position = standing(CGPoint(x: 600, y: 900), in: taller) { _ in taller.maxY }

        XCTAssertEqual(position.y, 1080, "the pet stands on the new floor, not the old one")
        XCTAssertEqual(position.x, 600, "and keeps the place it had")
    }

    /// The surface, not the area's floor: what a pet stands on is a window
    /// top as often as it is the bottom of the screen, and a display change
    /// re-measures both.
    func testThePetComesDownOnAWindowTopRatherThanThroughIt() {
        let taller = CGRect(x: 0, y: 0, width: 1440, height: 1080)

        let position = standing(CGPoint(x: 600, y: 900), in: taller) { _ in 1000 }

        XCTAssertEqual(position.y, 1000)
    }

    /// A shorter screen still works the way it did: containment brings the
    /// pet up onto the new floor, and the surface is asked about the position
    /// it was brought to rather than the one it had off-screen.
    func testAShorterScreenAsksAboutTheContainedPosition() {
        var asked: CGPoint?
        let position = standing(CGPoint(x: 1900, y: 1080)) { point in
            asked = point
            return point.y
        }

        XCTAssertEqual(asked, CGPoint(x: 1420, y: 900))
        XCTAssertEqual(position, CGPoint(x: 1420, y: 900))
    }
}
