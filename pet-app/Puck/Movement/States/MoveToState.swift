//
//  MoveToState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  MoveTo state's StateHandler implementation
//
//  A directed move ordered by a tool or a socket event ("임의 | 도구/이벤트
//  목표좌표 | MoveTo → Point 또는 Idle", plan/02_pet-app.md section 3).
//
//  Unlike Walk it deliberately ignores windows in the way: the pet was sent
//  somewhere specific, and stopping to climb something on the route would
//  abandon the order. Reuses the "walk" clip; the manifest has no dedicated one.

import CoreGraphics
import Foundation

final class MoveToState: StateHandler {
    let name = "MoveTo"
    let clipKey = "walk"
    let loopsClip = true

    /// Where to go, in the pet's coordinate space.
    var target: CGPoint?
    /// What to do on arrival. point_at sets this to `.point`; a plain
    /// relocation leaves it at `.idle`.
    var nextState: StateKind = .idle

    private var oneShot = OneShotTransition()

    func enter() {
        oneShot.reset()
    }

    func exit() {
        // Clear both so a stale order can't be replayed on the next entry.
        target = nil
        nextState = .idle
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !oneShot.hasFired else { return }

        guard let target else {
            oneShot.fire(.idle, using: context.requestTransition)
            return
        }

        if let facing = MovementSolver.facing(from: context.body.position, toward: target) {
            context.body.facing = facing
        }

        let step = MovementSolver.step(from: context.body.position, toward: target, speed: context.walkSpeed, dt: dt)
        context.body.position = step.position

        if step.hasArrived {
            oneShot.fire(nextState, using: context.requestTransition)
        }
    }
}
