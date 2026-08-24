//
//  JuggleBallState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  JuggleBall state's StateHandler implementation (optional ball-toy
//  interaction, 02_pet-app.md F12).
//
//  2026-07-29: the pet plays with the toy overhead for a while, then throws
//  it away and gets on with its day -- catching and re-throwing rather than
//  a pure bounce, and only for a while before moving on.
//
//  Catching, not heading. The toy comes down and STOPS on the pet's head --
//  it is resting there, physics and all -- and only after a short beat does
//  the pet throw it back up. That pause is the whole difference between a
//  catch and a bounce; without it the toy pings off the head on contact and
//  reads as a football header rather than the pet playing with something.
//
//  Each throw is driven by the toy actually arriving (AppDelegate calls
//  `caught()` from the existing head-collision path), never by a free-running
//  timer, which would throw again whether or not the toy had come back and
//  drift out of sync with its own arc within a couple of rounds.
//
//  Two ways out. Normally the pet gets bored: after `playDuration` it waits
//  for one more catch and then hands off to KickBall, which throws the toy
//  away properly -- the "대충 던지고" ending, done from the hand rather than
//  by snatching the toy out of mid-air. Failing that, if nothing comes back
//  for `patience` at all (the toy was picked up by the cursor, or knocked
//  somewhere it can't return from), the pet gives up and goes back to idle.

import Foundation

final class JuggleBallState: StateHandler {
    let name = "JuggleBall"
    let clipKey = "kick" // reuses kick's bounce/clip -- a header-like pop, no dedicated clip in the manifest
    let loopsClip = false

    /// Which toy the pet is about to play with, set by whoever starts the
    /// game (AppDelegate.startPlaying). Only the SOUND is toy-specific: the
    /// pet has a line for each toy ("호박이 좋아요"), while the motion is the
    /// same pop for all of them. A toy with no `kick_<toy>` entry plays
    /// nothing, per the table's standing "unmapped key = silence" rule.
    var toyName: String?

    var soundKey: String { toyName.map { "kick_\($0)" } ?? clipKey }

    /// How long the pet keeps playing before it has had enough.
    static let playDuration: TimeInterval = 6
    /// How long the toy sits on the pet's head between being caught and being
    /// thrown again. Long enough to read as a catch, short enough to look
    /// like play rather than a pause.
    static let holdTime: TimeInterval = 0.25
    /// How long to wait for a toy that never comes back before giving up.
    /// Comfortably longer than a throw's arc, so ordinary play never trips it.
    static let patience: TimeInterval = 1.5

    /// How the current toy is played with. Set before entering; see
    /// ToyPlayStyle. A spin-style toy is simply held overhead for the same
    /// `playDuration`, so all the timing below is shared and only the manner
    /// of play differs.
    var style: ToyPlayStyle = .throwAndCatch

    /// Fired on entry and after each catch -- AppDelegate throws the toy up
    /// over the pet's head in response. Not used by spin-style toys.
    var onThrow: (() -> Void)?

    /// Time since the toy last left the pet's hands. Not counted while the
    /// toy is being held -- the pet can hardly lose a toy it's holding.
    private var sinceThrown: TimeInterval = 0
    private var totalElapsed: TimeInterval = 0
    /// Set while the toy is sitting on the pet's head, waiting to be thrown.
    private var holdElapsed: TimeInterval?
    private var oneShot = OneShotTransition()

    func enter() {
        sinceThrown = 0
        totalElapsed = 0
        holdElapsed = nil
        oneShot.reset()
        guard style == .throwAndCatch else { return }
        onThrow?()
    }

    /// The toy came to rest on the pet's head. Called by whoever owns the
    /// collision (AppDelegate).
    func caught() {
        holdElapsed = 0
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !oneShot.hasFired else { return }
        totalElapsed += dt

        // A spun toy never leaves the pet, so there is nothing to catch and
        // nothing that can fail to come back -- it just ends when the pet has
        // had enough, with the same throw-away as everything else.
        guard style == .throwAndCatch else {
            guard totalElapsed >= Self.playDuration else { return }
            oneShot.fire(.kickBall, using: context.requestTransition)
            return
        }

        if let elapsed = holdElapsed {
            let held = elapsed + dt
            guard held >= Self.holdTime else {
                holdElapsed = held
                return
            }
            holdElapsed = nil

            // Bored, and holding the toy: the moment to throw it away for
            // good rather than straight back up.
            guard totalElapsed < Self.playDuration else {
                oneShot.fire(.kickBall, using: context.requestTransition)
                return
            }
            sinceThrown = 0
            onThrow?()
            return
        }

        // Mid-air. Only a toy that never comes back ends things here.
        sinceThrown += dt
        guard sinceThrown >= Self.patience else { return }
        oneShot.fire(.idle, using: context.requestTransition)
    }
}
