//
//  ClimbLedgeState.swift
//  Puck
//
//  Climbing the step between two displays.
//
//  Monitors of different heights are a one-way trip without this: walking
//  onto the lower one is a fall, and a walk has no way back up. The pet ends
//  up living on the short monitor and never returns to the one being worked
//  on.
//
//  The climb itself is ClimbState's -- straight up at walking speed, on the
//  climb clip. What differs is what is being climbed: ClimbState rides the
//  side of a window (and gives up the moment that window goes away), and
//  there is no window here, only the edge of a display.
//
//  Two moves rather than one diagonal: going up and across at the same time
//  leaves half the pet hanging in the space beside the display it is
//  climbing to, i.e. visibly cut in half for the length of the climb.
//

import CoreGraphics
import Foundation

final class ClimbLedgeState: StateHandler {
    let name = "ClimbLedge"
    let clipKey = "climb"
    let loopsClip = true

    /// Where to stand once up. Filled in by WalkState on the frame it runs
    /// out of floor, and cleared on exit so a stale ledge can't be re-climbed.
    var target: CGPoint?

    private var hasReachedHeight = false
    private var oneShot = OneShotTransition()

    func enter() {
        oneShot.reset()
        hasReachedHeight = false
    }

    func exit() {
        target = nil
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !oneShot.hasFired else { return }
        guard let target else {
            oneShot.fire(.idle, using: context.requestTransition)
            return
        }

        if !hasReachedHeight {
            // Straight up, and no facing change: the same rule ClimbState
            // has, for the same reason -- a pet that flips halfway up a wall
            // reads as it losing its grip.
            let top = CGPoint(x: context.body.position.x, y: target.y)
            let step = MovementSolver.step(from: context.body.position, toward: top, speed: context.walkSpeed, dt: dt)
            // A ledge is a specific height, not "about that height": inside
            // the arrival radius MovementSolver returns the position
            // unchanged, and stepping across from a few pixels short leaves
            // the pet standing that far into the display's edge.
            context.body.position = step.hasArrived ? top : step.position
            hasReachedHeight = step.hasArrived
            return
        }

        if let facing = MovementSolver.facing(from: context.body.position, toward: target) {
            context.body.facing = facing
        }
        let step = MovementSolver.step(from: context.body.position, toward: target, speed: context.walkSpeed, dt: dt)
        context.body.position = step.hasArrived ? target : step.position

        if step.hasArrived {
            oneShot.fire(.idle, using: context.requestTransition)
        }
    }
}
