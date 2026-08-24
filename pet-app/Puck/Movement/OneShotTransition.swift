//
//  OneShotTransition.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Guards a state that must request its transition exactly once.
//
//  Nearly every state (arrival at a target, a timer elapsing) used to
//  hand-roll the identical "private Bool flag + guard + requestTransition"
//  shape under a different field name each time (hasRequestedIdle,
//  hasRequestedFall, hasHandedOver, ...) -- found via review. One shared
//  type instead of ~14 copies that could drift.
//

import Foundation

struct OneShotTransition {
    private(set) var hasFired = false

    /// Call from `enter()` so re-entering the state can fire again.
    mutating func reset() {
        hasFired = false
    }

    /// Requests `kind`, but only the first time this is called since the last
    /// `reset()`.
    mutating func fire(_ kind: StateKind, using requestTransition: (StateKind) -> Void) {
        guard !hasFired else { return }
        hasFired = true
        requestTransition(kind)
    }
}
