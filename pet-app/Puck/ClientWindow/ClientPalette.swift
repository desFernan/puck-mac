//
//  ClientPalette.swift
//  Puck
//
//  Design system v2 (2026-08-14) -- see docs/decisions.md. Two
//  independently art-directed palettes (light/dark), not a light/dark axis
//  crossed with a flat/glass axis -- `.glass` is gone (macOS 26+-only
//  upkeep cost wasn't worth it for a mood nobody asked to keep).
//

import SwiftUI

/// The colours a code editor needs on top of the interface ones.
///
/// Part of the palette rather than derived from it, because a real editor
/// theme is a set of choices about code -- which of keyword, type and string
/// is the loud one -- and deriving them from three interface colours is what
/// made every theme's code look the same.
struct SyntaxPalette {
    var keyword: Color
    var type: Color
    var function: Color
    var string: Color
    var number: Color
    var comment: Color
    /// Plain identifiers. Usually the body text colour; named so a theme that
    /// disagrees can say so.
    var variable: Color
}

struct ClientPalette {
    var background: Color
    var surface: Color
    var surfaceBorder: Color
    var textPrimary: Color
    var textSecondary: Color
    /// The one deliberately loud color -- send button, active row, one
    /// empty-state glow. Not used anywhere else. Identical in every
    /// palette and in chat-web/workspace's --brand.
    var accent: Color
    /// Text/icons drawn directly on a solid `accent` fill.
    var onAccent: Color
    /// Status-color vocabulary (v2, new) -- session/run/connection state,
    /// git-style diff coloring. `statusIdle`/`statusActive` are computed
    /// rather than stored so they can never drift from `textSecondary`/
    /// `accent`.
    var statusSuccess: Color
    var statusError: Color
    var statusWarning: Color

    var syntax: SyntaxPalette

    var statusIdle: Color { textSecondary }
    var statusActive: Color { accent }

    /// A neutral dark, without a house style. Lighter than Vercel's
    /// near-black, which is what makes it the one to reach for when the
    /// screen is not the only thing on the desk.
    static let dark = ClientPalette(
        background: Color(hex: 0x1e1e1e),
        surface: Color(hex: 0x272727),
        surfaceBorder: Color(hex: 0x3a3a3a),
        textPrimary: Color(hex: 0xe4e4e4),
        textSecondary: Color(hex: 0x9d9d9d),
        accent: Color(hex: 0xed8c33),
        onAccent: Color(hex: 0x1e1e1e),
        statusSuccess: Color(hex: 0x3fb950),
        statusError: Color(hex: 0xf85149),
        statusWarning: Color(hex: 0xe3b341),
        syntax: SyntaxPalette(
            keyword: Color(hex: 0xff7ab2),
            type: Color(hex: 0x6bdfff),
            function: Color(hex: 0x7ac2ff),
            string: Color(hex: 0xff8170),
            number: Color(hex: 0xd9c97c),
            comment: Color(hex: 0x7f8c98),
            variable: Color(hex: 0xe4e4e4)
        )
    )

    /// Vercel's dark neutrals, which this app shipped on. Secondary text is
    /// #a1a1a1 rather than the #7a7a7a it had: that grey on near-black is
    /// what made whole panes read as switched off.
    static let vercelDark = ClientPalette(
        background: Color(hex: 0x0a0a0a),
        surface: Color(hex: 0x141414),
        surfaceBorder: Color(hex: 0x2e2e2e),
        textPrimary: Color(hex: 0xededed),
        textSecondary: Color(hex: 0xa1a1a1),
        accent: Color(hex: 0xed8c33),
        // Near-black reads better on the accent than white does here.
        onAccent: Color(hex: 0x161616),
        statusSuccess: Color(hex: 0x3fb950),
        statusError: Color(hex: 0xf85149),
        statusWarning: Color(hex: 0xe3b341),
        // Neutral chrome, coloured code. The theme's restraint is in the
        // interface; leaving the code grey too is what made it look unlit.
        syntax: SyntaxPalette(
            keyword: Color(hex: 0xd2a8ff),
            type: Color(hex: 0x79c0ff),
            function: Color(hex: 0xd2a8ff),
            string: Color(hex: 0xa5d6ff),
            number: Color(hex: 0xffa657),
            comment: Color(hex: 0x8b949e),
            variable: Color(hex: 0xededed)
        )
    )

    /// Tokyo Night, Storm variant. Night's #1a1b26 is nearly black; Storm's
    /// #24283b keeps the blue in the ground, which is the point of the theme.
    static let tokyoNight = ClientPalette(
        background: Color(hex: 0x1f2335),
        surface: Color(hex: 0x24283b),
        surfaceBorder: Color(hex: 0x3b4261),
        textPrimary: Color(hex: 0xc0caf5),
        // Brighter than the theme's own #565f89 comment grey, which is meant
        // for code nobody is reading and is unreadable as interface text.
        textSecondary: Color(hex: 0x8b95c4),
        // The theme's own orange, so the brand accent belongs to it rather
        // than being imported over it.
        accent: Color(hex: 0xff9e64),
        onAccent: Color(hex: 0x1f2335),
        statusSuccess: Color(hex: 0x9ece6a),
        statusError: Color(hex: 0xf7768e),
        statusWarning: Color(hex: 0xe0af68),
        syntax: SyntaxPalette(
            keyword: Color(hex: 0xbb9af7),
            type: Color(hex: 0x2ac3de),
            function: Color(hex: 0x7aa2f7),
            string: Color(hex: 0x9ece6a),
            number: Color(hex: 0xff9e64),
            comment: Color(hex: 0x565f89),
            variable: Color(hex: 0xc0caf5)
        )
    )

    static let light = ClientPalette(
        background: Color(hex: 0xfafafa),
        surface: Color(hex: 0xffffff),
        surfaceBorder: Color(hex: 0xe5e5e5),
        textPrimary: Color(hex: 0x1a1a1a),
        textSecondary: Color(hex: 0x6b6b6b),
        accent: Color(hex: 0xed8c33),
        onAccent: Color(hex: 0xffffff),
        statusSuccess: Color(hex: 0x3fb950),
        statusError: Color(hex: 0xf85149),
        statusWarning: Color(hex: 0xe3b341),
        syntax: SyntaxPalette(
            keyword: Color(hex: 0xcf222e),
            type: Color(hex: 0x953800),
            function: Color(hex: 0x8250df),
            string: Color(hex: 0x0a3069),
            number: Color(hex: 0x0550ae),
            comment: Color(hex: 0x6e7781),
            variable: Color(hex: 0x1a1a1a)
        )
    )
}

extension Color {
    /// `0xrrggbb`, so a palette reads the way a theme is published rather
    /// than as three decimals a reader has to convert back.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}
