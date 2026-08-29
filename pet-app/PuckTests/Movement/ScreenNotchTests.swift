//
//  ScreenNotchTests.swift
//  PuckTests
//
//  The camera housing as something in the pet's way -- tested on a machine
//  that has none, which is the whole reason the geometry is pure.
//

import XCTest
@testable import Puck

final class ScreenNotchTests: XCTestCase {
    /// A 16" MacBook Pro's numbers, in AppKit's space: the screen is
    /// 3456x2234, the menu bar beside the notch is 37pt tall, and the notch
    /// is the gap left between the two strips.
    private let screen = CGRect(x: 0, y: 0, width: 3456, height: 2234)
    private var left: CGRect { CGRect(x: 0, y: 2197, width: 1493, height: 37) }
    private var right: CGRect { CGRect(x: 1963, y: 2197, width: 1493, height: 37) }

    // MARK: - Reading it off the screen

    func test_theNotchIsTheGapBetweenTheTwoStrips() throws {
        let notch = try XCTUnwrap(ScreenNotch.appKitRect(
            inScreenFrame: screen,
            auxiliaryTopLeft: left,
            auxiliaryTopRight: right
        ))

        XCTAssertEqual(notch.minX, 1493)
        XCTAssertEqual(notch.maxX, 1963)
        XCTAssertEqual(notch.height, 37, "as tall as the strips beside it")
        XCTAssertEqual(notch.maxY, screen.maxY, "and its top is the screen's")
    }

    /// A display with no notch reports neither strip, and must produce
    /// nothing rather than a rectangle spanning the whole screen.
    func test_aScreenWithNoNotchHasNone() {
        XCTAssertNil(ScreenNotch.appKitRect(inScreenFrame: screen, auxiliaryTopLeft: nil, auxiliaryTopRight: nil))
        XCTAssertNil(ScreenNotch.appKitRect(inScreenFrame: screen, auxiliaryTopLeft: left, auxiliaryTopRight: nil))
        XCTAssertNil(ScreenNotch.appKitRect(inScreenFrame: screen, auxiliaryTopLeft: nil, auxiliaryTopRight: right))
    }

    /// Strips that meet, or arrive the other way round on an arrangement
    /// nobody anticipated, are not a notch. A negative width would be a
    /// rectangle the pet then tries to walk around.
    func test_anImpossibleGapIsNotANotch() {
        let touching = CGRect(x: 1493, y: 2197, width: 1493, height: 37)
        XCTAssertNil(ScreenNotch.appKitRect(inScreenFrame: screen, auxiliaryTopLeft: left, auxiliaryTopRight: touching))
        XCTAssertNil(ScreenNotch.appKitRect(inScreenFrame: screen, auxiliaryTopLeft: right, auxiliaryTopRight: left))
    }

    // MARK: - What it does to the ceiling

    /// In the pet's space: y grows downward, so the notch hangs from y=0 and
    /// its bottom edge is the larger number.
    private let notch = ScreenNotch(rect: CGRect(x: 1493, y: 0, width: 470, height: 37))

    func test_awayFromTheNotchTheCeilingIsTheScreensOwn() {
        XCTAssertEqual(notch.ceiling(atX: 100, areaTop: 0), 0)
        XCTAssertEqual(notch.ceiling(atX: 3400, areaTop: 0), 0)
    }

    func test_underTheNotchTheCeilingIsItsBottomEdge() {
        XCTAssertEqual(notch.ceiling(atX: 1700, areaTop: 0), 37)
    }

    /// Its own sides count as under it: a ceiling that changed only strictly
    /// inside would let the pet clip the corner.
    func test_theNotchsOwnEdgesAreUnderIt() {
        XCTAssertEqual(notch.ceiling(atX: 1493, areaTop: 0), 37)
        XCTAssertEqual(notch.ceiling(atX: 1963, areaTop: 0), 37)
    }

    /// The ordinary case, and the reason this is usually invisible: with the
    /// menu bar there, the pet's own ceiling is already below the notch, and
    /// the notch must not raise it back up.
    func test_aCeilingAlreadyBelowTheNotchIsLeftAlone() {
        XCTAssertEqual(notch.ceiling(atX: 1700, areaTop: 37), 37)
        XCTAssertEqual(notch.ceiling(atX: 1700, areaTop: 60), 60, "never above the area's own top")
    }

    // MARK: - Whether the pet clears it

    /// A pet's outline, standing on its feet: 40 wide, 80 tall.
    private let outline = CGRect(x: -20, y: -80, width: 40, height: 80)

    func test_aPetWellClearOfTheNotchClearsIt() {
        XCTAssertTrue(notch.clears(CGPoint(x: 400, y: 80), visualBounds: outline, areaTop: 0))
    }

    /// Its head, not its feet: the pet hangs upside down from the ceiling, so
    /// what meets the camera housing is the top of the drawing.
    func test_aPetWhoseHeadIsInsideTheNotchDoesNot() {
        XCTAssertFalse(notch.clears(CGPoint(x: 1700, y: 100), visualBounds: outline, areaTop: 0))
        XCTAssertTrue(notch.clears(CGPoint(x: 1700, y: 117), visualBounds: outline, areaTop: 0))
    }

    /// Half a pet behind the camera housing is as wrong as all of it, so the
    /// question is asked of the outline's edges rather than its middle.
    func test_aPetHalfwayUnderTheNotchDoesNotClearIt() {
        // Feet at the notch's left edge: its middle is clear, its right
        // shoulder is not.
        XCTAssertFalse(notch.clears(CGPoint(x: 1483, y: 100), visualBounds: outline, areaTop: 0))
    }
}

/// The same reading, taken off whatever screen this actually is.
///
/// Everything above is arithmetic on numbers a test wrote down. This checks
/// the numbers AppKit really reports on the machine running it -- and it has
/// to pass on both kinds of machine, since most have no notch and CI never
/// does. What it can assert either way is the relationship the feature rests
/// on: the menu bar is at least as tall as the notch, which is why the pet
/// only meets it once the menu bar is gone.
@MainActor
final class RealScreenNotchTests: XCTestCase {
    func test_whateverThisMachineReportsIsCoherent() throws {
        for screen in NSScreen.screens {
            guard let notch = ScreenNotch.appKitRect(
                inScreenFrame: screen.frame,
                auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
                auxiliaryTopRight: screen.auxiliaryTopRightArea
            ) else {
                continue  // no notch on this display, which is the usual case
            }

            XCTAssertTrue(screen.frame.contains(notch), "a notch outside its own screen is a rebasing bug")
            XCTAssertEqual(notch.maxY, screen.frame.maxY, "it hangs from the top edge")
            XCTAssertGreaterThan(notch.width, 0)
            XCTAssertLessThan(notch.width, screen.frame.width / 2, "a notch is a notch, not half the screen")

            // The reason this is invisible until a Space goes fullscreen: the
            // pet's world stops at the menu bar, and the menu bar is at least
            // as deep as the housing.
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            XCTAssertGreaterThanOrEqual(
                menuBar, notch.height,
                "if the housing were deeper than the menu bar it would intrude in the ordinary case too"
            )

            // Both halves of the feature, against this machine's real
            // measurements rather than a test's invented ones. In the pet's
            // own space the housing hangs from y=0 to y=height.
            let housing = ScreenNotch(rect: CGRect(
                x: notch.minX, y: 0, width: notch.width, height: notch.height
            ))
            let underIt = notch.midX

            // With the menu bar there the pet's ceiling is already below the
            // housing, and the housing must not raise it back up.
            XCTAssertEqual(
                housing.ceiling(atX: underIt, areaTop: menuBar), menuBar,
                "the ordinary case has to stay exactly as it was"
            )
            // In a fullscreen Space the menu bar's height is given back, and
            // then the housing really is what stops the pet.
            XCTAssertEqual(
                housing.ceiling(atX: underIt, areaTop: 0), notch.height,
                "with the menu bar gone the ceiling under the housing is its bottom edge"
            )
            XCTAssertEqual(
                housing.ceiling(atX: notch.minX - 1, areaTop: 0), 0,
                "and beside it the whole screen is still there"
            )
        }
    }
}

/// Which housing belongs to which display, and what happens when the answer
/// changes -- a monitor plugged in or out, a lid closed, a resolution
/// changed. The pet's world is re-measured at each of those, and the
/// housings are measured with it.
@MainActor
final class ScreenNotchPerDisplayTests: XCTestCase {
    /// A MacBook on the left with a housing, an external monitor on the
    /// right without one. Both in the pet's own space.
    private let laptop = CGRect(x: 0, y: 33, width: 1512, height: 870)
    private let external = CGRect(x: 1512, y: 30, width: 3440, height: 1318)
    private var housing: ScreenNotch { ScreenNotch(rect: CGRect(x: 663, y: 0, width: 185, height: 32)) }

    private func context(notches: [ScreenNotch]) -> StateContext {
        StateContext(
            body: CharacterBody(avatar: SpyAvatarPlayable(), position: .zero),
            roamableArea: laptop.union(external),
            roamableAreas: [laptop, external],
            notches: notches,
            avatarHeight: 80,
            visualBounds: CGRect(x: -20, y: -80, width: 40, height: 80),
            walkSpeed: 90,
            windows: [],
            unclimbableWindowIDs: [],
            landingY: { _ in 0 },
            requestTransition: { _ in }
        )
    }

    /// A MacBook driving an external monitor has one housing and two
    /// displays. A pet crawling the external screen's ceiling must not duck
    /// around a housing that is over the other one.
    func test_theHousingBelongsToTheDisplayItHangsOver() {
        let context = context(notches: [housing])

        XCTAssertNotNil(context.notch(over: laptop))
        XCTAssertNil(context.notch(over: external))
    }

    /// The ceiling follows from that: unchanged on the display with nothing
    /// over it, whatever x is asked about.
    func test_theExternalScreensCeilingIsUntouched() {
        let context = context(notches: [housing])

        // The same x the housing occupies on the laptop, asked of the screen
        // beside it.
        XCTAssertEqual(context.ceilingY(atX: 750, on: external), external.minY)
        XCTAssertEqual(context.ceilingY(atX: 750, on: laptop), laptop.minY, "menu bar still lower than the housing")
    }

    /// A lid closed or a monitor unplugged empties the list, and the ceiling
    /// is a plain edge again. This is the case that has to be right without
    /// anybody remembering to clear anything: the housings are measured
    /// wherever the screens are, so a screen that is gone takes its housing
    /// with it.
    func test_aHousingThatHasGoneStopsMattering() {
        let fullscreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(
            context(notches: [housing]).ceilingY(atX: 750, on: fullscreen), 32,
            "with the housing there it is what stops the pet"
        )
        XCTAssertEqual(
            context(notches: []).ceilingY(atX: 750, on: fullscreen), 0,
            "and with it gone the ceiling is the screen's own top again"
        )
    }

    /// Two MacBooks, or a machine somebody has arranged unusually: each
    /// display gets its own answer rather than the first one found.
    func test_eachDisplayGetsItsOwnHousing() {
        let second = ScreenNotch(rect: CGRect(x: 1512 + 1600, y: 0, width: 185, height: 32))
        let context = context(notches: [housing, second])

        XCTAssertEqual(context.notch(over: laptop)?.rect.minX, 663)
        XCTAssertEqual(context.notch(over: external)?.rect.minX, 1512 + 1600)
    }
}

/// A display with no camera housing does not get given one.
///
/// It was given one for a while -- 185 points of drawn bar in the middle of
/// the menu bar, so a monitor could have the panel too. What that cost was
/// paid by everything else: the pet ducked around a housing the user could
/// not see on any display the panel was not drawn on, and the shut panel sat
/// over live menu bar and took clicks meant for the app's own menus.
final class NoVirtualNotchTests: XCTestCase {
    /// An external monitor: two strips is what a notch looks like to AppKit,
    /// and a screen without one reports neither.
    func test_aScreenWithNoAuxiliaryAreasHasNoNotch() {
        XCTAssertNil(
            ScreenNotch.appKitRect(
                inScreenFrame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                auxiliaryTopLeft: nil,
                auxiliaryTopRight: nil
            ),
            "a monitor has no camera housing, and must not be given one"
        )
    }

    /// One strip and not the other is not a notch either -- an arrangement
    /// nobody anticipated must produce nothing rather than a guess.
    func test_oneAuxiliaryAreaAloneIsNotANotch() {
        let strip = CGRect(x: 0, y: 1410, width: 600, height: 30)
        XCTAssertNil(ScreenNotch.appKitRect(
            inScreenFrame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
            auxiliaryTopLeft: strip,
            auxiliaryTopRight: nil
        ))
        XCTAssertNil(ScreenNotch.appKitRect(
            inScreenFrame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: strip
        ))
    }

    // MARK: - The panel's notch, which is not the pet's

    private let ultrawide = CGRect(x: 0, y: 0, width: 3440, height: 1440)

    /// A display with no camera housing gets a drawn one, so the panel is
    /// available on a monitor. This is panel-only on purpose: `appKitRect`,
    /// which is what the pet is given, still answers nil for the same screen.
    func testADisplayWithNoHousingStillGetsAPanelNotch() {
        let drawn = ScreenNotch.panelAppKitRect(
            onScreenFrame: ultrawide,
            visibleFrame: ultrawide.insetBy(dx: 0, dy: 0).offsetBy(dx: 0, dy: -37)
                .divided(atDistance: 1403, from: .minYEdge).slice,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil
        )

        XCTAssertNotNil(drawn)
        XCTAssertEqual(drawn?.width, ScreenNotch.drawnWidth)
        XCTAssertEqual(drawn?.midX ?? 0, ultrawide.midX, accuracy: 0.001)
        XCTAssertEqual(drawn?.maxY ?? 0, ultrawide.maxY, accuracy: 0.001,
                       "it has to sit in the menu bar, not below it")
    }

    /// The pet must not be given the drawn one. It was taken out once because
    /// the pet ducked around a housing that was not there and stopped under
    /// it on displays the panel was not even on.
    func testThePetIsNotGivenADrawnNotch() {
        XCTAssertNil(ScreenNotch.appKitRect(
            inScreenFrame: ultrawide,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil
        ))
    }

    /// A real housing wins: a MacBook must get its own notch, not a drawn one
    /// centred on the screen.
    func testARealHousingIsUsedWhenThereIsOne() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let left = CGRect(x: 0, y: 945, width: 640, height: 37)
        let right = CGRect(x: 872, y: 945, width: 640, height: 37)

        let panel = ScreenNotch.panelAppKitRect(
            onScreenFrame: frame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945),
            auxiliaryTopLeft: left,
            auxiliaryTopRight: right
        )

        XCTAssertEqual(panel?.minX, 640)
        XCTAssertEqual(panel?.width, 232, "the gap between the two strips, not the drawn width")
    }

    /// With no menu bar to sit in -- a fullscreen Space -- there is nowhere
    /// to draw one, and a notch hanging into the desktop is worse than none.
    func testNoMenuBarMeansNoDrawnNotch() {
        XCTAssertNil(ScreenNotch.panelAppKitRect(
            onScreenFrame: ultrawide,
            visibleFrame: ultrawide,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil
        ))
    }

    /// And nowhere to put one on a display narrower than the notch itself.
    func testAScreenTooNarrowForANotchGetsNone() {
        let tiny = CGRect(x: 0, y: 0, width: 120, height: 400)

        XCTAssertNil(ScreenNotch.panelAppKitRect(
            onScreenFrame: tiny,
            visibleFrame: CGRect(x: 0, y: 0, width: 120, height: 380),
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil
        ))
    }
}
