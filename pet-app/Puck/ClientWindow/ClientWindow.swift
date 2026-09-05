//
//  ClientWindow.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  A regular titled/resizable window (unlike OverlayWindow/TextInputBubbleWindow,
//  this one is a real app window, not a floating/borderless overlay) -- it's
//  the persistent "Claude Desktop"-style client, not a transient popup.
//

import AppKit

final class ClientWindow: NSWindow {
    /// Fired when the user closes the window -- AppDelegate un-pins the
    /// character (F3 Pinned state) from here.
    var onWillClose: (() -> Void)?

    convenience init(contentRect: CGRect) {
        self.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = AppIdentity.displayName
        isReleasedWhenClosed = false
        applyGlassChrome()
        delegate = self
    }

    func showAndActivate() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension ClientWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onWillClose?()
    }
}

extension NSWindow {
    /// The house window chrome (client window, settings window): content runs
    /// up under a transparent titlebar so the view's own vibrant background
    /// reaches the traffic lights, instead of a separate gray titlebar strip
    /// -- the plain-titlebar look was part of what read as a generic
    /// default macOS settings pane rather than something custom.
    ///
    /// 2026-08-02: tried adding `isOpaque = false`/`backgroundColor = .clear`
    /// here too, on the theory that the window's own opaque default
    /// background was leaking through around the traffic lights, visibly
    /// mismatched from the rest of the chrome. Made it worse, not better -- a real
    /// screenshot showed a visibly translucent patch appear right where the
    /// traffic lights sit. Reverted. The likely reason: unlike
    /// `OverlayWindow`/`TextInputBubbleWindow` (both `.borderless`, no
    /// titlebar at all), this window is `.titled` with
    /// `fullSizeContentView` -- it still has a real native titlebar
    /// container view hosting the traffic lights, layered above the content.
    /// Making the *window* non-opaque exposes that native layer's own
    /// vibrancy/translucency against the desktop behind it instead of
    /// against our dark content, which reads as a mismatched patch rather
    /// than fixing one. The `isOpaque`/`backgroundColor` trick only applies
    /// to genuinely borderless windows; a titled window's titlebar area
    /// needs a different fix, not discovered yet -- see PROGRESS.md.
    func applyGlassChrome() {
        styleMask.insert(.fullSizeContentView)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        // No hairline under the titlebar, ever. `.automatic` draws one as soon
        // as AppKit decides scrollable content sits directly beneath it, which
        // is a rule for a window with a titlebar strip -- and this window is
        // one continuous backdrop with the toolbar's own material hidden
        // (ClientWindowView). Where it showed up was with the island folded:
        // open, the island is a non-scrolling strip under the toolbar and the
        // line stayed away; folded, it gets out of the way and the pane behind
        // it becomes what is under the titlebar, so a line appeared across the
        // window that nothing in the design puts there.
        titlebarSeparatorStyle = .none
    }
}
