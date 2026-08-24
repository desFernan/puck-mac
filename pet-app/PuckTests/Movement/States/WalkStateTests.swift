//
//  WalkStateTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Walk carries the pet to a target at constant speed and hands back to Idle
//  on arrival (plan/02_pet-app.md section 3 transition table).
//

import XCTest
@testable import Puck

/// Minimal AvatarPlayable so a state can be driven without RealityKit.
final class RecordingAvatar: AvatarPlayable {
    private(set) var positions: [CGPoint] = []
    private(set) var facings: [AvatarFacing] = []
    func play(clip: String, loop: Bool) {}
    func stop() {}
    func setScreenPosition(_ position: CGPoint) { positions.append(position) }
    func setFacing(_ facing: AvatarFacing) { facings.append(facing) }
}

/// Builds a StateContext around a body, recording transition requests.
final class TestStateWorld {
    let avatar = RecordingAvatar()
    let body: CharacterBody
    private(set) var requestedTransitions: [StateKind] = []
    var roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 500)
    var avatarHeight: CGFloat = 0
    /// A pet with real extent by default: the screen-edge limits every
    /// containment/bounce test exercises are measured from this, and a zero
    /// rect would silently put them back on the old centre-point behaviour.
    var visualBounds = CGRect(x: -50, y: -120, width: 100, height: 120)
    var walkSpeed: CGFloat = MovementSolver.walkSpeed
    var landingY: CGFloat = 500
    var windows: [WindowInfo] = []
    /// Settings' "포커스된 창 위로는 올라가지 않기", as WalkState sees it.
    var unclimbableWindowIDs: Set<CGWindowID> = []

    init(position: CGPoint = .zero) {
        body = CharacterBody(avatar: avatar, position: position)
    }

    var context: StateContext {
        StateContext(
            body: body,
            roamableArea: roamableArea,
            avatarHeight: avatarHeight,
            visualBounds: visualBounds,
            walkSpeed: walkSpeed,
            windows: windows,
            unclimbableWindowIDs: unclimbableWindowIDs,
            landingY: { [landingY] _ in landingY },
            requestTransition: { [weak self] kind in self?.requestedTransitions.append(kind) }
        )
    }

    /// Runs `seconds` of frames at 60fps.
    ///
    /// `@MainActor` because a state is: this stands in for the frame loop,
    /// which is a hop onto the main thread.
    @MainActor
    func run(_ state: StateHandler, seconds: TimeInterval) {
        let frame = 1.0 / 60
        var elapsed: TimeInterval = 0
        while elapsed < seconds {
            state.update(dt: frame, context: context)
            elapsed += frame
        }
    }
}

/// `@MainActor`: the character and its states belong to the main thread,
/// which is where the frame loop drives them.
@MainActor
final class WalkStateTests: XCTestCase {
    func test_walksTowardTheTarget() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 100))
        let state = WalkState()
        state.target = CGPoint(x: 500, y: 100)

        world.run(state, seconds: 1)

        XCTAssertGreaterThan(world.body.position.x, 0, "the pet should have moved toward the target")
        XCTAssertLessThan(world.body.position.x, 500, "and not teleported to it in one second")
    }

    func test_facesTheDirectionOfTravel() {
        let world = TestStateWorld(position: CGPoint(x: 500, y: 100))
        let state = WalkState()
        state.target = CGPoint(x: 0, y: 100)

        world.run(state, seconds: 0.1)

        XCTAssertEqual(world.avatar.facings.last, .left)
    }

    func test_returnsToIdleOnArrival() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 100))
        let state = WalkState()
        state.target = CGPoint(x: 20, y: 100)

        world.run(state, seconds: 3)

        XCTAssertEqual(world.requestedTransitions.first, .idle)
        // "도착 반경" (plan section 3): arriving means being within the radius,
        // not landing exactly on the point. Snapping the last couple of pixels
        // would be a visible teleport at no benefit.
        XCTAssertEqual(world.body.position.x, 20, accuracy: MovementSolver.arrivalRadius)
    }

    /// Without a target there is nowhere to go; standing in Walk forever would
    /// loop the walk clip on the spot.
    func test_withoutATarget_returnsToIdleImmediately() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 100))
        let state = WalkState()

        world.run(state, seconds: 0.1)

        XCTAssertEqual(world.requestedTransitions.first, .idle)
    }

    /// Settings' movement-speed slider.
    func test_respectsACustomWalkSpeed() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 100))
        world.walkSpeed = MovementSolver.walkSpeed * 2
        let state = WalkState()
        state.target = CGPoint(x: 1000, y: 100)

        world.run(state, seconds: 1)

        XCTAssertEqual(world.body.position.x, MovementSolver.walkSpeed * 2, accuracy: 1)
    }

    func test_arrivalIsRequestedOnlyOnce() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 100))
        let state = WalkState()
        state.target = CGPoint(x: 5, y: 100)

        world.run(state, seconds: 2)

        XCTAssertEqual(world.requestedTransitions.count, 1, "one arrival, one request")
    }
}
