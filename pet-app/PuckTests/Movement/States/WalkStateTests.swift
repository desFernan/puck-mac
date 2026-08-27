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
    /// One rect per display. Left empty by default -- one screen, which is
    /// what every test that doesn't say otherwise means -- and the context
    /// falls back to `roamableArea` for it.
    var roamableAreas: [CGRect] = []
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
    /// The camera housing, on the machines that have one.
    var notch: ScreenNotch?

    init(position: CGPoint = .zero) {
        body = CharacterBody(avatar: avatar, position: position)
    }

    var context: StateContext {
        StateContext(
            body: body,
            roamableArea: roamableArea,
            roamableAreas: roamableAreas,
            notch: notch,
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

    // MARK: - Two displays

    /// The pet walking toward the space beside a shorter monitor is walking
    /// off the world -- there is no screen there and nothing would draw it.
    func test_stopsAtTheEdgeOfTheDisplays_ratherThanWalkingIntoTheGap() {
        let world = TestStateWorld(position: CGPoint(x: 900, y: 500))
        // A second display to the right whose floor is 100 higher: everything
        // below that line, beyond x = 1000, is on no screen.
        world.roamableAreas = [
            CGRect(x: 0, y: 0, width: 1000, height: 500),
            CGRect(x: 1000, y: 0, width: 800, height: 400),
        ]
        world.roamableArea = ScreenGround.union(world.roamableAreas)
        let state = WalkState()
        state.target = CGPoint(x: 1700, y: 500)

        world.run(state, seconds: 3)

        XCTAssertLessThanOrEqual(
            world.body.position.x + world.visualBounds.maxX, 1000,
            "the pet's whole drawing should still be on the first display"
        )
        XCTAssertEqual(world.requestedTransitions.first, .idle)
    }

    /// ...unless it can climb up onto that display, which is the only way
    /// back once it has come down the other way.
    func test_climbsTheLedgeWhenTheDisplayAheadIsHigher() {
        let world = TestStateWorld(position: CGPoint(x: 900, y: 500))
        world.roamableAreas = [
            CGRect(x: 0, y: 0, width: 1000, height: 500),
            CGRect(x: 1000, y: 0, width: 800, height: 400),
        ]
        world.roamableArea = ScreenGround.union(world.roamableAreas)
        let ledge = ClimbLedgeState()
        let state = WalkState()
        state.climbLedgeState = ledge
        state.target = CGPoint(x: 1700, y: 500)

        world.run(state, seconds: 3)

        XCTAssertEqual(world.requestedTransitions.first, .climbLedge)
        XCTAssertEqual(ledge.target?.y, 400, "onto the higher display's floor")
        XCTAssertEqual(ledge.target?.x, 1050, "far enough in that all of the pet lands on it")
    }

    /// The other direction is a fall, not a stop: the floor under the pet's
    /// next step is lower than the one it is on.
    func test_fallsWhenItWalksOntoADisplayWithALowerFloor() {
        let world = TestStateWorld(position: CGPoint(x: 1100, y: 400))
        world.roamableAreas = [
            CGRect(x: 0, y: 0, width: 1000, height: 500),
            CGRect(x: 1000, y: 0, width: 800, height: 400),
        ]
        world.roamableArea = ScreenGround.union(world.roamableAreas)
        let state = WalkState()
        state.target = CGPoint(x: 200, y: 400)

        world.run(state, seconds: 3)

        XCTAssertEqual(world.requestedTransitions.first, .fall)
    }

    func test_arrivalIsRequestedOnlyOnce() {
        let world = TestStateWorld(position: CGPoint(x: 0, y: 100))
        let state = WalkState()
        state.target = CGPoint(x: 5, y: 100)

        world.run(state, seconds: 2)

        XCTAssertEqual(world.requestedTransitions.count, 1, "one arrival, one request")
    }
}
