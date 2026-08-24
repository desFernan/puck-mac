//
//  NearestClimbTargetTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Choosing a window to go and climb, so the pet climbs windows now and then
//  instead of staying glued to the floor.
//
//  The target has to be one WalkState's own blockingWindow check will then
//  pick up, so these assert the handoff conditions rather than just "some
//  point near a window".
//

import XCTest
@testable import Puck

final class NearestClimbTargetTests: XCTestCase {
    /// Y grows downward; the floor is at the bottom.
    private let floor: CGFloat = 800
    private let roamableTop: CGFloat = 0
    private let avatarHeight: CGFloat = 130

    private func window(x: CGFloat, width: CGFloat = 300, top: CGFloat = 200) -> WindowInfo {
        window(frame: CGRect(x: x, y: top, width: width, height: 900 - top))
    }

    private func window(frame: CGRect) -> WindowInfo {
        WindowInfo(windowID: CGWindowID(abs(Int(frame.minX)) + 1), ownerPID: 1, ownerName: nil, title: nil, layer: 0, frame: frame)
    }

    private func target(from x: CGFloat, windows: [WindowInfo], excluding: Set<CGWindowID> = []) -> CGPoint? {
        WindowSupport.nearestClimbTarget(
            from: CGPoint(x: x, y: floor),
            in: windows,
            roamableTop: roamableTop,
            avatarHeight: avatarHeight,
            excluding: excluding
        )
    }

    func test_walksToTheNearerEdgeOfTheOnlyWindow() throws {
        let result = try XCTUnwrap(target(from: 100, windows: [window(x: 400)]))

        XCTAssertEqual(result.x, 400, accuracy: 5, "the left edge is the near one from x=100")
        XCTAssertEqual(result.y, floor, "walking, not teleporting upward")
    }

    func test_picksTheFarSideWhenThePetIsPastTheWindow() throws {
        let result = try XCTUnwrap(target(from: 900, windows: [window(x: 400)]))

        XCTAssertEqual(result.x, 700, accuracy: 5, "the right edge at 400+300")
    }

    func test_picksTheNearestOfSeveralWindows() throws {
        let result = try XCTUnwrap(target(from: 100, windows: [window(x: 600), window(x: 200), window(x: 900)]))

        XCTAssertEqual(result.x, 200, accuracy: 5)
    }

    /// The target must lie *past* the edge, or `blockingWindow` never sees the
    /// edge as being between the pet and where it's going, and the pet walks
    /// up to the window and just stops.
    func test_theTargetOvershootsTheEdgeSoTheClimbTriggers() throws {
        let windows = [window(x: 400)]
        let start = CGPoint(x: 100, y: floor)
        let result = try XCTUnwrap(target(from: start.x, windows: windows))

        XCTAssertGreaterThan(result.x, 400, "stopping exactly on the edge doesn't trigger a climb")
        XCTAssertNotNil(
            WindowSupport.blockingWindow(
                walkingFrom: start,
                toward: result,
                in: windows,
                roamableTop: roamableTop,
                avatarHeight: avatarHeight
            ),
            "WalkState would not recognise this target as a climb"
        )
    }

    // MARK: - When there's nothing to climb

    func test_noWindowsMeansNoTarget() {
        XCTAssertNil(target(from: 100, windows: []))
    }

    /// A window that doesn't reach down to where the pet is standing can't be
    /// climbed from the floor.
    func test_ignoresWindowsAboveThePet() {
        // Ends at y=300, well above the floor.
        let floating = window(frame: CGRect(x: 400, y: 100, width: 300, height: 200))

        XCTAssertNil(target(from: 100, windows: [floating]))
    }

    /// Same headroom rule the rest of F3 uses: a near-fullscreen window has
    /// nowhere to stand on top, so it isn't worth walking to.
    func test_ignoresWindowsWithNoHeadroomOnTop() {
        // Only 20pt of headroom above its top edge.
        let tall = window(frame: CGRect(x: 400, y: 20, width: 300, height: 880))

        XCTAssertNil(target(from: 100, windows: [tall]))
    }

    /// Standing at a window's side, with only that window in reach, there is
    /// nothing to aim at.
    ///
    /// This used to walk to the far edge. That walk can never become a climb:
    /// a climb happens by crossing a window's left side going right or its
    /// right side going left, and from inside the window's own span neither
    /// is ahead of the pet -- it arrives and strolls past. Nil sends the
    /// caller to an ordinary roam, which at least moves the pet somewhere a
    /// climb can start from.
    func test_aWindowThePetIsStandingInFrontOfIsNotAClimbTarget() {
        XCTAssertNil(target(from: 400, windows: [window(x: 400)]))
        XCTAssertNil(target(from: 550, windows: [window(x: 400)]), "inside its span")
    }

    /// ...and another window's near side still is, so the pet has not stopped
    /// climbing -- only stopped walking at edges it cannot take.
    func test_anotherWindowsNearSideIsStillChosen() {
        let standingIn = window(x: 400)          // 400...700
        let reachable = window(x: 900)           // 900...1200

        XCTAssertEqual(target(from: 550, windows: [standingIn, reachable])?.x, 900 + 4)
    }

    // MARK: - "포커스된 창 위로는 올라가지 않기" (Settings)

    /// The toggle's whole promise. Before it had a reader, an excluded window
    /// was climbed exactly like any other.
    func test_anExcludedWindowIsNeverChosenToClimb() {
        let focused = window(x: 400)

        XCTAssertNil(target(from: 100, windows: [focused], excluding: [focused.windowID]))
    }

    /// Excluding one window doesn't stop the pet climbing anything else --
    /// the setting is "not that window", not "no climbing".
    func test_excludingOneWindowFallsThroughToTheNextClimbableOne() throws {
        let focused = window(x: 200)
        let other = window(x: 600)

        let result = try XCTUnwrap(
            target(from: 100, windows: [focused, other], excluding: [focused.windowID])
        )

        XCTAssertEqual(result.x, 600, accuracy: 5)
    }

    /// The incidental climb, not the deliberate one: a plain walk whose path
    /// crosses the focused window's edge must walk past it rather than climb
    /// it, or the setting would only hold for wanders that aimed at it.
    func test_anExcludedWindowDoesNotBlockAWalkThatCrossesIt() {
        let focused = window(x: 400)

        XCTAssertNil(
            WindowSupport.blockingWindow(
                walkingFrom: CGPoint(x: 100, y: floor),
                toward: CGPoint(x: 900, y: floor),
                in: [focused],
                roamableTop: roamableTop,
                avatarHeight: avatarHeight,
                excluding: [focused.windowID]
            )
        )
    }

    // MARK: - Which window counts as focused

    private func window(id: CGWindowID, pid: pid_t, layer: Int = 0) -> WindowInfo {
        WindowInfo(windowID: id, ownerPID: pid, ownerName: nil, title: nil, layer: layer, frame: .zero)
    }

    /// Front-to-back Z order, so the frontmost app's first window is the one
    /// the user is looking at -- the same rule get_frontmost_window applies.
    func test_focusedWindow_isTheFrontmostWindowOfTheFrontmostApp() {
        let windows = [window(id: 1, pid: 10), window(id: 2, pid: 20), window(id: 3, pid: 20)]

        XCTAssertEqual(WindowSupport.focusedWindow(ownedBy: 20, in: windows)?.windowID, 2)
    }

    func test_focusedWindow_ignoresNonZeroLayers() {
        let windows = [window(id: 1, pid: 20, layer: 25), window(id: 2, pid: 20)]

        XCTAssertEqual(WindowSupport.focusedWindow(ownedBy: 20, in: windows)?.windowID, 2)
    }

    func test_focusedWindow_nilWhenNothingIsFrontmost() {
        XCTAssertNil(WindowSupport.focusedWindow(ownedBy: nil, in: [window(id: 1, pid: 10)]))
        XCTAssertNil(WindowSupport.focusedWindow(ownedBy: 99, in: [window(id: 1, pid: 10)]))
    }

    // MARK: - Edges nobody can see

    /// Both fixtures below sit at y=200 so they clear the avatar-height
    /// headroom rule; what is being tested is Z order, not headroom.
    private func climbable(x: CGFloat, width: CGFloat) -> WindowInfo {
        window(frame: CGRect(x: x, y: 200, width: width, height: 700))
    }

    /// A window entirely behind another has no edge on screen, and walking to
    /// one is a pet turning round, crossing the desktop for no visible
    /// reason, and going up thin air. Landing has always asked this of a
    /// surface; climbing did not.
    func test_ignoresAnEdgeHiddenBehindAWindowInFront() {
        let cover = climbable(x: 300, width: 500)   // 300...800, frontmost
        let hidden = climbable(x: 400, width: 200)  // 400...600, entirely under it

        let aim = target(from: 100, windows: [cover, hidden])
        // Past the edge in the direction of travel, which is how the walk
        // ends up crossing it and handing off to Climb.
        XCTAssertEqual(aim?.x, 300 + 4, "the cover's own left side is the only edge that shows")
    }

    /// Only the covered part is out. A window sticking out from behind
    /// another still has the side you can see.
    func test_keepsTheEdgeThatStillShows() {
        let cover = climbable(x: 300, width: 500)   // 300...800, frontmost
        let behind = climbable(x: 100, width: 400)  // 100...500: left side shows, right side does not

        XCTAssertEqual(target(from: 1000, windows: [cover, behind])?.x, 800 - 4)
        // From inside `behind`'s span, its own edges are not approachable;
        // the cover's left side is, and can be seen.
        XCTAssertEqual(target(from: 150, windows: [cover, behind])?.x, 300 + 4)
    }

    /// The same rule where a walk actually becomes a climb: an edge the pet
    /// blunders into is no more of a wall than one it aimed at.
    func test_walkingIntoAHiddenEdgeDoesNotClimb() {
        let cover = climbable(x: 300, width: 500)
        let hidden = climbable(x: 400, width: 200)

        XCTAssertNil(
            WindowSupport.blockingWindow(
                walkingFrom: CGPoint(x: 350, y: floor),
                toward: CGPoint(x: 700, y: floor),
                in: [cover, hidden],
                roamableTop: roamableTop,
                avatarHeight: avatarHeight
            ),
            "the hidden window's left edge at 400 is under the cover"
        )
    }

    /// Being in front is what matters, not merely overlapping: the same two
    /// rectangles the other way round leave the edge climbable.
    func test_aWindowBehindDoesNotHideAnEdgeInFrontOfIt() {
        let front = climbable(x: 400, width: 200)
        let back = climbable(x: 300, width: 500)

        let blocked = WindowSupport.blockingWindow(
            walkingFrom: CGPoint(x: 350, y: floor),
            toward: CGPoint(x: 700, y: floor),
            in: [front, back],
            roamableTop: roamableTop,
            avatarHeight: avatarHeight
        )
        XCTAssertEqual(blocked?.frame.minX, 400)
    }
}
