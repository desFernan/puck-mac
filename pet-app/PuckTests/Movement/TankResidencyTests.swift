//
//  TankResidencyTests.swift
//  PuckTests
//
//  How big the pet is while it is in the tank.
//
//  The height a person asks for is not always the height they get, and the
//  failure mode of getting that wrong is silent: pet-app refuses a tank the
//  pet does not fit in, and from outside that looks like the pet ignoring the
//  window rather than like a size being wrong.
//

import XCTest
@testable import Puck

final class TankResidencyTests: XCTestCase {
    /// A 130x133 pet, which is the bundled avatar's shape.
    private let pet = CGSize(width: 130, height: 133)

    private func tank(_ size: CGSize?, petHeight: CGFloat = TankResidency.defaultPetHeight) -> TankResidency {
        var residency = TankResidency()
        residency.lastReportedSize = size
        residency.petHeight = petHeight
        return residency
    }

    /// A tank with room gives the height that was asked for.
    func test_aTankWithRoomGivesTheHeightAsked() {
        let scale = tank(CGSize(width: 900, height: 90)).scale(forPetOfSize: pet)

        XCTAssertEqual(CGFloat(scale) * pet.height, TankResidency.defaultPetHeight, accuracy: 0.0001)
    }

    /// The width is what usually binds: a tank has to be two pets across
    /// before it is worth standing in, so a narrow window's island sizes the
    /// pet down rather than being refused.
    func test_aNarrowTankSizesThePetDownRatherThanBeingRefused() {
        let narrow = tank(CGSize(width: 120, height: 90)).scale(forPetOfSize: pet)
        let wide = tank(CGSize(width: 900, height: 90)).scale(forPetOfSize: pet)

        XCTAssertLessThan(narrow, wide)
        XCTAssertGreaterThan(narrow, 0, "sized down, not refused")
        XCTAssertLessThanOrEqual(
            CGFloat(narrow) * pet.width * PetTankArea.minimumWidthInPets,
            120.0001,
            "two of the pet at this scale must still fit across"
        )
    }

    /// A tank shorter than the height asked for gives the height it has.
    func test_aShortTankGivesTheHeightItHas() {
        let scale = tank(CGSize(width: 900, height: 40)).scale(forPetOfSize: pet)

        XCTAssertEqual(CGFloat(scale) * pet.height, 40, accuracy: 0.0001)
    }

    /// Before the client has reported anything there is nothing to fit to,
    /// so the height asked for is the answer.
    func test_beforeAnyReportTheHeightAskedForIsTheAnswer() {
        let scale = tank(nil, petHeight: 50).scale(forPetOfSize: pet)

        XCTAssertEqual(CGFloat(scale) * pet.height, 50, accuracy: 0.0001)
    }

    /// No avatar yet -- which happens before one is installed and never while
    /// a move is running. A division by its height is not an answer.
    func test_noAvatarYetIsFullSizeRatherThanADivideByZero() {
        XCTAssertEqual(tank(CGSize(width: 900, height: 90)).scale(forPetOfSize: .zero), 1)
    }

    /// The island's lever moves this, and the pet has to follow it.
    func test_theLeverChangesTheAnswer() {
        let small = tank(CGSize(width: 900, height: 200), petHeight: 40).scale(forPetOfSize: pet)
        let large = tank(CGSize(width: 900, height: 200), petHeight: 120).scale(forPetOfSize: pet)

        XCTAssertLessThan(small, large)
    }
}
