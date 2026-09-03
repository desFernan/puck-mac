//
//  AvatarStandardSize.swift
//  Puck
//
//  One size every avatar is drawn at, whatever its manifest says.
//
//  A manifest's hitbox was being used as the on-screen size directly, so how
//  big the pet came out depended on numbers each package chose for itself:
//  one drawn at 130x133 and one at 251x300 stood a head apart on the same
//  screen at the same setting, and the size slider meant a different thing
//  for each. Nothing in a package should decide how big the pet is; that is
//  the app's business, and the user's.
//
//  So the hitbox goes back to being what its name says -- a shape, an aspect
//  ratio -- and this turns it into a size. The taller side is matched to a
//  fixed height and the other follows, so a wide character and a tall one are
//  the same height rather than the same area.
//
//  Pure arithmetic, no CALayer, so the awkward cases are testable: a package
//  that declares a zero or absurd hitbox is a package somebody hand-edited,
//  and it must still produce something drawable.
//

import CoreGraphics

enum AvatarStandardSize {
    /// How tall the pet stands, before the size slider and the manifest's own
    /// scale are applied.
    ///
    /// Big enough to read as a character rather than an icon. The pet is
    /// drawn over whatever is on screen and is meant to be looked at; the
    /// size slider is there for anyone who disagrees.
    static let height: CGFloat = 260

    /// The widest the pet may get relative to its height. A package claiming
    /// a 10:1 hitbox is a mistake or a joke; either way it must not become a
    /// banner across the desktop.
    static let maximumAspectRatio: CGFloat = 3

    /// What `scale` has to be for the pet to be drawn `height` tall.
    ///
    /// The inverse of `size(hitbox:scale:)`, and the reason it exists: the
    /// island fits the pet to the room it has, which is a height, and it has
    /// to say that in the units the renderer takes. Working it out against
    /// the manifest's own hitbox -- which is what it used to do -- asks for a
    /// scale in units nothing uses any more, and the pet came out a fraction
    /// of the size the island had made room for.
    static func scale(forDrawnHeight desired: CGFloat) -> Double {
        guard height > 0 else { return 1 }
        return Double(desired / height)
    }

    /// The drawn size for a package whose manifest declares `hitbox`.
    ///
    /// - Parameter scale: the manifest's own scale times the user's size
    ///   setting, applied after normalising so both mean the same thing for
    ///   every avatar.
    static func size(hitbox: CGSize, scale: CGFloat = 1) -> CGSize {
        // A package with no usable shape still has to draw. Square is the
        // least wrong guess and keeps the pet on screen.
        guard hitbox.width > 0, hitbox.height > 0 else {
            let side = height * max(scale, 0.01)
            return CGSize(width: side, height: side)
        }
        let ratio = min(hitbox.width / hitbox.height, maximumAspectRatio)
        let drawnHeight = height * max(scale, 0.01)
        return CGSize(width: drawnHeight * ratio, height: drawnHeight)
    }
}
