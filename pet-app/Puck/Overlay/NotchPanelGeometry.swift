//
//  NotchPanelGeometry.swift
//  Puck
//
//  How big the notch is when it is closed, when it is open, and which of
//  those the cursor is inside.
//
//  Two rects and a hit test, kept away from AppKit so the awkward part is
//  testable. The awkward part is that "the cursor is over the notch" and "the
//  cursor is still over the panel" are different questions with different
//  answers, and getting them the same way round is what stops the panel
//  flickering open and shut along its own edge.
//
//  Everything is in AppKit's global screen space -- bottom-left origin, Y up
//  -- because that is what NSEvent.mouseLocation and NSWindow.frame are in,
//  and this exists to be compared against both.
//

import CoreGraphics

enum NotchPanelGeometry {
    /// How tall the band showing what is playing is.
    ///
    /// Set by the cover art, which is the tallest thing in it: a title, a
    /// lyric and a progress bar stack to less than a square big enough to
    /// recognise an album by.
    static let musicBandHeight: CGFloat = 62

    /// How tall the row of things you press is. One control height, because
    /// everything in it is a target and targets that vary in height are
    /// harder to aim at than ones that do not.
    static let actionBandHeight: CGFloat = 34

    /// The gap above and below the line between the two bands.
    static let bandGap: CGFloat = 12

    /// The padding around the content. Deeper at the bottom than the top:
    /// the bottom corners are rounded, and content run up against a curve
    /// looks closer to the edge than content beside a straight one.
    static let topInset: CGFloat = 13
    static let bottomInset: CGFloat = 16

    /// How far the panel reaches below the notch when open.
    ///
    /// The two bands, the hairline between them, the gaps around it and the
    /// padding -- written as the sum rather than a measured number so that
    /// changing a band moves the window with it, instead of leaving the
    /// panel clipped or floating above its own bottom edge.
    static let openHeight: CGFloat =
        topInset + musicBandHeight + bandGap + 1 + bandGap + actionBandHeight + bottomInset

    /// How wide it opens to. Wider than the notch by a good margin, so the
    /// thing that appears reads as a panel coming out of the notch rather
    /// than as the notch itself growing downward.
    static let openWidth: CGFloat = 560

    /// How far outside the closed notch the cursor may stray and still count
    /// as arriving at it.
    ///
    /// The notch's own bottom edge is the top of the screen's content, so a
    /// pointer moving up to it stops exactly on the boundary; without a
    /// little slack the panel opens only if you overshoot into the bezel.
    static let approachSlack: CGFloat = 4

    /// The window's frame: always the open size, whatever is drawn inside.
    ///
    /// One frame rather than resizing on every hover -- a window that changes
    /// size takes the cursor out of itself on the frame it shrinks, which is
    /// how a hover panel ends up flickering. What changes is what is painted
    /// in it and whether it takes the mouse.
    static func windowFrame(notch: CGRect) -> CGRect {
        CGRect(
            x: notch.midX - openWidth / 2,
            y: notch.maxY - openHeight,
            width: openWidth,
            height: openHeight
        )
    }

    /// Whether the cursor is close enough to the closed notch to open it.
    static func isArriving(_ cursor: CGPoint, notch: CGRect) -> Bool {
        notch.insetBy(dx: -approachSlack, dy: -approachSlack).contains(cursor)
    }

    /// Whether the cursor is still somewhere that should keep the panel open.
    ///
    /// The whole window, not the notch: once it is open the panel is what the
    /// pointer is on its way to, and closing the moment it leaves the notch
    /// itself would shut it before it arrived.
    static func isLingering(_ cursor: CGPoint, notch: CGRect) -> Bool {
        windowFrame(notch: notch).insetBy(dx: -approachSlack, dy: -approachSlack).contains(cursor)
    }

    /// Whether the panel should be open, given where the cursor is and
    /// whether it is open already.
    ///
    /// Asked as one question because the two rects overlap: opening uses the
    /// small one and staying open uses the large one, so a cursor sitting in
    /// the difference between them holds an open panel open without being
    /// able to have opened it. That hysteresis is the whole point -- the same
    /// position giving different answers depending on the way it is moving is
    /// what stops the edge flickering.
    static func shouldBeOpen(cursor: CGPoint, notch: CGRect, isOpen: Bool) -> Bool {
        isOpen ? isLingering(cursor, notch: notch) : isArriving(cursor, notch: notch)
    }
}
