//
//  IdleFrameRatePolicy.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Decides when the frame loop may slow down.
//
//  The current CALayer renderer still needs ticks for FSM movement, toy
//  physics, pointing and idle timers. The policy therefore uses a bounded 2D
//  heartbeat rather than claiming a fully event-driven loop: 30 Hz while the
//  pet is active and 15 Hz after a sustained idle period.
//

import Foundation

struct IdleFrameRatePolicy {
    /// How long the pet must have been idle before slowing down.
    let threshold: TimeInterval

    private var idleElapsed: TimeInterval = 0

    init(threshold: TimeInterval = 30) {
        self.threshold = threshold
    }

    /// - Parameter idle: whether the FSM is currently in a resting state.
    /// - Returns: the rate the clock should run at this frame.
    mutating func framesPerSecond(idle: Bool, dt: TimeInterval) -> Double {
        guard idle else {
            // Back to the active rate immediately — ramping up a second later
            // would show as a stutter exactly when something is happening.
            idleElapsed = 0
            return FrameClock.activeFramesPerSecond
        }
        idleElapsed += dt
        return idleElapsed >= threshold ? FrameClock.idleFramesPerSecond : FrameClock.activeFramesPerSecond
    }
}
