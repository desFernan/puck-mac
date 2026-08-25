//
//  WalkState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Walk state's StateHandler implementation.
//
//  Carries the pet to `target` at constant speed and hands back to Idle on
//  arrival (plan/02_pet-app.md section 3). Whoever transitions into Walk sets
//  the target first — Idle's wander does so via IdleWanderDelegate.
//
//  A window standing in the path is walked up to and then climbed, rather
//  than walked through (section 3: "Walk | 창 좌/우 모서리 접촉 | Climb").

import CoreGraphics
import Foundation

final class WalkState: StateHandler {
    let name = "Walk"
    let clipKey = "walk"
    let loopsClip = true

    /// Where to walk, in GlobalScreenSpace pixels. Cleared on exit so a stale
    /// destination can't be re-walked next time Walk is entered.
    var target: CGPoint?

    /// Where the walk hands over when it runs out of floor and the display
    /// ahead has a higher one. Nil with a single display, where that cannot
    /// happen -- the walk simply stops at the edge.
    weak var climbLedgeState: ClimbLedgeState?

    private var oneShot = OneShotTransition()

    func enter() {
        oneShot.reset()
    }

    func exit() {
        target = nil
    }

    func update(dt: TimeInterval, context: StateContext) {
        // One arrival, one request: the transition only lands after this
        // update returns, so further frames would queue duplicates.
        guard !oneShot.hasFired else { return }

        guard let target else {
            // Nothing to walk to — looping the walk clip on the spot would
            // read as the pet moonwalking.
            oneShot.fire(.idle, using: context.requestTransition)
            return
        }

        // A walk is along the ground the pet is already standing on: only
        // the target's x is walked to. Its y is where the *target* stands,
        // which on another display is a different floor -- walking at it
        // directly would take the pet diagonally through the air on the way
        // there. Coming down onto a lower display is a fall, and going up
        // onto a higher one is a climb; both are decided below, per step.
        let alongTheGround = CGPoint(x: target.x, y: context.body.position.y)
        if let facing = MovementSolver.facing(from: context.body.position, toward: alongTheGround) {
            context.body.facing = facing
        }

        // A window in the way is what starts a climb — the pet walks up to its
        // side rather than through it (section 3: "Walk | 창 좌/우 모서리 접촉 | Climb").
        if let blocking = WindowSupport.blockingWindow(
            walkingFrom: context.body.position, toward: alongTheGround, in: context.windows,
            // The headroom above a window is measured against the display it
            // is on, not the box around every display.
            roamableTop: context.area(at: context.body.position).minY, avatarHeight: context.avatarHeight,
            excluding: context.unclimbableWindowIDs
        ) {
            let edgeX = alongTheGround.x > context.body.position.x ? blocking.frame.minX : blocking.frame.maxX
            let step = MovementSolver.step(
                from: context.body.position,
                toward: CGPoint(x: edgeX, y: context.body.position.y),
                speed: context.walkSpeed,
                dt: dt
            )
            context.body.position = step.position
            if step.hasArrived {
                oneShot.fire(.climb, using: context.requestTransition)
            }
            return
        }

        let step = MovementSolver.step(from: context.body.position, toward: alongTheGround, speed: context.walkSpeed, dt: dt)

        // The end of the world, which with two displays is not the end of the
        // roamable box: the next step can land in the space beside a shorter
        // monitor, which is on no screen at all. The pet's own outline decides
        // where that edge is, so it stops with all of itself still visible
        // rather than half over the void.
        guard context.artworkHasGround(at: step.position) else {
            let direction: CGFloat = target.x >= context.body.position.x ? 1 : -1
            if let ledge = climbLedgeState,
               let landing = context.ledge(beyond: context.body.position, directionX: direction) {
                ledge.target = landing
                oneShot.fire(.climbLedge, using: context.requestTransition)
            } else {
                // Nothing to climb: this really is the edge of everything.
                // Idle, not the walk clip against a wall forever.
                oneShot.fire(.idle, using: context.requestTransition)
            }
            return
        }

        // Walked onto a display whose floor is lower than the one just left.
        // Nothing else notices until the pet next stands still, and until
        // then it is walking through mid-air over the other monitor.
        let floorAhead = context.area(at: step.position).maxY
        let floorHere = context.area(at: context.body.position).maxY
        context.body.position = step.position
        if floorAhead > floorHere + WindowSupport.footTolerance {
            oneShot.fire(.fall, using: context.requestTransition)
            return
        }

        if step.hasArrived {
            oneShot.fire(.idle, using: context.requestTransition)
        }
    }
}
