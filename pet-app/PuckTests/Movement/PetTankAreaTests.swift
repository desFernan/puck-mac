//
//  PetTankAreaTests.swift
//  Puck
//

import XCTest
import CoreGraphics
@testable import Puck

/// `@MainActor`: it reads AppDelegate.tankPetHeight, which the frame loop
/// and the bridge both touch from the main thread.
@MainActor
final class PetTankAreaTests: XCTestCase {
    private let overlayOrigin = CGPoint(x: 0, y: 0)
    private let overlaySize = CGSize(width: 1470, height: 956)
    private let pet = CGSize(width: 60, height: 72)

    func test_aTankOnThePrimaryDisplayBecomesAnOverlayLocalRect() {
        let area = PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 200, y: 39, width: 1200, height: 90),
            overlayOriginInQuartz: overlayOrigin,
            overlaySize: overlaySize,
            petSize: pet
        )

        XCTAssertEqual(area, CGRect(x: 200, y: 39, width: 1200, height: 90))
    }

    /// The overlay window is not always at the origin of Quartz space -- on a
    /// second display it is not. The rect is rebased the same way the window
    /// list is (AppDelegate.overlayLocalWindows).
    func test_theRectIsRebasedOntoTheOverlayWindow() {
        let area = PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 1670, y: 139, width: 800, height: 90),
            overlayOriginInQuartz: CGPoint(x: 1470, y: 100),
            overlaySize: overlaySize,
            petSize: pet
        )

        XCTAssertEqual(area, CGRect(x: 200, y: 39, width: 800, height: 90))
    }

    /// A tank the pet cannot stand in is not a tank. Refused rather than
    /// clamped: the pet stays on the desktop, which is somewhere it fits.
    func test_aTankTooSmallForThePetIsRefused() {
        XCTAssertNil(PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 200, y: 39, width: 100, height: 90),
            overlayOriginInQuartz: overlayOrigin,
            overlaySize: overlaySize,
            petSize: pet
        ), "narrower than two pets")

        XCTAssertNil(PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 200, y: 39, width: 1200, height: 40),
            overlayOriginInQuartz: overlayOrigin,
            overlaySize: overlaySize,
            petSize: pet
        ), "shorter than the pet")
    }

    func test_aTankOutsideTheOverlayIsRefused() {
        XCTAssertNil(PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 3000, y: 39, width: 1200, height: 90),
            overlayOriginInQuartz: overlayOrigin,
            overlaySize: overlaySize,
            petSize: pet
        ))
    }

    /// The guard is `>=`, not `>` -- a tank exactly two pet-widths wide and
    /// exactly one pet tall is the smallest one the pet can still walk in,
    /// and nothing else in the suite exercises that edge.
    func test_aTankExactlyAtTheMinimumSizeIsAccepted() {
        let area = PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 200, y: 39, width: 120, height: 72),
            overlayOriginInQuartz: overlayOrigin,
            overlaySize: overlaySize,
            petSize: pet
        )

        XCTAssertEqual(area, CGRect(x: 200, y: 39, width: 120, height: 72))
    }

    /// A client window dragged partway off the overlay reports its full
    /// on-screen rect, not just the visible slice. The pet can only stand in
    /// the part that is actually inside the overlay it's rendered on top of.
    func test_aTankHangingOffTheOverlayIsClippedToIt() {
        let area = PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 1300, y: 39, width: 300, height: 90),
            overlayOriginInQuartz: overlayOrigin,
            overlaySize: overlaySize,
            petSize: pet
        )

        XCTAssertEqual(area, CGRect(x: 1300, y: 39, width: 170, height: 90))
    }

    /// The old check sized up the raw rect before ever clipping it, so a
    /// tank that only looks roomy because most of it is off screen used to
    /// be handed to the movement engine whole. What's left after clipping is
    /// the part the pet could actually stand in, and here that's not enough.
    func test_aTankBigEnoughOnlyBeforeClippingIsRefused() {
        XCTAssertNil(PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 1400, y: 39, width: 300, height: 90),
            overlayOriginInQuartz: overlayOrigin,
            overlaySize: overlaySize,
            petSize: pet
        ))
    }

    /// CGRect's width/height getters silently return the absolute value of a
    /// negative size, so without an explicit sign check a malformed wire rect
    /// (a bad reading, a race during a resize) would sail through the size
    /// guard as if it were a large, legitimate tank. Zero is refused too --
    /// there's nothing to stand in.
    func test_zeroOrNegativeWireDimensionsAreRefused() {
        XCTAssertNil(PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 200, y: 39, width: 0, height: 90),
            overlayOriginInQuartz: overlayOrigin,
            overlaySize: overlaySize,
            petSize: pet
        ), "zero width")

        XCTAssertNil(PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 200, y: 39, width: 1200, height: 0),
            overlayOriginInQuartz: overlayOrigin,
            overlaySize: overlaySize,
            petSize: pet
        ), "zero height")

        XCTAssertNil(PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 200, y: 39, width: -1200, height: 90),
            overlayOriginInQuartz: overlayOrigin,
            overlaySize: overlaySize,
            petSize: pet
        ), "negative width")

        XCTAssertNil(PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 200, y: 39, width: 1200, height: -90),
            overlayOriginInQuartz: overlayOrigin,
            overlaySize: overlaySize,
            petSize: pet
        ), "negative height")
    }

    /// A rect whose far edge lands exactly on the overlay's own edge isn't
    /// "hanging off" -- it's flush with it, still entirely on screen.
    /// CGRect's intersection treats touching bounds as fully contained, so
    /// this is accepted at its full size rather than clipped down or
    /// refused; that matches reality better than an off-by-one would.
    func test_aTankFlushAgainstTheOverlaysRightEdgeIsAcceptedWhole() {
        let area = PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 1350, y: 39, width: 120, height: 72),
            overlayOriginInQuartz: overlayOrigin,
            overlaySize: overlaySize,
            petSize: pet
        )

        XCTAssertEqual(area, CGRect(x: 1350, y: 39, width: 120, height: 72))
    }

    /// The island has to be at least as tall as the pet that lives on it, or
    /// the area is refused and the pet silently stays on the desktop --
    /// nothing on screen says why.
    ///
    /// This is not hypothetical. Insetting the island vertically to float it
    /// took 90pt down to 74 against an 80pt pet, and opening the window
    /// stopped moving the pet at all.
    ///
    /// Asked of the *smallest* the island can be dragged to, since that is
    /// the one a person can reach and the one the default no longer protects.
    func test_theIslandIsTallEnoughForThePetThatLivesOnIt() {
        let petHeight = AppDelegate.tankPetHeight
        XCTAssertGreaterThanOrEqual(
            PetTankView.minimumIslandHeight,
            petHeight,
            "an island the pet does not fit in is refused, and that looks like the pet refusing to come home"
        )

        let accepted = PetTankArea.roamableArea(
            fromWire: BridgeRect(x: 0, y: 0, width: 600, height: Double(PetTankView.minimumIslandHeight)),
            overlayOriginInQuartz: .zero,
            overlaySize: CGSize(width: 1440, height: 900),
            // Square-ish is the worst case for the width rule; the bundled
            // avatar is 130x133, so its width at this height is close to it.
            petSize: CGSize(width: petHeight, height: petHeight)
        )
        XCTAssertNotNil(accepted, "the island as drawn has to be a usable world")
    }

    /// The handle cannot be dragged past either end into a size that is not a
    /// shelf: too short and the area is refused, too tall and the island is
    /// the window.
    func test_theIslandsLimitsBracketItsDefault() {
        XCTAssertLessThanOrEqual(PetTankView.minimumIslandHeight, PetTankView.islandHeight)
        XCTAssertGreaterThan(PetTankView.maximumIslandHeight, PetTankView.islandHeight)
    }

    /// Whatever height it is dragged to, the strip around it grows with it --
    /// a fixed strip would clip the island the first time someone made it
    /// taller.
    func test_theStripGrowsWithTheIsland() {
        for island in [PetTankView.minimumIslandHeight, PetTankView.islandHeight, PetTankView.maximumIslandHeight] {
            XCTAssertGreaterThan(PetTankView.stripHeight(island: island), island)
        }
    }

    /// The size slider bounds itself by the island's height, which is not the
    /// dimension that binds: a tank has to be two pets across before it is
    /// worth standing in, so a narrow window refuses a pet its height alone
    /// would have allowed -- and a refusal is invisible from the outside.
    func test_aNarrowTankSizesThePetDownRatherThanRefusingIt() {
        let fitted = PetTankArea.fittedPetHeight(
            desired: 200,
            tank: CGSize(width: 300, height: 260),
            aspect: 1
        )

        XCTAssertEqual(fitted, 150, "two pets wide is the rule, so 300pt of tank is a 150pt pet")
    }

    /// A tank with room to spare gives the size that was asked for. Sizing
    /// down when nothing requires it would undo the slider.
    func test_aRoomyTankGivesTheSizeThatWasAsked() {
        let fitted = PetTankArea.fittedPetHeight(
            desired: 72,
            tank: CGSize(width: 1_100, height: 90),
            aspect: 0.8
        )

        XCTAssertEqual(fitted, 72)
    }

    /// Height still binds when it is the smaller of the two.
    func test_aShortTankBindsByHeight() {
        let fitted = PetTankArea.fittedPetHeight(
            desired: 200,
            tank: CGSize(width: 2_000, height: 84),
            aspect: 0.8
        )

        XCTAssertEqual(fitted, 84)
    }

    /// A wide pet needs more width per point of height, and the fit has to
    /// know that rather than assuming a square.
    func test_theAspectRatioIsPartOfTheFit() {
        let narrow = PetTankArea.fittedPetHeight(desired: 300, tank: CGSize(width: 400, height: 400), aspect: 0.5)
        let wide = PetTankArea.fittedPetHeight(desired: 300, tank: CGSize(width: 400, height: 400), aspect: 2)

        XCTAssertEqual(narrow, 300, "a narrow pet fits at the size that was asked for")
        XCTAssertEqual(wide, 100, "a wide one has to come down to fit the same tank")
    }

    /// Nothing to fit into: a report with no size yet must not answer zero,
    /// which would put a pet of no height on the island.
    func test_anEmptyTankLeavesTheDesiredSizeAlone() {
        XCTAssertEqual(PetTankArea.fittedPetHeight(desired: 72, tank: .zero, aspect: 1), 72)
    }
}
