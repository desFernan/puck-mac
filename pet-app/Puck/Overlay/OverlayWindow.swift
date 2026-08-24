//
//  OverlayWindow.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  NSWindow subclass: borderless, transparent, click-through by default, level .floating
//

import AppKit

/// Transparent, borderless window hosting one display's SpriteLayerView.
/// plan/02_pet-app.md F1. `canBecomeKey`/`canBecomeMain` are false so this
/// never steals focus from whatever app the user is actually working in —
/// F6's text-input bubble is a separate window that's the deliberate
/// exception to that rule.
///
/// A non-activating panel rather than a plain window, and that is not a
/// detail: the pet becomes clickable the moment the cursor is over it
/// (ClickThroughController), and clicking a plain window brings its
/// application forward -- so grabbing the pet deactivated whatever the user
/// was in. On the island that was visible as the pet escaping: the chat
/// window stopped being frontmost the instant it was picked up, which is
/// exactly the condition that sends the pet back to the desktop. Refusing key
/// is not enough on its own; the application is activated either way.
final class OverlayWindow: NSPanel {
    convenience init(screenFrame: CGRect) {
        self.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
