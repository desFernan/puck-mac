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

        if let facing = MovementSolver.facing(from: context.body.position, toward: target) {
            context.body.facing = facing
        }

        // A window in the way is what starts a climb — the pet walks up to its
        // side rather than through it (section 3: "Walk | 창 좌/우 모서리 접촉 | Climb").
        if let blocking = WindowSupport.blockingWindow(
            walkingFrom: context.body.position, toward: target, in: context.windows,
            roamableTop: context.roamableArea.minY, avatarHeight: context.avatarHeight,
            excluding: context.unclimbableWindowIDs
        ) {
            let edgeX = target.x > context.body.position.x ? blocking.frame.minX : blocking.frame.maxX
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

        let step = MovementSolver.step(from: context.body.position, toward: target, speed: context.walkSpeed, dt: dt)
        context.body.position = step.position

        if step.hasArrived {
            oneShot.fire(.idle, using: context.requestTransition)
        }
    }
}
