//
//  AppDelegate+AvatarAppearance.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Live-applies the Settings size slider to the avatar, hitbox, and
//  character position.
//

import CoreGraphics

extension AppDelegate {
    // MARK: - Avatar appearance (Settings size slider, 2026-07-29)

    /// Called when the size slider changes (the menu bar's quick view), and
    /// whenever the pet is resized to fit its island.
    /// `avatarHitboxSize` must be recomputed too (its click-through geometry
    /// has to track what's actually rendered), and the character's position
    /// has to be re-pushed through CharacterBody so the ground-point offset
    /// (which depends on the sprite's height) picks up the new size --
    /// otherwise the pet stays at its old screen position until the next
    /// state transition happens to move it.
    func applyLiveAvatarScale(_ scale: Double) {
        // Logged when it settles somewhere new, not on every frame of a trip:
        // the pet is resized dozens of times a second while it crosses
        // between the desktop and its island, and what is worth knowing is
        // where it ended up. Without this, "the pet keeps getting smaller"
        // has no record at all -- the size is derived, never stored, so
        // nothing else can be asked what it was.
        if abs(scale - lastLoggedAvatarScale) > 0.02 {
            lastLoggedAvatarScale = scale
            AppLogger.shared.log(.info, String(format: "avatar scale -> %.3f", scale))
        }
        avatar?.updateScale(scale)
        // The drawn size, not the manifest's numbers times a scale: the
        // two parted company when the renderer moved to a standard height,
        // and a pet the movement system thinks is half the size it looks
        // walks through things and stands off the floor.
        avatarHitboxSize = AvatarStandardSize.size(hitbox: baseHitboxSize, scale: CGFloat(scale))
        characterController?.avatarHeight = avatarHitboxSize.height
        // Not `body.position = body.position` -- Swift rejects that as a
        // self-assignment, and CharacterBody's didSet wouldn't fire anyway.
        // Push straight to the avatar instead, at the position it already has.
        if let body = characterBody {
            avatar?.setScreenPosition(body.position)
        }
    }
}
