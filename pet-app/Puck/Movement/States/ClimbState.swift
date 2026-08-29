//
//  ClimbState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Climb state's StateHandler implementation.
//
//  Rides a window's side up to its top edge, then walks along it
//  ("Climb | 창 상단 도달 | WalkOnTop").
//

import CoreGraphics
import Foundation

final class ClimbState: StateHandler {
    let name = "Climb"
    let clipKey = "climb"
    let loopsClip = true

    private var oneShot = OneShotTransition()

    func enter() {
        oneShot.reset()
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !oneShot.hasFired else { return }

        // No `excluding:` here, deliberately. That set is "windows the pet
        // may not start climbing", resolved fresh each frame from whichever
        // app is frontmost -- so passing it here made clicking the window the
        // pet was already on halfway up drop it off the side. Whether a wall
        // is *there* is this check's business; whether it was allowed to be
        // climbed was WalkState's, one transition ago.
        guard let window = WindowSupport.windowBeingClimbed(
            at: context.body.position,
            in: context.windows
        ) else {
            // The window went away mid-climb — there is nothing to hold on to.
            oneShot.fire(.fall, using: context.requestTransition)
            return
        }

        // Straight up: no facing change, or the character flips partway up.
        let target = CGPoint(x: context.body.position.x, y: window.frame.minY)
        let step = MovementSolver.step(from: context.body.position, toward: target, speed: context.walkSpeed, dt: dt)
        context.body.position = step.position

        if step.hasArrived {
            oneShot.fire(.walkOnTop, using: context.requestTransition)
        }
    }
}
