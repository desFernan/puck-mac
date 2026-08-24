//
//  LandState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Land state's StateHandler implementation
//
//  A brief landing beat so the non-looping land clip is legible, then Idle
//  (plan/02_pet-app.md section 3: "Fall | 착지면 감지 | Land → Idle").
//

import Foundation

final class LandState: StateHandler {
    let name = "Land"
    let clipKey = "land"
    let loopsClip = false

    /// Long enough to read as a landing, short enough not to feel stuck.
    static let duration: TimeInterval = 0.35

    private var elapsed: TimeInterval = 0
    private var oneShot = OneShotTransition()

    func enter() {
        elapsed = 0
        oneShot.reset()
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !oneShot.hasFired else { return }
        elapsed += dt
        guard elapsed >= Self.duration else { return }
        oneShot.fire(.idle, using: context.requestTransition)
    }
}
