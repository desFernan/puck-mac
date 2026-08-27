//
//  WanderRun.swift
//  Puck
//
//  The legs of one wander, and the beat between them.
//
//  A wander is one to three walks with a pause in between, not one straight
//  line to one point -- the pet stopping to look at something is most of what
//  makes it read as wandering rather than as travelling. Nothing reports an
//  arrival, so the countdown is driven from the frame loop, which is why this
//  is a state machine rather than a timer.
//
//  It was two properties on the app delegate and a countdown written inline
//  in the frame-loop callback. Both were touched by one file, and the one
//  thing worth being sure of -- that a wander with two legs left walks twice
//  and then stops -- had no way to be asserted.
//

import CoreGraphics
import Foundation

struct WanderRun {
    /// How many walks are still to come after the one in progress.
    private(set) var legsRemaining = 0
    /// How long until the next one starts.
    private(set) var pause: TimeInterval = 0
    /// Where the pet is wandering, which decides both of the draws.
    private var atHome = false

    var isRunning: Bool { legsRemaining > 0 }

    /// Begins a wander. The first leg is the caller's to start; this counts
    /// the ones after it.
    mutating func begin(atHome: Bool) {
        self.atHome = atHome
        legsRemaining = Self.drawLegs(atHome: atHome) - 1
        pause = Self.drawPause(atHome: atHome)
    }

    /// One frame of the beat between legs.
    ///
    /// - Returns: true when the next leg starts now.
    mutating func tick(dt: TimeInterval) -> Bool {
        guard legsRemaining > 0 else { return false }
        pause -= dt
        guard pause <= 0 else { return false }
        legsRemaining -= 1
        pause = Self.drawPause(atHome: atHome)
        return true
    }

    /// Drops whatever legs are left. Anything that takes the pet over --
    /// another wander outcome, a tool, a fall behind a window -- calls this,
    /// or the pet resumes a walk nobody asked for any more.
    mutating func cancel() {
        legsRemaining = 0
        pause = 0
    }

    /// Mostly one leg, sometimes two, now and then three. More than that and
    /// the pet never settles.
    ///
    /// On the island it walks further per wander: the shelf is small enough
    /// that one leg of it is barely a step, and the pet is being watched
    /// there rather than glanced at.
    nonisolated static func drawLegs(atHome: Bool = false, roll: CGFloat = .random(in: 0...1)) -> Int {
        if atHome {
            if roll < 0.3 { return 2 }
            return roll < 0.75 ? 3 : 4
        }
        if roll < 0.55 { return 1 }
        return roll < 0.85 ? 2 : 3
    }

    /// Long enough to read as the pet stopping to look at something, short
    /// enough that the walk still feels like one wander. Shorter on the
    /// island, where the legs themselves are short.
    nonisolated static func drawPause(atHome: Bool = false) -> TimeInterval {
        atHome ? .random(in: 0.2...0.7) : .random(in: 0.4...1.4)
    }
}
