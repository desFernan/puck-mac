//
//  GroundedSpawnPosition.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Where the pet appears on launch/display-rebuild/summon -- horizontally
//  centered, standing on the ground (bottom edge), not floating at the
//  window's vertical center. WanderScheduler's walk targets and
//  LandingSurfaceResolver's screen-bottom fallback already treat the bottom
//  edge as "the ground"; spawning/resetting anywhere else left the pet
//  visibly floating in empty space until the first wander timer fired.
//
//  No hitbox/height parameter needed: AvatarPlayable.setScreenPosition's
//  input is the ground/feet point uniformly across avatar types (SpriteAvatar
//  converts to its own CALayer center internally; USDZAvatar's rig is
//  root-at-feet by convention already), so "the ground" is just the bottom edge.

import CoreGraphics

enum GroundedSpawnPosition {
    /// Small gap so the sprite doesn't visually clip into the very bottom pixel row.
    static let groundMargin: CGFloat = 4

    /// A rect rather than a size: with several displays the pet's world does
    /// not start at the overlay window's own origin, and the middle of the
    /// window is a point on whichever monitor happens to be in the middle of
    /// the arrangement -- or in the space between two of them.
    static func position(in area: CGRect) -> CGPoint {
        CGPoint(x: area.midX, y: area.maxY - groundMargin)
    }
}
