//
//  ClimbToCeilingState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  ClimbToCeiling state's StateHandler implementation.
//
//  F3 ceiling-crawling (2026-07-29): climbs straight up to the roamable
//  area's top edge. Requires an actual window edge underfoot, the same way
//  ClimbState does (WindowSupport.windowBeingClimbed, re-checked every
//  frame) -- climbing must only ever happen via a real on-screen wall, not
//  from arbitrary terrain (it used to climb from anywhere). A wall that doesn't reach near the
//  ceiling just gets climbed as far as it goes, then falls, same as running
//  out of window climbing ClimbState's own wall.
//

import CoreGraphics
import Foundation

final class ClimbToCeilingState: StateHandler {
    let name = "ClimbToCeiling"
    let clipKey = "climb"
    let loopsClip = true

    private var oneShot = OneShotTransition()

    func enter() {
        oneShot.reset()
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !oneShot.hasFired else { return }

        // Without `excluding:` -- see ClimbState for why an in-progress
        // climb is not re-decided by a setting about starting one.
        guard WindowSupport.hasWall(
            at: context.body.position,
            visualBounds: context.visualBounds,
            in: context.windows,
            area: context.area(at: context.body.position)
        ) else {
            // No wall here (or climbed past the top of a short one) --
            // there's nothing left to hold onto.
            oneShot.fire(.fall, using: context.requestTransition)
            return
        }

        // Straight up: x stays fixed, same "no facing change mid-climb" rule
        // ClimbState uses. The target is roamableArea.minY + avatarHeight,
        // NOT roamableArea.minY itself -- position is still the feet here
        // (right-side-up, body extending upward), so climbing feet all the
        // way to the literal top of the screen would push the head off-screen
        // before "arrival." Stopping with the head just touching the ceiling
        // also makes this land on exactly the same rendered rect CeilingState
        // computes for position.y == roamableArea.minY once it flips upside
        // down, so the flip reads as an in-place turn, not a jump.
        // The top of the display being climbed on, not of the box around
        // every display -- see CeilingState, which this hands over to.
        let ceiling = context.ceilingY(
            atX: context.body.position.x,
            on: context.area(at: context.body.position)
        )
        let target = CGPoint(x: context.body.position.x, y: ceiling + context.avatarHeight)
        let step = MovementSolver.step(from: context.body.position, toward: target, speed: context.walkSpeed, dt: dt)
        context.body.position = step.position

        if step.hasArrived {
            oneShot.fire(.ceiling, using: context.requestTransition)
        }
    }
}
