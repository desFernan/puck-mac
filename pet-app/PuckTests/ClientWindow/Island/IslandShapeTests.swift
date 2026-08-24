//
//  IslandShapeTests.swift
//  PuckTests
//
//  The island's outline, which has one job beyond looking like a panel: to
//  climb into the toolbar's empty band without ever reaching under the
//  buttons that live in it.
//

import SwiftUI
import XCTest

@testable import Puck

final class IslandShapeTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 120)

    /// Past the toolbar's last button, the island uses the whole band.
    func test_theShoulderClimbsToTheTopWhereThereIsRoom() {
        let path = IslandShape(cornerRadius: 14, rise: 26, shoulderStart: 300).path(in: bounds)
        XCTAssertEqual(path.boundingRect.minY, bounds.minY, accuracy: 0.5,
                       "the raised part reaches the top of its box, which is the toolbar's band")
    }

    /// Under the buttons it stays down. The left end of the island is what
    /// sits below them, and a shape that rose there would draw behind the
    /// toolbar rather than beside it.
    func test_theLeftEndStaysBelowTheToolbar() {
        let path = IslandShape(cornerRadius: 14, rise: 26, shoulderStart: 300).path(in: bounds)
        XCTAssertFalse(
            path.contains(CGPoint(x: 60, y: 6)),
            "the island's left end is not in the band the buttons are in"
        )
    }

    /// Nothing has measured the toolbar yet, or the buttons run the whole
    /// width: the island is the rectangle it was before the shoulder existed.
    func test_withNowhereToRiseItIsAPlainPanel() {
        let path = IslandShape(cornerRadius: 14, rise: 26, shoulderStart: .greatestFiniteMagnitude).path(in: bounds)
        XCTAssertEqual(path.boundingRect.minY, bounds.minY + 26, accuracy: 0.5,
                       "the top edge stays where a rectangle's would be")
    }

    /// A segment that begins to the right of the buttons -- the editor's
    /// always does -- has no reason to hold anything back.
    func test_aSegmentClearOfTheToolbarRisesAllTheWayAcross() {
        let path = IslandShape(cornerRadius: 14, rise: 26, shoulderStart: -400).path(in: bounds)
        XCTAssertTrue(
            path.contains(CGPoint(x: 60, y: 6)),
            "with the buttons behind it, the whole top edge is raised"
        )
    }

    /// The rise is clamped rather than trusted: a shoulder taller than the
    /// island would fold the outline inside out.
    func test_aRiseTallerThanTheIslandIsClamped() {
        let path = IslandShape(cornerRadius: 14, rise: 400, shoulderStart: 300).path(in: bounds)
        XCTAssertEqual(path.boundingRect.height, bounds.height, accuracy: 0.5)
        XCTAssertEqual(path.boundingRect.width, bounds.width, accuracy: 0.5)
    }

    /// The slider cannot make a pet that does not fit on the island it is
    /// standing on, nor one so small it cannot be seen. A pet the island
    /// cannot hold is refused by pet-app, which looks like the pet ignoring
    /// the window rather than like a size that was too big.
    func test_theSizeLimitsLeaveThePetOnTheIsland() {
        XCTAssertGreaterThan(PetTankView.minimumPetHeight, 0)
        XCTAssertLessThan(
            PetTankView.minimumPetHeight + PetTankView.petHeadroom,
            Double(PetTankView.minimumIslandHeight),
            "the smallest pet still fits on the shortest island the handle can make"
        )
        XCTAssertLessThanOrEqual(
            PetTankView.defaultPetHeight + PetTankView.petHeadroom,
            Double(PetTankView.islandHeight),
            "the pet fits the island both of them open at"
        )
    }

    /// A number read back from UserDefaults can be anything -- a hand-edited
    /// plist, a value from a version with different limits. NaN passes
    /// straight through min/max and into a SwiftUI frame, which is a window
    /// that will not draw.
    func test_aStoredHeightThatIsNotANumberFallsBackToTheFloor() {
        XCTAssertEqual(PetTankView.clamped(.nan, from: 84, to: 260), 84)
        XCTAssertEqual(PetTankView.clamped(.infinity, from: 84, to: 260), 84)
        XCTAssertEqual(PetTankView.clamped(-.infinity, from: 84, to: 260), 84)
    }

    func test_aStoredHeightOutsideTheLimitsIsBroughtBackInside() {
        XCTAssertEqual(PetTankView.clamped(10, from: 84, to: 260), 84)
        XCTAssertEqual(PetTankView.clamped(10_000, from: 84, to: 260), 260)
        XCTAssertEqual(PetTankView.clamped(120, from: 84, to: 260), 120)
    }
}
