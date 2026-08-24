//
//  StateHandler.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  protocol: enter() / update(dt:context:) / exit()
//

import Foundation

/// A single FSM state. name/clipKey correspond to the state transition table
/// in plan/02_pet-app.md section 3 and the avatar manifest's clips keys.
/// On transition, CharacterController calls AvatarPlayable.play AND triggers
/// SFX using clipKey (not name) -- the manifest's sounds table is keyed by
/// the same lowercase clip names as clips, not the capitalized state name.
/// `@MainActor`: the whole state machine is driven by the frame loop, which
/// is a CVDisplayLink hop onto the main thread -- a state that ran anywhere
/// else would be moving a character AppKit is drawing.
@MainActor
protocol StateHandler: AnyObject {
    /// FSM state name (e.g. "Idle", "WalkOnTop") -- display/debugging only.
    var name: String { get }
    /// Lookup key into the avatar manifest's clips. States without a dedicated
    /// clip (WalkOnTop, MoveTo) reuse "walk".
    var clipKey: String { get }
    /// Whether the clip can loop (start/end pose match) — idle/walk/climb/type/listen/point etc.
    var loopsClip: Bool { get }
    /// Lookup key into the manifest's `sounds`. Defaults to clipKey; states
    /// whose sound depends on something the clip doesn't care about override
    /// it (JuggleBall: which toy the pet is playing with).
    var soundKey: String { get }
    /// Whether the SFX loops. Defaults to false: every mapped sound today is
    /// a spoken one-shot, and a line has an end -- defaulting this to
    /// loopsClip made every looping-clip state with a voice line restart it
    /// mid-sentence forever unless it remembered to opt out. A state with a
    /// genuinely ambient cue (a footstep loop) overrides this to true.
    var loopsSound: Bool { get }
    /// Whether transitioning into this state while it's already the current
    /// one should restart it (exit()+enter() again) rather than being a
    /// no-op. Reactive one-shot states (e.g. ReactClick) want a repeated
    /// trigger to replay from the start; ambient states like Idle must NOT
    /// restart, or repeated same-kind events would reset their timers.
    var restartsOnReentry: Bool { get }
    /// Whether entering this state should leave CharacterBody.isUpsideDown
    /// alone instead of resetting it to false. Only CeilingState (F3
    /// ceiling-crawling, 2026-07-29) overrides this -- any state can
    /// interrupt any other (a click, a drag, an agent command), so a
    /// centralized reset on entry is the only way to guarantee a state
    /// entered *directly* from Ceiling (bypassing Fall's own reset entirely)
    /// still comes back right-side-up.
    var preservesUpsideDown: Bool { get }

    func enter()
    func update(dt: TimeInterval, context: StateContext)
    func exit()
}

extension StateHandler {
    var loopsClip: Bool { false }
    var soundKey: String { clipKey }
    var loopsSound: Bool { false }
    var restartsOnReentry: Bool { false }
    var preservesUpsideDown: Bool { false }
    func enter() {}
    func update(dt: TimeInterval, context: StateContext) {}
    func exit() {}
}
