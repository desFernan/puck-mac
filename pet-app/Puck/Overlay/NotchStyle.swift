//
//  NotchStyle.swift
//  Puck
//
//  The panel's palette and measurements, in one place.
//
//  Written as named tokens rather than numbers at each call site, which is
//  the one idea worth taking from the web design systems this borrows from:
//  the reason a panel looks designed rather than assembled is that a corner
//  radius, a border and a muted label are the *same* radius, border and
//  muted everywhere they appear, and that only holds if there is one name for
//  each of them.
//
//  Everything is white at an opacity rather than a colour. The panel sits on
//  black over an arbitrary desktop, so a surface is defined by how much light
//  it lets through, and a palette of greys would drift against the shell.
//

import SwiftUI

enum NotchStyle {
    // MARK: - Surfaces

    /// A raised element: a tile, a field, a cover's backing.
    static let surface = Color.white.opacity(0.06)
    /// The same element under the pointer.
    static let surfaceHovered = Color.white.opacity(0.11)
    /// The same element while it is on -- a toy that is out.
    static let surfaceActive = Color.white.opacity(0.20)

    /// The unfilled part of a progress bar. Brighter than a surface: it is
    /// read against the filled part beside it rather than against the shell.
    static let track = Color.white.opacity(0.14)

    /// The hairline around a surface, and the one between the two bands.
    static let border = Color.white.opacity(0.09)
    /// The border of something that is on, which has to read as deliberate
    /// against its brighter fill.
    static let borderActive = Color.white.opacity(0.28)

    // MARK: - Text

    /// Titles, and anything else that is the point of the line it is on.
    static let foreground = Color.white
    /// Secondary text: an artist, a source, a placeholder.
    static let mutedForeground = Color.white.opacity(0.55)
    /// Times and other figures that should be readable without being read.
    static let subtleForeground = Color.white.opacity(0.40)

    // MARK: - Shape

    /// Small controls: toy tiles, transport buttons.
    static let radiusSmall: CGFloat = 10
    /// Larger blocks: the cover.
    static let radiusMedium: CGFloat = 12

    // MARK: - Motion

    /// A hover, which should feel immediate.
    static let hover = Animation.easeOut(duration: 0.12)
    /// A state that changed because something was pressed, which is worth a
    /// beat rather than a jump.
    static let stateChange = Animation.easeOut(duration: 0.16)
}
