//
//  KickBallState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  KickBall state's StateHandler implementation (optional ball-toy
//  interaction, F12).
//
//  A short "header" reaction once the pet has arrived at the ball, then back
//  to Idle -- mirrors ReactClickState's timer shape. `onEnter` is where
//  AppDelegate actually launches the ball (BallPhysics.kick), matching
//  PointState.onEnter's pattern for bootstrap-owned side effects a pure
//  StateHandler shouldn't reach for itself.

import Foundation

final class KickBallState: StateHandler {
    let name = "KickBall"
    let clipKey = "kick" // falls back straight to idle if the manifest has no dedicated clip (AvatarLoader.resolvedClipName)
    let loopsClip = false

    /// Long enough for BouncePreset's kick anticipation+impact motion to read.
    static let duration: TimeInterval = 0.4

    /// Fired once, on entry -- AppDelegate uses this to actually launch the
    /// ball (BallPhysics.kick) in the pet's current facing direction.
    var onEnter: (() -> Void)?

    private var elapsed: TimeInterval = 0
    private var oneShot = OneShotTransition()

    func enter() {
        elapsed = 0
        oneShot.reset()
        onEnter?()
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !oneShot.hasFired else { return }
        elapsed += dt
        guard elapsed >= Self.duration else { return }
        oneShot.fire(.idle, using: context.requestTransition)
    }
}
