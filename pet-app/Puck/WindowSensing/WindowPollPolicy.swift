//
//  WindowPollPolicy.swift
//  Puck
//
//  How often the window list is worth asking for.
//
//  Asking is not cheap: CGWindowListCopyWindowInfo builds an array of
//  dictionaries for every window on screen, and a sample of the running pet
//  found that one call, ten times a second, was most of what the app was
//  doing at rest -- 218 of the 242 main-thread samples that were not simply
//  waiting for an event.
//
//  Ten times a second is the right answer while something is happening. The
//  pet stands on window tops, and a window can be dragged or resized without
//  posting any notification at all, so a walking pet really does need to be
//  told where the edges are. A pet that has been sitting still for a minute
//  does not: nothing it is doing depends on the answer, and the moment it
//  starts moving again the rate goes back up before the first step lands.
//
//  The same shape as IdleFrameRatePolicy, and for the same reason -- there is
//  no event to wait for, so this is a heartbeat that slows down rather than a
//  subscription.
//

import Foundation

struct WindowPollPolicy {
    /// While anything is happening: a walk, a fall, a climb, a toy in the air.
    static let activeHz: Double = 10
    /// After an app activates, launches or quits -- the window list is about
    /// to change and the pet should react to it, not a tenth of a second
    /// later.
    static let burstHz: Double = 15
    /// Once the pet has been still long enough that nothing depends on the
    /// answer. Not zero: a window moved while the pet rests on it still has
    /// to be noticed, just not within a tenth of a second.
    static let restingHz: Double = 2

    /// How long the pet must have been still before slowing down.
    ///
    /// Shorter than the frame loop's, because nothing visible depends on it:
    /// the rate decides how quickly the pet notices a window that moved under
    /// it while it was sitting, and half a second is not a delay anybody
    /// sees. Measured against the eight-to-fifteen seconds the wander
    /// scheduler waits between draws -- a threshold longer than that is a
    /// threshold that never fires, which is what this policy replaced.
    let threshold: TimeInterval

    private var restingElapsed: TimeInterval = 0

    init(threshold: TimeInterval = 3) {
        self.threshold = threshold
    }

    /// - Parameters:
    ///   - resting: whether the pet is in a state that does not read the
    ///     window list -- idle on a surface, or put away.
    ///   - bursting: whether an app just activated, launched or quit.
    /// - Returns: the rate to poll at this moment.
    mutating func hertz(resting: Bool, bursting: Bool, dt: TimeInterval) -> Double {
        guard resting else {
            // Straight back up. Ramping would mean the first step of a walk
            // is taken against a window list from the resting rate, which is
            // the one case that matters.
            restingElapsed = 0
            return bursting ? Self.burstHz : Self.activeHz
        }
        // A burst outranks resting: the window list is changing right now,
        // which is the whole reason the burst exists.
        guard !bursting else { return Self.burstHz }
        restingElapsed += dt
        return restingElapsed >= threshold ? Self.restingHz : Self.activeHz
    }
}
