//
//  CharacterBody.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The pet's position and facing, and the one place that pushes them onto the
//  avatar.
//
//  States previously received only `dt` and had no handle on the character at
//  all, so no amount of frame ticking could have moved anything. They now act
//  on this; it forwards to AvatarPlayable so no state ever talks to the
//  renderer directly (F2's rule that the FSM must not know the avatar type).
//
//  Coordinates are GlobalScreenSpace pixels: top-left origin, Y down.
//

import CoreGraphics
import Foundation

final class CharacterBody {
    /// pet-app's own default bounce intensity when manifest.bounce_intensity
    /// is absent (2026-07-29 2D switch, 02_pet-app.md F2).
    static let defaultBounceIntensity = 0.6

    private let avatar: AvatarPlayable
    private let bounceIntensity: Double

    var position: CGPoint {
        didSet { avatar.setScreenPosition(position) }
    }

    /// Writing the same facing is a no-op — the FSM sets this every frame
    /// while walking, and re-applying the transform 60 times a second is
    /// pointless work.
    var facing: AvatarFacing {
        didSet {
            guard facing != oldValue else { return }
            avatar.setFacing(facing)
        }
    }

    /// A one-shot launch impulse in px/sec, consumed by the next state that
    /// can act on it (only FallState today, which reads it on its first frame
    /// and clears it). Set by ReactDragState when the pet is thrown: the
    /// throw's speed has to outlive the drag state that measured it, and this
    /// is the only thing both states already share. Zero means a plain drop,
    /// so every other route into Fall is unaffected.
    ///
    /// Deliberately NOT a live velocity the FSM integrates every frame -- the
    /// states are kinematic by design ("물리엔진 없음", plan/02_pet-app.md F3)
    /// and only Fall does anything with acceleration.
    var launchVelocity: CGPoint = .zero

    /// F3 ceiling-crawling (2026-07-29): true while CeilingState/ClimbToCeilingState
    /// own the character. Same no-op-on-unchanged guard as facing.
    var isUpsideDown: Bool = false {
        didSet {
            guard isUpsideDown != oldValue else { return }
            avatar.setUpsideDown(isUpsideDown)
        }
    }

    /// The pet's visible outline relative to its position — forwarded from
    /// the avatar so the FSM never talks to the renderer directly, the same
    /// rule every other property here follows.
    var visualBounds: CGRect { avatar.visualBounds }

    /// Whether a point (relative to `position`) lands on the drawn character.
    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        avatar.hitTest(point, tolerance: tolerance)
    }

    func play(clip: String, loop: Bool) {
        avatar.play(clip: clip, loop: loop)
    }

    func stop() {
        avatar.stop()
    }

    func updateBounce(clip: String, elapsed: TimeInterval) {
        avatar.updateBounce(clip: clip, elapsed: elapsed, intensity: bounceIntensity)
    }

    /// A short visual hop -- EventRouter's agent_done/code_editor
    /// path-change reactions (02_pet-app.md F3). Forwarded straight through,
    /// same as every other avatar-facing call here.
    func triggerJump() {
        avatar.triggerJump()
    }

    init(avatar: AvatarPlayable, position: CGPoint, facing: AvatarFacing = .right, bounceIntensity: Double = CharacterBody.defaultBounceIntensity) {
        self.avatar = avatar
        self.position = position
        self.facing = facing
        self.bounceIntensity = bounceIntensity
        avatar.setScreenPosition(position)
    }
}
