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

import AppKit

final class NotchHoverView: NSView {
    /// Where the pointer counts, in this view's own coordinates: the notch
    /// while closed, the whole panel while open.
    var activeRect: CGRect = .zero {
        didSet {
            guard activeRect != oldValue else { return }
            rebuildTrackingArea()
        }
    }

    var onHoverChanged: ((Bool) -> Void)?

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
        guard !activeRect.isEmpty else {
            tracking = nil
            return
        }
        // `.activeAlways` rather than `.activeInKeyWindow`: this panel is
        // never the key window until somebody types in it, and by then they
        // have already had to point at it.
        let area = NSTrackingArea(
            rect: activeRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
}
