//
//  NotchHoverView.swift
//  Puck
//
//  The part of the notch panel's window that the pointer can actually touch.
//
//  Hover is read from a tracking area rather than a global event monitor,
//  which is what this type exists for. A global monitor needs the process to
//  be trusted for Accessibility, and Puck's ad-hoc signature changes on every
//  rebuild -- so the grant goes away and the notch quietly stops opening,
//  with nothing on screen to say why. A window that owns its own mouse needs
//  no permission at all.
//
//  The price is that this window takes the pointer, and it sits over the menu
//  bar. So it takes it only where it is drawn: `hitTest` answers nil
//  everywhere else, which leaves the rest of the menu bar working normally.
//  Closed, that is the notch alone -- on a real notch a piece of camera
//  housing there is nothing to click anyway, and on a given one it is the
//  empty stretch between the app menus and the status items.
//
//  What the tracking area covers and what the pointer can touch are two
//  different rectangles, and this only reports where the pointer is. Deciding
//  whether that counts is NotchPanelGeometry's job.
//
//  The tracking area is the whole window and never changes. Swapping it for a
//  smaller one while shut and a larger one while open -- which is what this
//  did -- meant the rectangle the pointer was being measured against was
//  itself changing as a result of the measurement, and a tracking area
//  rebuilt under the pointer does not reliably say whether the pointer is now
//  inside it. The panel opened from most of the width of the open panel while
//  it was shut, which is the size it is not.
//

import AppKit

final class NotchHoverView: NSView {
    /// Where the pointer can touch this window, in the view's own
    /// coordinates: the notch while closed, the whole panel while open.
    ///
    /// This gates clicks and nothing else. It deliberately does not gate
    /// hovering -- see the note above.
    var activeRect: CGRect = .zero

    /// Where the pointer is, in screen coordinates, or nil once it has left
    /// the window entirely.
    var onPointerMoved: ((CGPoint?) -> Void)?

    private var tracking: NSTrackingArea?

    /// Only where it is drawn. Everything else passes through to whatever is
    /// beneath -- the menu bar, mostly, which has to keep working.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return activeRect.contains(local) ? super.hitTest(point) : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildTrackingArea()
    }

    private func rebuildTrackingArea() {
        if let tracking { removeTrackingArea(tracking) }
        // `.inVisibleRect` so it follows the view rather than being rebuilt
        // against a stale rect, and `.activeAlways` rather than
        // `.activeInKeyWindow`: this panel is never the key window until
        // somebody types in it, and by then they have already had to point
        // at it.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { report() }
    override func mouseMoved(with event: NSEvent) { report() }
    override func mouseExited(with event: NSEvent) { onPointerMoved?(nil) }

    /// Where the pointer is now, asked of the system rather than read off the
    /// event.
    ///
    /// An event's own location is where the event happened, which for one a
    /// tracking area synthesised on entry is the point the pointer crossed
    /// the boundary -- not where it ended up. A pointer that jumps rather
    /// than travels, which is what a warp or a fast flick to the top of the
    /// screen is, then reports the edge it came in through, and the panel
    /// opens or does not open depending on which edge that was.
    ///
    /// `NSEvent.mouseLocation` is already in the screen space the geometry
    /// is written against, so this needs no conversion either.
    private func report() {
        onPointerMoved?(NSEvent.mouseLocation)
    }
}
