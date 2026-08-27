//
//  PetStates.swift
//  Puck
//
//  The one long-lived instance of every state the pet can be in, and the
//  table that hands them to the controller.
//
//  One instance per state, reused for every transition into it.
//  CharacterController's same-state no-op guard is reference equality
//  (StateHandler is AnyObject), so constructing a fresh one per transition
//  (`IdleState()` each time) silently defeats it -- which reset IdleState's
//  wander timer and replayed its clip and its sound on every repeated
//  same-kind event.
//
//  They were twenty-two properties on the app delegate, declared where all
//  eighteen of its extensions can see them and read by one or two each, and
//  the table that registers them was written out a second time in the middle
//  of building the avatar. A StateKind nobody put in that table is not a
//  build error -- it is a line in the log at the moment somebody transitions
//  to it -- so the table lives here with a test that walks every case.
//

import Foundation

@MainActor
final class PetStates {
    // One shared instance per FSM state, reused for every transition into it.
    // CharacterController.transition's same-state no-op guard is reference
    // equality (StateHandler: AnyObject) -- constructing a fresh instance per
    // transition (e.g. `IdleState()` each time) defeated that guard, silently
    // resetting IdleState's WanderScheduler timer and replaying loop clip/SFX
    // on every repeated same-kind event.
    let idle = IdleState()

    let walk = WalkState()

    let climb = ClimbState()

    /// The step between two displays of different heights -- see
    /// ClimbLedgeState. Idle on a single-display machine, where WalkState
    /// never finds a ledge to hand it.
    let climbLedge = ClimbLedgeState()

    let walkOnTop = WalkOnTopState()

    let fall = FallState()

    let land = LandState()

    let moveTo = MoveToState()

    let travel = TravelState()

    let type = TypeState()

    let point = PointState()

    let listen = ListenState()

    let reactClick = ReactClickState()

    let reactDrag = ReactDragState()

    // Double-tap "petting" interaction (2026-07-29, more interactions).
    let petting = PettingState()

    let spin = SpinState()

    // F13 (2026-07-29): Option+Shift+Space pins the character while the
    // client window is open, same "capture then restore" pattern as
    // stateBeforeListen below.
    let pinned = PinnedState()

    // F3 ceiling-crawling (2026-07-29): WanderScheduler's .climbToCeiling outcome.
    let climbToCeiling = ClimbToCeilingState()

    let ceiling = CeilingState()

    // F12 (optional, lowest priority): ball-toy interaction.
    let chaseBall = ChaseBallState()

    let juggleBall = JuggleBallState()

    let kickBall = KickBallState()

    /// Every kind, and the instance that serves it.
    ///
    /// A dictionary rather than a switch so the test can compare its keys
    /// against StateKind.allCases; a switch would be exhaustive at compile
    /// time but says nothing about a case mapped to the wrong instance.
    var byKind: [StateKind: StateHandler] {
        [
            .idle: idle,
            .walk: walk,
            .climb: climb,
            .climbLedge: climbLedge,
            .walkOnTop: walkOnTop,
            .fall: fall,
            .land: land,
            .moveTo: moveTo,
            .travel: travel,
            .type: type,
            .point: point,
            .listen: listen,
            .reactClick: reactClick,
            .reactDrag: reactDrag,
            .petting: petting,
            .spin: spin,
            .pinned: pinned,
            .kickBall: kickBall,
            .climbToCeiling: climbToCeiling,
            .ceiling: ceiling,
            .chaseBall: chaseBall,
            .juggleBall: juggleBall,
        ]
    }

    /// Hands the lot to a freshly built controller.
    func register(in controller: CharacterController) {
        for (kind, state) in byKind {
            controller.register(state, as: kind)
        }
    }
}
