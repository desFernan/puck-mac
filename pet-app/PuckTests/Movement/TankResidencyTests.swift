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

    /// The height the pet is actually *drawn* at, which is the app's
    /// standard times this scale -- not the manifest's own numbers times it.
    /// Asserting the latter is what let the two part company: the renderer
    /// moved to a standard height, this kept answering in the package's
    /// units, and the pet swam around a fraction of the size the island had
    /// made room for while every test here passed.
    private func drawnHeight(_ scale: Double) -> CGFloat {
        AvatarStandardSize.size(hitbox: pet, scale: CGFloat(scale)).height
    }

    private func drawnWidth(_ scale: Double) -> CGFloat {
        AvatarStandardSize.size(hitbox: pet, scale: CGFloat(scale)).width
    }

    /// A tank with room gives the height that was asked for. "With room"
    /// means taller than the ask -- a tank shorter than it is testing the
    /// cap, which is the test below.
    func test_aTankWithRoomGivesTheHeightAsked() {
        let roomy = CGSize(width: 2000, height: TankResidency.defaultPetHeight + 50)
        let scale = tank(roomy).scale(forPetOfSize: pet)

        XCTAssertEqual(drawnHeight(scale), TankResidency.defaultPetHeight, accuracy: 0.0001)
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
            drawnWidth(narrow) * PetTankArea.minimumWidthInPets,
            120.0001,
            "two of the pet at this scale must still fit across"
        )
    }

    /// A tank shorter than the height asked for gives the height it has.
    func test_aShortTankGivesTheHeightItHas() {
        let scale = tank(CGSize(width: 900, height: 40)).scale(forPetOfSize: pet)

        XCTAssertEqual(drawnHeight(scale), 40, accuracy: 0.0001)
    }

    /// Before the client has reported anything there is nothing to fit to,
    /// so the height asked for is the answer.
    func test_beforeAnyReportTheHeightAskedForIsTheAnswer() {
        let scale = tank(nil, petHeight: 50).scale(forPetOfSize: pet)

        XCTAssertEqual(drawnHeight(scale), 50, accuracy: 0.0001)
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

    /// The reported fault, as a test: a package that declares a big hitbox
    /// and one that declares a small one must be fitted to the same island
    /// the same way, because neither number decides how big the pet is drawn.
    func testTheFitDoesNotDependOnWhatThePackageClaims() {
        let small = CGSize(width: 130, height: 133)
        let large = CGSize(width: 251, height: 300)
        let island = tank(CGSize(width: 900, height: 120))

        let fromSmall = AvatarStandardSize.size(
            hitbox: small, scale: CGFloat(island.scale(forPetOfSize: small))
        ).height
        let fromLarge = AvatarStandardSize.size(
            hitbox: large, scale: CGFloat(island.scale(forPetOfSize: large))
        ).height

        XCTAssertEqual(fromSmall, fromLarge, accuracy: 0.0001)
    }

    /// An island with room to spare must actually use it. The height asked
    /// for was low enough that the pet came out small in every island, not
    /// just the cramped ones.
    func testAnIslandWithRoomToSpareGetsABigPet() {
        let roomy = tank(CGSize(width: 2000, height: 400)).scale(forPetOfSize: pet)

        XCTAssertGreaterThanOrEqual(drawnHeight(roomy), 200)
    }

    // MARK: - What "the desktop" is, across two quick trips

    /// The size and the room the pet had on the desktop, taken down on the way
    /// in.
    func test_goingHomeRemembersTheDesktopItLeft() {
        var tank = TankResidency()
        let desktop = [CGRect(x: 0, y: 0, width: 1440, height: 900)]

        let remembered = tank.rememberingDesktop(currentAreas: desktop, currentScale: 1.4, isMidTrip: false)

        XCTAssertEqual(remembered, desktop)
        XCTAssertEqual(tank.desktopScale, 1.4, accuracy: 0.0001)
    }

    /// Two quick Cmd-Tabs: the window loses front and the pet sets off for the
    /// desktop, then the window comes back before it lands. What the pet is
    /// passing through -- a size between the two ends, an area widened to
    /// cover both -- is not the desktop, and writing it down as one is how the
    /// pet came back out at whatever size the trip happened to be at.
    func test_aTripThatHasNotLandedIsNotTheDesktop() {
        var tank = TankResidency()
        let desktop = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        _ = tank.rememberingDesktop(currentAreas: desktop, currentScale: 1.4, isMidTrip: false)

        // Heading back out, half way, at half the size and in the union of
        // both worlds.
        let midTrip = desktop + [CGRect(x: 400, y: 40, width: 600, height: 38)]
        let remembered = tank.rememberingDesktop(currentAreas: midTrip, currentScale: 0.6, isMidTrip: true)

        XCTAssertEqual(remembered, desktop, "the desktop is where the trip was heading, not where it is")
        XCTAssertEqual(tank.desktopScale, 1.4, accuracy: 0.0001, "the desktop size must survive the crossing")
    }

    /// With nothing remembered yet there is nothing better to use, so a
    /// mid-trip call still has to answer with something the pet can stand in.
    func test_aTripWithNothingRememberedFallsBackToWhatItHas() {
        var tank = TankResidency()
        let areas = [CGRect(x: 0, y: 0, width: 800, height: 600)]

        let remembered = tank.rememberingDesktop(currentAreas: areas, currentScale: 1, isMidTrip: true)

        XCTAssertEqual(remembered, areas)
    }
}
