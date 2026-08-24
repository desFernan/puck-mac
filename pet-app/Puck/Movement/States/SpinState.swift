//
//  SpinState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The happy flips the pet does after being petted, for a while afterward.
//  It turns about its own vertical axis, like a sheet of paper
//  being turned over repeatedly -- not an in-plane rotation, which tips the
//  pet sideways and reads as falling over.
//
//  Purely a rendering effect -- the pet stays exactly where it is -- so this
//  state owns only the timing, and the flipping itself comes from
//  BouncePreset.spin driven by the elapsed time CharacterController already
//  feeds the avatar every frame. No new per-frame plumbing.
//
//  Has its own clip key rather than reusing "pet": BouncePreset is looked up
//  BY clip key, so sharing one would mean sharing the wiggle too. The
//  manifest points "spin" at the same artwork as "pet" -- the blissed-out
//  face from being stroked is what should be whirling around.
//

import Foundation

final class SpinState: StateHandler {
    let name = "Spin"
    let clipKey = "spin"
    let loopsClip = true
    /// Petting the pet again mid-spin restarts the flipping rather than being
    /// swallowed, same reasoning as the other reaction states.
    let restartsOnReentry = true

    /// However long BouncePreset.spin's flip animation takes -- this state
    /// just needs to stay entered exactly that long before returning to Idle.
    /// `nonisolated`: a constant, and the tests read it to place a moment in
    /// the spin without standing on the main actor to do it.
    nonisolated static let duration: TimeInterval = BouncePreset.spinDuration

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
