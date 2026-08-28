//
//  BouncePreset.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Procedural squash-and-stretch "bounce" motion for 2D sprite avatars
//  (02_pet-app.md F2, 2026-07-29 2D switch).
//
//  A static illustration ships no animation frames, so instead of playing
//  back baked motion, pet-app computes a small scale transform every frame
//  from (which clip is playing, how long it's been playing, a 0...1 global
//  intensity dial) -- pure math, no timers or rendering here.
//

import Foundation

/// One frame of a preset's procedural motion. Started out scale-only --
/// squash-and-stretch alone already reads as "bounce" -- and has since grown
/// the two things that genuinely cannot be expressed as a scale: `rotation`
/// (the climb waddle) and `tintHue` (the rainbow flips). Both stay neutral
/// for every preset that doesn't use them, so presets only ever describe
/// what they actually do.
struct BounceTransform: Equatable {
    let scaleX: Double
    let scaleY: Double
    /// Radians, applied on top of whatever orientation the sprite already
    /// has (including the 90 degrees a climbing sprite is turned by).
    var rotation: Double = 0
    /// Hue in 0...1 to wash the character in, or nil for its own colours.
    /// Only the artwork is tinted, never the space around it.
    var tintHue: Double?
    /// Whether the whole sprite should be turned 90 degrees before `rotation`
    /// is applied (wall-climbing). Previously SpriteAvatar re-derived this
    /// itself by comparing the raw clip name to "climb" independently of
    /// BouncePreset.preset(for:)'s own dispatch on that same string (found
    /// via review) -- a future preset needing the same effect would have had
    /// to keep both string literals in sync by hand.
    var rotatesQuarterTurn = false

    static let identity = BounceTransform(scaleX: 1, scaleY: 1)
}

enum BouncePreset: Equatable {
    /// How long `.spin`'s flip animation takes to complete -- SpinState reads
    /// this (not the other way around) so the FSM's timing depends on the
    /// rendering layer's constant, not vice versa. This used to read
    /// SpinState.duration directly, inverted from every other dependency in
    /// the codebase and meaning whoever tunes the *look* of the spin had to
    /// know to edit a Movement/States file (found via review).
    static let spinDuration: TimeInterval = 2.0

    case none
    case idle
    case walk
    case land
    /// point/react_click's short "pop" pulse.
    case pop
    case kick
    /// "pet" (double-tap petting reaction, 2026-07-29).
    case wiggle
    /// The waddle a climbing pet does on its way up (2026-07-29).
    case climb
    /// The flips after being petted (2026-07-29).
    case spin

    /// Which preset a clip name uses. Clips with no bounce behavior (fall,
    /// type, listen, react_drag, and anything unrecognized) get `.none`.
    static func preset(for clip: String) -> BouncePreset {
        switch clip {
        case "idle": return .idle
        case "climb": return .climb
        case "spin": return .spin
        case "walk": return .walk
        case "land": return .land
        case "point", "react_click": return .pop
        case "kick": return .kick
        case "pet": return .wiggle
        default: return .none
        }
    }

    /// The rainbow, in order, one colour per half turn, so the pet's front
    /// and back are never the same colour and each flip reveals the next one.
    ///
    /// The caller offsets the angle by a quarter turn before dividing,
    /// because the boundaries of `angle / .pi` are where the sprite is fully
    /// face-on or back-on -- recolouring there happens in plain view. Edge-on
    /// (width zero) is a quarter turn away from those, and that is the only
    /// moment a colour change is invisible.
    ///
    /// Hues rather than named colours so the tint stays a single number the
    /// renderer can apply without a colour table.
    static let rainbowHues: [Double] = [
        0.0,    // red
        0.083,  // orange
        0.167,  // yellow
        0.333,  // green
        0.583,  // blue
        0.708,  // indigo
        0.792,  // violet
    ]

    static func rainbowHue(halfTurn: Int) -> Double {
        rainbowHues[max(halfTurn, 0) % rainbowHues.count]
    }

    /// `elapsed`: seconds since the current clip started playing.
    /// `intensity`: the manifest's `bounce_intensity` (0...1, 0 = fully static).
    func transform(elapsed: TimeInterval, intensity: Double) -> BounceTransform {
        guard intensity > 0 else { return .identity }

        switch self {
        case .none:
            return .identity

        case .idle:
            // Slow breathing bob.
            let period = 2.5
            let phase = sin(2 * .pi * elapsed / period)
            let amplitude = 0.04 * intensity
            return BounceTransform(scaleX: 1, scaleY: 1 + amplitude * phase)

        case .walk:
            // Faster bounce synced to a nominal step cadence, with a slight
            // horizontal squeeze at the peak so it doesn't just look like
            // pure vertical scaling. The squeeze uses phase^2 rather than
            // abs(phase) -- abs() folds sharply (a derivative kink) at every
            // zero-crossing, which reads as the motion "catching" at each
            // footfall; squaring keeps the same 0-at-rest/full-at-peak shape
            // but eases through zero instead.
            let period = 0.35
            let phase = sin(2 * .pi * elapsed / period)
            let amplitude = 0.08 * intensity
            return BounceTransform(scaleX: 1 - amplitude * 0.3 * phase * phase, scaleY: 1 + amplitude * phase)

        case .land:
            // Decaying spring: squashed flat on impact, oscillates back to
            // identity. exp(...) alone would decay monotonically with no
            // spring-back overshoot; multiplying by cos(...) gives it a
            // couple of damped oscillations before settling.
            let duration = 0.35
            let t = elapsed / duration
            let squash = intensity * exp(-t * 6) * cos(t * 12)
            return BounceTransform(scaleX: 1 + squash * 0.3, scaleY: 1 - squash * 0.3)

        case .pop:
            // One pulse: 0 -> peak -> back to identity, then holds.
            let duration = 0.25
            let t = min(elapsed / duration, 1)
            let pop = intensity * sin(t * .pi)
            return BounceTransform(scaleX: 1 + pop * 0.15, scaleY: 1 + pop * 0.15)

        case .kick:
            // Two phases: anticipation squash (first 40% of the window), then
            // an impact stretch the opposite way. Each phase is its own
            // sine bump (0 -> peak -> 0) rather than a linear ramp, so both
            // ease in/out AND meet at identity at the phase boundary --
            // linear ramps peak right at the boundary and jump straight to
            // the other phase's peak, a visible snap mid-kick.
            let duration = 0.4
            let t = min(elapsed / duration, 1)
            let anticipationWindow = 0.4
            if t < anticipationWindow {
                let localT = t / anticipationWindow
                let s = intensity * sin(localT * .pi)
                return BounceTransform(scaleX: 1 + s * 0.2, scaleY: 1 - s * 0.2)
            } else {
                let localT = (t - anticipationWindow) / (1 - anticipationWindow)
                let s = intensity * sin(localT * .pi)
                return BounceTransform(scaleX: 1 - s * 0.2, scaleY: 1 + s * 0.3)
            }

        case .climb:
            // Rocking side to side on the way up, like something small
            // hauling itself up one side at a time. Rotation is the whole
            // effect -- a scale-only version of this reads as the sprite
            // being squeezed, not as the pet leaning.
            //
            // The vertical squash rides at DOUBLE the rocking frequency, so
            // the pet is shortest at both extremes of the rock and tallest as
            // it passes through upright -- it looks like it's compressing to
            // plant each side and stretching to reach with the other. Matching
            // frequencies instead would just make one side droop.
            let period = 0.5
            let phase = sin(2 * .pi * elapsed / period)
            let lean = 8 * .pi / 180 * intensity
            let reach = 0.05 * intensity
            return BounceTransform(
                // Turned over, both ways. The quarter turn alone lands the
                // pet on the wall the wrong way round -- it went up head
                // first -- and the two mirrors on top of it put its feet
                // against the wall and its head toward the top of the
                // screen, which is the way something climbing goes.
                scaleX: -1,
                scaleY: -(1 - reach * abs(phase)),
                rotation: lean * phase,
                rotatesQuarterTurn: true
            )

        case .spin:
            // Turning about its own vertical axis -- the pet flips over like
            // a sheet of paper, several times. Deliberately NOT an in-plane
            // rotation: that tips the pet over sideways, which reads as it
            // falling rather than as a happy little spin.
            //
            // Same projection FlipAnimation uses for a single turn, and
            // reusing it keeps one definition of what a turning sprite looks
            // like -- the scale multiplies straight into the facing flip
            // SpriteAvatar already applies.
            //
            // A whole number of turns, so the pet always ends face-on however
            // the duration divides into the rate. The easing is applied to
            // how far round it is, never to the angle itself: damping the
            // angle (the obvious-looking `angle * (1 - p * p)`) is not
            // monotonic -- it peaks partway through and returns to zero, so
            // the pet visibly winds up and then unwinds backwards.
            let turns = 3.0
            let progress = min(elapsed / Self.spinDuration, 1)
            let easedOut = 1 - (1 - progress) * (1 - progress) // fast, then coasting to a stop
            let angle = 2 * .pi * turns * easedOut

            // A small squash as it passes edge-on, fading out with the spin,
            // so it reads as the pet throwing itself round rather than an
            // image being scaled by software.
            let settle = 1 - progress
            return BounceTransform(
                scaleX: Double(FlipAnimation.horizontalScale(atAngle: angle)),
                scaleY: 1 - 0.06 * intensity * settle * abs(sin(angle)),
                rotation: 0,
                tintHue: Self.rainbowHue(halfTurn: Int((angle + .pi / 2) / .pi))
            )

        case .wiggle:
            // A joyful side-to-side shake, several quick pulses, decaying to
            // identity by the end of the reaction so it settles rather than
            // cutting off abruptly mid-wiggle.
            let duration = 0.8
            let t = min(elapsed / duration, 1)
            let decay = 1 - t
            let wiggle = sin(2 * .pi * elapsed / 0.15) * intensity * decay
            return BounceTransform(scaleX: 1 + wiggle * 0.12, scaleY: 1 - wiggle * 0.06)
        }
    }
}
