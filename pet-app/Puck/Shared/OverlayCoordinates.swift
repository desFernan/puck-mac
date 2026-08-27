//
//  OverlayCoordinates.swift
//  Puck
//
//  The three conversions between the spaces the overlay window sits in.
//
//  There are three of them and they disagree about which way Y goes:
//
//    - **window-local** -- what the pet, the toys and every state are in.
//      Top-left origin, Y down. `CharacterBody.position` is one of these.
//    - **AppKit global** -- what `NSEvent.mouseLocation` and `NSWindow.frame`
//      are in. Bottom-left origin, Y up.
//    - **Quartz global** -- what `CGWindowListCopyWindowInfo` and the wire
//      protocol are in. Top-left origin of the *primary* display, Y down,
//      which is not the overlay window's origin.
//
//  Each conversion used to be written where it was needed: window-local to
//  AppKit in the file that draws the avatar, AppKit back to window-local in
//  the file that handles clicks, and neither knew about the other. They are
//  inverses, and a pair of inverses kept apart is a pair that drifts -- the
//  Quartz one had already been a plain subtraction with no Y flip at all,
//  which happened to work for the primary display's overlay and for nothing
//  else.
//
//  Pure, so the round trip can be asserted rather than assumed.
//

import CoreGraphics

enum OverlayCoordinates {
    /// AppKit's global screen space to the overlay window's own.
    ///
    /// Two changes at once: the origin moves to the window's, and Y flips to
    /// point down. Doing one without the other puts a click as far from the
    /// pet as the pet is from the middle of the window.
    static func windowLocal(fromGlobalAppKit point: CGPoint, windowFrame: CGRect) -> CGPoint {
        CGPoint(
            x: point.x - windowFrame.origin.x,
            y: windowFrame.height - (point.y - windowFrame.origin.y)
        )
    }

    /// And back the other way.
    static func globalAppKit(fromWindowLocal point: CGPoint, windowFrame: CGRect) -> CGPoint {
        CGPoint(
            x: windowFrame.origin.x + point.x,
            y: windowFrame.origin.y + (windowFrame.height - point.y)
        )
    }

    /// Quartz's global space to the overlay window's own.
    ///
    /// Both are top-left origin and Y-down, so this is only a move -- but the
    /// window's origin has to be expressed in Quartz's space first, and that
    /// is a flip, which is what `GlobalScreenSpace.normalized(fromAppKit:)`
    /// is for. A bare subtraction of the AppKit origin only works for a
    /// window on the primary display.
    static func overlayLocal(
        fromQuartz point: CGPoint,
        windowFrame: CGRect,
        in space: GlobalScreenSpace
    ) -> CGPoint {
        let origin = space.normalized(
            fromAppKit: CGPoint(x: windowFrame.minX, y: windowFrame.maxY)
        )
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }
}
