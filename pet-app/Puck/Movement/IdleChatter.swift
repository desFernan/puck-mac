//
//  IdleChatter.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  The occasional unprompted voice line while the pet is standing around.
//
//  Every other sound in the app is a *reaction* -- to a state entry, a click,
//  a tool result. A pet that only ever speaks when something happens to it
//  goes silent for minutes at a time, so this is the one timer-driven trigger: while Idle, every
//  now and then, it says one of whatever lines the avatar happens to carry.
//
//  Which lines those are is the avatar's business, not this file's: the keys
//  come from the manifest's own `sounds` table (everything under the
//  `chatter_` prefix), so an avatar with none simply never chatters and one
//  with ten draws from all ten. Same shape as WanderScheduler, which is the
//  other "wait a random while, then pick something" timer in the FSM.
//

import Foundation

final class IdleChatter {
    /// Long enough that the pet reads as quiet-with-occasional-remarks rather
    /// than talkative. A range, not a fixed interval, for WanderScheduler's
    /// reason: a metronomic pet is the thing these timers exist to avoid.
    static let defaultIntervalRange: ClosedRange<TimeInterval> = 30...75

    /// Sound-table keys to draw from. Set at bootstrap from the loaded
    /// manifest; empty means this avatar has no chatter and the timer never
    /// produces anything.
    var keys: [String] = []

    private var elapsed: TimeInterval = 0
    private var nextFireInterval: TimeInterval
    private let nextIntervalProvider: () -> TimeInterval

    init(nextIntervalProvider: @escaping () -> TimeInterval = { .random(in: IdleChatter.defaultIntervalRange) }) {
        self.nextIntervalProvider = nextIntervalProvider
        nextFireInterval = nextIntervalProvider()
    }

    /// Accumulates dt; returns a sound key once the timer expires, then draws
    /// its next interval. Only call this while the pet is actually idle --
    /// the timer is not meant to run down during a walk or a tool run.
    func tick(dt: TimeInterval) -> String? {
        elapsed += dt
        guard elapsed >= nextFireInterval else { return nil }
        elapsed = 0
        nextFireInterval = nextIntervalProvider()
        return keys.randomElement()
    }
}
