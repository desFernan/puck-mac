//
//  ScreenNotch.swift
//  Puck
//
//  The camera housing at the top of a MacBook's screen, as something the pet
//  has to walk around.
//
//  Most of the time it is not in the pet's world at all: the roamable area
//  comes from `NSScreen.visibleFrame`, which has the menu bar subtracted, and
//  on a notched Mac the menu bar is exactly as tall as the notch. The pet's
//  ceiling is already below it.
//
//  In a fullscreen Space it is. The menu bar goes away, `visibleFrame` gives
//  that height back (see AppDelegate's Space observer), and the pet's world
//  now reaches the physical top of the display -- where a black plastic
//  rectangle is hanging down into it. A pet crawling that ceiling walks
//  straight through the camera.
//
//  So the ceiling is not a line, it is a function of x: the top of the screen
//  everywhere, and the bottom of the notch under the notch. Everything that
//  asks "how high can the pet go here" asks it that way now.
//
//  Only a real one. A display without a camera housing does not get given a
//  drawn stand-in: the pet would duck around something that is not there, and
//  a panel hung over the middle of a live menu bar takes clicks meant for it.
//
//  Pure, so a notch can be tested on a machine that has none -- which is most
//  of them, and was this one.
//

import CoreGraphics

struct ScreenNotch: Equatable {
    /// The notch in the same space the pet's areas are in: top-left origin,
    /// Y down, rebased onto the overlay window.
    let rect: CGRect

    /// How far the pet's world is allowed to reach at `x`.
    ///
    /// - Parameter areaTop: the top of the display the pet is on, which is
    ///   the answer everywhere the notch is not.
    func ceiling(atX x: CGFloat, areaTop: CGFloat) -> CGFloat {
        // The notch's own sides count as under it: a pet whose ceiling
        // changed only strictly inside would clip the corner.
        guard x >= rect.minX, x <= rect.maxX else { return areaTop }
        // Never *above* the area's own top. A notch on a display the pet is
        // not on, or one that has been rebased wrong, must not hand back a
        // ceiling that lets the pet leave the screen.
        return max(areaTop, rect.maxY)
    }

    /// Whether the pet's whole outline clears the notch at `position`.
    ///
    /// Asked of the outline rather than the ground point for the same reason
    /// ScreenGround asks it that way: half a pet behind the camera housing is
    /// as wrong as all of it.
    func clears(_ position: CGPoint, visualBounds: CGRect, areaTop: CGFloat) -> Bool {
        let head = position.y + visualBounds.minY
        let left = position.x + visualBounds.minX
        let right = position.x + visualBounds.maxX
        return head >= ceiling(atX: left, areaTop: areaTop)
            && head >= ceiling(atX: right, areaTop: areaTop)
    }

    /// The notch on `screen`, in AppKit's own coordinates, or nil when there
    /// is not one.
    ///
    /// Derived from the two areas AppKit reports *beside* the notch rather
    /// than from a hardcoded size: the gap between them is the notch, on
    /// whichever MacBook this is. A screen with no notch reports neither.
    ///
    /// - Parameters:
    ///   - frame: the screen's full frame, whose top edge is the notch's.
    ///   - auxiliaryTopLeft: `NSScreen.auxiliaryTopLeftArea`.
    ///   - auxiliaryTopRight: `NSScreen.auxiliaryTopRightArea`.
    static func appKitRect(
        inScreenFrame frame: CGRect,
        auxiliaryTopLeft: CGRect?,
        auxiliaryTopRight: CGRect?
    ) -> CGRect? {
        guard let left = auxiliaryTopLeft, let right = auxiliaryTopRight else { return nil }
        let width = right.minX - left.maxX
        // A zero or inverted gap is not a notch. Reported areas that meet, or
        // that arrive the other way round on a screen arrangement nobody
        // anticipated, must produce nothing rather than a rectangle of
        // nonsense the pet then tries to walk around.
        guard width > 0 else { return nil }
        // Its bottom is where the strips beside it end -- that is the same
        // line the menu bar's own bottom is on.
        let bottom = min(left.minY, right.minY)
        let height = frame.maxY - bottom
        guard height > 0 else { return nil }
        return CGRect(x: left.maxX, y: bottom, width: width, height: height)
    }
}
