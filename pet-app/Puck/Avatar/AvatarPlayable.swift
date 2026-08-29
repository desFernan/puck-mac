//
//  AvatarPlayable.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  protocol: play(clip:loop:) / stop / setScreenPosition / setFacing
//
//  The FSM (Movement/CharacterController) only knows this protocol — it has no
//  idea whether USDZAvatar/VideoAvatar/SpriteAvatar is actually playing
//  (F2).

import CoreGraphics
import Foundation

enum AvatarFacing {
    case left
    case right
}

protocol AvatarPlayable: AnyObject {
    func play(clip: String, loop: Bool)
    func stop()
    func setScreenPosition(_ position: CGPoint)
    func setFacing(_ facing: AvatarFacing)

    /// Per-frame procedural "bounce" motion (2026-07-29 2D switch, F2) --
    /// `clip`/`elapsed` describe how long the current clip has been
    /// playing, `intensity` is the manifest's bounce_intensity. Default is a
    /// no-op: usdz/video avatars have no use for this, only SpriteAvatar acts on it.
    func updateBounce(clip: String, elapsed: TimeInterval, intensity: Double)

    /// Live-applies a new `manifest.scale` (Settings' size slider). Default
    /// is a no-op -- usdz/video avatars don't support live resizing.
    func updateScale(_ scale: Double)

    /// Swaps to the manifest's `emotions[emotion]` image, if one is mapped
    /// (Settings' emotion mapping, driven by EventRouter's emotion field).
    /// Silent no-op if the key isn't mapped -- same "unmapped = do nothing"
    /// policy as the sounds table. Default is a no-op: usdz/video avatars
    /// don't support emotion images.
    func showEmotion(_ emotion: String)

    /// F3 ceiling-crawling (2026-07-29): flips the sprite vertically while
    /// CeilingState owns the character. Default is a no-op -- usdz/video
    /// avatars have no use for this, only SpriteAvatar acts on it.
    func setUpsideDown(_ isUpsideDown: Bool)

    /// A short visual hop (F3: agent_done, code_editor
    /// detail.path changes) -- JumpFlourish, purely a render-time overlay
    /// like bounce/tint, never touching the FSM's actual position. Default
    /// is a no-op -- usdz/video avatars have no use for this, only
    /// SpriteAvatar acts on it.
    func triggerJump()

    /// The character's visible outline as a rectangle, relative to its ground
    /// point (the position the FSM moves): `minX`/`maxX` are how far the
    /// artwork extends to either side, `minY` how far above (negative, since Y
    /// grows downward). Used to keep the pet inside the screen and to bounce
    /// it off the edges by its own outline rather than by its centre point.
    ///
    /// Default is the zero rect — a point. An avatar that can't measure
    /// itself is treated as having no extent, which is exactly the old
    /// behaviour, so nothing regresses.
    var visualBounds: CGRect { get }

    /// Whether `point` -- relative to the pet's ground point, in the same
    /// space as `visualBounds` -- lands on the artwork itself rather than on
    /// the transparent canvas around it.
    ///
    /// Asked of the avatar rather than computed by the click handling,
    /// because only the avatar knows how it is currently drawn: which way it
    /// faces, whether it is upside-down on a ceiling, how the procedural
    /// bounce is squashing it, whether it is rotated flat against a wall.
    ///
    /// `tolerance` is in points, and dilates the silhouette so grabbing
    /// something small doesn't demand pixel precision.
    ///
    /// Default falls back to `visualBounds`, which is what an avatar with no
    /// measurable artwork (usdz, video) can honestly answer.
    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool

    /// Fades the whole avatar out and back in. Used when the pet moves
    /// between the desktop and its tank, which is a cut rather than a walk.
    /// Default is a no-op, and the completion still runs -- a caller that
    /// moves the pet inside it must not be skipped by an avatar that cannot
    /// animate.
    func setAlpha(_ alpha: CGFloat, duration: TimeInterval, completion: (() -> Void)?)
}

extension AvatarPlayable {
    func updateBounce(clip: String, elapsed: TimeInterval, intensity: Double) {}
    func updateScale(_ scale: Double) {}
    func showEmotion(_ emotion: String) {}
    func setUpsideDown(_ isUpsideDown: Bool) {}
    func triggerJump() {}
    var visualBounds: CGRect { .zero }

    func setAlpha(_ alpha: CGFloat, duration: TimeInterval, completion: (() -> Void)?) {
        completion?()
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        visualBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }
}
