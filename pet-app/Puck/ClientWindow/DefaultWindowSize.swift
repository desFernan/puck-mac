//
//  DefaultWindowSize.swift
//  Puck
//
//  How big the chat window opens.
//
//  1440x900 was written down when the window was a sidebar and a
//  conversation. It is now five things across -- sidebar, island, chat, the
//  file a click opens, and the file list -- and at 1440 the three that can
//  give way all do at once: the conversation loses its measure, the code
//  column opens at its 300pt floor, and the explorer's names truncate. The
//  window was smaller than what it holds.
//
//  Sized to the screen rather than fixed, because "big enough" is a fact
//  about the display: 1760 is roomy on an ultrawide and does not fit on a
//  13-inch laptop at all. A fraction alone is no better -- most of an
//  ultrawide is a chat window nobody wants -- so it is a target, capped by
//  what the screen can spare and floored by what the layout needs.
//
//  Pure, and separate from the window, because every interesting case is a
//  screen this machine does not have.
//

import CoreGraphics

enum DefaultWindowSize {
    /// What the layout wants when nothing is in its way.
    ///
    /// Width: the sidebar at its ideal (220), a conversation at its measure
    /// (760 plus its margins), the code column somewhere worth reading (520)
    /// and the file list at its ideal (200). That is everything open at once
    /// without any of it at a minimum.
    ///
    /// Height: enough transcript above the composer to hold a reply and the
    /// exchange before it, with the island and the status bar taken off the
    /// top and bottom.
    static let preferred = CGSize(width: 1_760, height: 1_040)

    /// How much of the screen the window may take.
    ///
    /// Not all of it: a window the size of the display reads as a full-screen
    /// app, and this one is meant to sit beside what you are working on --
    /// the pet walks out of it onto the desktop.
    static let maximumScreenFraction: CGFloat = 0.86

    /// The size to open at on a screen whose usable area is `visibleFrame`.
    ///
    /// - Parameter minimum: what the layout cannot go under, which the window
    ///   also enforces as its own `minSize`. Honoured last: a screen too
    ///   small for the floor gets the floor, because the alternative is a
    ///   window whose panes overflow rather than compress.
    static func size(forVisibleFrame visibleFrame: CGSize, minimum: CGSize) -> CGSize {
        let allowed = CGSize(
            width: visibleFrame.width * maximumScreenFraction,
            height: visibleFrame.height * maximumScreenFraction
        )
        return CGSize(
            width: max(minimum.width, min(preferred.width, allowed.width)),
            height: max(minimum.height, min(preferred.height, allowed.height))
        )
    }
}
