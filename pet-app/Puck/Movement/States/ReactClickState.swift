//
//  ReactClickState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  ReactClick state's StateHandler implementation.
//
//  A short reaction to being clicked, then back to whatever the pet was doing
//  ("임의 | 캐릭터 클릭 | ReactClick → Idle").
//  Also reused as the failure reaction for tool_result(ok=false) — see
//  EventRouter.
//

import Foundation

final class ReactClickState: StateHandler {
    let name = "ReactClick"
    let clipKey = "react_click"
    let loopsClip = false
    // Clicking the pet again while it's still reacting should replay the
    // reaction (see enter()'s comment) -- without this, CharacterController's
    // same-state no-op guard silently swallowed the repeated transition.
    let restartsOnReentry = true

    /// Long enough for the non-looping clip to read.
    static let duration: TimeInterval = 0.6

    private var elapsed: TimeInterval = 0
    private var oneShot = OneShotTransition()

    func enter() {
        // Restart on re-entry: clicking the pet again replays the reaction
        // rather than inheriting the previous one's remaining time.
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
