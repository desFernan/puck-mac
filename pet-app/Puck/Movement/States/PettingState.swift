//
//  PettingState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Petting state's StateHandler implementation.
//
//  A double-tap "petting" reaction, distinct from a single ReactClick tap.
//  Reuses ReactClickState's exact shape (short reaction, then back to
//  whatever the pet was doing), just with its own clip/bounce/emotion so it
//  reads as a different, happier reaction than a plain click.
//
//  Also the reaction to having its head stroked with the cursor
//  (HeadPetDetector). That version has no duration of its own -- it lasts as
//  long as the user keeps going -- so the timer is suspended while stroking
//  and the pet twirls (Spin) once the hand leaves, instead of dropping
//  straight back to Idle the way the double-tap does.
//

import Foundation

final class PettingState: StateHandler {
    let name = "Petting"
    let clipKey = "pet"
    let loopsClip = false
    // Petting the pet again while it's still reacting should replay the
    // reaction, same reasoning as ReactClickState.restartsOnReentry.
    let restartsOnReentry = true

    /// Long enough for the wiggle bounce to read (BouncePreset.wiggle's own
    /// duration).
    static let duration: TimeInterval = 0.8

    private var elapsed: TimeInterval = 0
    private var oneShot = OneShotTransition()
    /// True while the user is actively stroking the pet's head.
    private var isBeingStroked = false
    /// Whether this reaction came from stroking — which earns a twirl —
    /// rather than from a double-tap, which doesn't.
    private var wasStroked = false

    func enter() {
        elapsed = 0
        oneShot.reset()
        isBeingStroked = false
        wasStroked = false
    }

    /// The user started rubbing the pet's head. Call *after* transitioning in:
    /// enter() clears this, the same ordering trap ReactDragState documents.
    func beginStroking() {
        isBeingStroked = true
        wasStroked = true
    }

    /// The user stopped stroking. Ends the reaction on the next frame — the
    /// state never drives a transition from outside the frame loop.
    func endStroking() {
        guard isBeingStroked else { return }
        isBeingStroked = false
        elapsed = Self.duration
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !oneShot.hasFired else { return }
        // Being stroked holds the reaction open for as long as it lasts.
        guard !isBeingStroked else { return }

        elapsed += dt
        guard elapsed >= Self.duration else { return }
        oneShot.fire(wasStroked ? .spin : .idle, using: context.requestTransition)
    }
}
