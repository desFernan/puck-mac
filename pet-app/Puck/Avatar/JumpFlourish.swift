//
//  JumpFlourish.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  A short vertical hop -- 02_pet-app.md F3 calls for one on agent_done and
//  on a code_editor detail.path change, but EventReaction.jump was decoded
//  and never actually animated anything (found via spec cross-check).
//
//  Purely visual, like BouncePreset/FlipAnimation: computed from elapsed time
//  and folded into SpriteAvatar's existing per-frame transform, never
//  touching CharacterBody.position (the FSM's real, kinematic position) --
//  the pet doesn't actually leave the ground as far as movement/landing
//  logic is concerned, it just looks like it does.
//

import CoreGraphics
import Foundation

enum JumpFlourish {
    /// Long enough to read as a hop, short enough not to delay whatever the
    /// FSM is doing underneath it (Type, Point, ...).
    static let duration: TimeInterval = 0.3
    /// Peak height in points. Y grows downward in this codebase's screen
    /// space, so the offset itself is negative at the peak.
    static let height: CGFloat = 24

    /// The vertical offset `elapsed` seconds into a jump -- zero before it
    /// starts and once it's finished, negative (upward) at its peak,
    /// parabolic in between.
    static func offset(elapsed: TimeInterval) -> CGFloat {
        guard elapsed >= 0, elapsed <= duration else { return 0 }
        let t = CGFloat(elapsed / duration)
        return -height * 4 * t * (1 - t)
    }
}
