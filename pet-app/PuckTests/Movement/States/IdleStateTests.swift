//
//  IdleStateTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  IdleState's wander-timer -> delegate callback wiring.
//

import XCTest
@testable import Puck

/// `@MainActor`: the character and its states belong to the main thread,
/// which is where the frame loop drives them.
@MainActor
final class IdleStateTests: XCTestCase {
    private final class SpyWanderDelegate: IdleWanderDelegate {
        private(set) var received: [WanderScheduler.Outcome] = []
        private(set) var lostFootingBehind: [WindowInfo] = []
        func idleStateDidRequestWander(_ outcome: WanderScheduler.Outcome) { received.append(outcome) }
        func idleStateDidLoseFootingBehind(_ window: WindowInfo) { lostFootingBehind.append(window) }
    }

    private static func window(_ frame: CGRect, id: CGWindowID = 1) -> WindowInfo {
        WindowInfo(windowID: id, ownerPID: 1, ownerName: "PuckClient", title: nil, layer: 0, frame: frame)
    }

    func test_update_notifiesDelegate_whenWanderTimerFires() {
        let scheduler = WanderScheduler(nextIntervalProvider: { _ in 8 }, outcomeProvider: { _ in .walkToRandomPoint })
        let state = IdleState(scheduler: scheduler)
        let delegate = SpyWanderDelegate()
        state.wanderDelegate = delegate
        let world = TestStateWorld()
        world.landingY = 0 // already resting on the ground -- not falling

        state.update(dt: 8, context: world.context)

        XCTAssertEqual(delegate.received, [.walkToRandomPoint])
    }

    func test_metadata_matchesManifestIdleClip() {
        let state = IdleState()

        XCTAssertEqual(state.name, "Idle")
        XCTAssertEqual(state.clipKey, "idle")
        XCTAssertTrue(state.loopsClip)
    }

    // MARK: - Ground disappearing (F4, 2026-07-29)

    /// After Fall -> Land -> Idle, the pet can be resting on a window's top
    /// edge (LandingSurfaceResolver treats window tops as valid landing
    /// surfaces) -- if that window closes or minimizes while the pet is
    /// idling there, nothing previously checked for it (only WalkOnTopState
    /// did) -- the pet should fall automatically once the window it's resting
    /// on disappears.
    func test_theSupportingSurfaceDisappearing_requestsFall() {
        let world = TestStateWorld(position: CGPoint(x: 400, y: 200))
        world.landingY = 200 // resting exactly on a window's top edge
        let state = IdleState()

        state.update(dt: 0.1, context: world.context)
        XCTAssertTrue(world.requestedTransitions.isEmpty, "still supported")

        world.landingY = 900 // the window closed -- nothing until the floor
        state.update(dt: 0.1, context: world.context)

        XCTAssertEqual(world.requestedTransitions, [.fall])
    }

    func test_stillSupported_doesNotRequestFall() {
        let world = TestStateWorld(position: CGPoint(x: 400, y: 500))
        world.landingY = 500
        let state = IdleState()

        world.run(state, seconds: 5) // below the scheduler's 8s minimum interval

        XCTAssertTrue(world.requestedTransitions.isEmpty)
    }

    /// Clicking the chat window used to drop the pet into the middle of it:
    /// the window covered the edge the pet was standing on, so the surface
    /// read as gone, and the floor it fell to was covered by that same window
    /// -- the pet draws above every window, so it just moved from one hidden
    /// spot to a more annoying one (2026-08-22).
    func test_theSurfaceGoingBehindAWindow_asksTheDelegateInsteadOfFalling() {
        let world = TestStateWorld(position: CGPoint(x: 400, y: 200))
        world.avatarHeight = 120
        world.landingY = 900
        world.windows = [Self.window(CGRect(x: 0, y: 40, width: 1000, height: 900))]
        let delegate = SpyWanderDelegate()
        let state = IdleState()
        state.wanderDelegate = delegate

        state.update(dt: 0.1, context: world.context)

        XCTAssertTrue(world.requestedTransitions.isEmpty, "falling behind the window helps nobody")
        XCTAssertEqual(delegate.lostFootingBehind.map(\.windowID), [1])
    }

    /// The window actually closing is still a fall: nothing covers where the
    /// pet would land, so landing there is visible and correct.
    func test_theSurfaceSimplyDisappearing_stillFalls() {
        let world = TestStateWorld(position: CGPoint(x: 400, y: 200))
        world.avatarHeight = 120
        world.landingY = 900
        world.windows = [Self.window(CGRect(x: 0, y: 40, width: 100, height: 900))]
        let delegate = SpyWanderDelegate()
        let state = IdleState()
        state.wanderDelegate = delegate

        state.update(dt: 0.1, context: world.context)

        XCTAssertEqual(world.requestedTransitions, [.fall])
        XCTAssertTrue(delegate.lostFootingBehind.isEmpty)
    }
}
