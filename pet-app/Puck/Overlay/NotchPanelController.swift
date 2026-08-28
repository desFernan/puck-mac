//
//  NotchPanelController.swift
//  Puck
//
//  The notch, and the panel it opens into when you point at it.
//
//  Its own window rather than something drawn in the pet's overlay, for one
//  reason: the overlay sits at `.floating`, below the menu bar, and a panel
//  that opens across the menu bar has to be above it.
//
//  It takes the pointer only where it is drawn -- see NotchHoverView, which
//  is also where the reason for a tracking area rather than a global event
//  monitor is written down.
//
//  `@MainActor`: it owns a window and a hosting view.
//

import AppKit
import SwiftUI

@MainActor
final class NotchPanelController {
    private var window: NSPanel?
    private var hoverView: NotchHoverView?
    private var hosting: NSHostingView<NotchShell<NotchPanelView>>?
    private var notch: CGRect = .zero
    private var isOpen = false

    /// What is playing. Owned here rather than by the view so it survives the
    /// view being rebuilt on every open and close, and so it can be polling
    /// only while somebody is looking at it.
    private let music = NowPlayingStore()

    /// Which toys are out. Asked at the moment the panel opens, because it
    /// can change while it is shut -- the status item's panel puts toys out
    /// too, and so does the pet kicking one away.
    var toysOut: (() -> Set<String>)?
    var onToggleToy: ((Toy) -> Set<String>)?
    var onSubmit: ((String) -> Void)?

    /// Shows the notch at `appKitRect`, or takes it away when there is none.
    ///
    /// Called wherever the screens are measured, so an unplugged monitor or a
    /// resolution change moves it without anything else having to remember.
    func present(notchAppKitRect: CGRect?) {
        guard let notchAppKitRect else { return stop() }
        notch = notchAppKitRect

        let panel = window ?? makeWindow()
        panel.setFrame(NotchPanelGeometry.windowFrame(notch: notchAppKitRect), display: true)
        panel.orderFrontRegardless()
        window = panel
        setOpen(false)
    }

    func stop() {
        window?.orderOut(nil)
        window = nil
        hoverView = nil
        hosting = nil
        isOpen = false
        music.stop()
    }

    private func makeWindow() -> NSPanel {
        let panel = NotchPanelWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the menu bar, which is the whole reason this is not drawn in
        // the pet's overlay.
        panel.level = .statusBar
        // Present in every Space, including a fullscreen one -- the notch does
        // not go away when an app does.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let hover = NotchHoverView(frame: .zero)
        hover.autoresizingMask = [.width, .height]
        hover.onHoverChanged = { [weak self] isInside in self?.setOpen(isInside) }
        panel.contentView = hover
        hoverView = hover

        let hosted = NSHostingView(rootView: shell(isOpen: false))
        hosted.autoresizingMask = [.width, .height]
        hosted.frame = hover.bounds
        hover.addSubview(hosted)
        hosting = hosted

        return panel
    }

    private func setOpen(_ open: Bool) {
        isOpen = open
        hosting?.rootView = shell(isOpen: open)
        // What the pointer can touch follows what is drawn: the notch alone
        // while closed, so the rest of the menu bar keeps working, and the
        // whole panel once it is open, so moving down into it does not
        // immediately close it again.
        hoverView?.activeRect = activeRect(isOpen: open)
        // Asking a music app what it is playing costs a few milliseconds
        // over Automation, so it is asked only while the panel is open --
        // once a second forever for a panel nobody is looking at is a cost
        // nobody agreed to.
        if open {
            music.start()
        } else {
            music.stop()
        }
        // Key only while open, so the field can take typing -- a borderless
        // window that can become key while nobody is looking at it steals the
        // caret from whatever the user is working in.
        (window as? NotchPanelWindow)?.wantsKey = open
        if open {
            window?.makeKeyAndOrderFront(nil)
        } else if window?.isKeyWindow == true {
            window?.resignKey()
        }
    }

    /// The drawn shape, in the window's own coordinates. AppKit's Y grows
    /// upward, so both hang from the window's top edge.
    private func activeRect(isOpen: Bool) -> CGRect {
        let size = window?.frame.size ?? .zero
        let width = isOpen ? NotchPanelGeometry.openWidth : notch.width
        let height = isOpen ? NotchPanelGeometry.openHeight : notch.height
        return CGRect(
            x: (size.width - width) / 2,
            y: size.height - height,
            width: width,
            height: height
        )
    }

    private func shell(isOpen: Bool) -> NotchShell<NotchPanelView> {
        NotchShell(isOpen: isOpen, notchSize: notch.size) {
            NotchPanelView(
                music: self.music,
                toysOut: self.toysOut?() ?? [],
                onToggleToy: { [weak self] toy in self?.onToggleToy?(toy) ?? [] },
                onSubmit: { [weak self] text in self?.onSubmit?(text) }
            )
        }
    }
}

/// The panel's window.
///
/// `constrainFrameRect` is the whole reason this is a subclass. AppKit moves
/// a window down so it does not cover the menu bar, which for this one is
/// exactly backwards -- it is a notch, its whole job is to be up there, and
/// unconstrained it was landing 62 points below where it belonged, hanging in
/// the middle of the screen.
final class NotchPanelWindow: NSPanel {
    /// Set while the panel is open. Closed, it must not take the caret from
    /// whatever the user is working in.
    var wantsKey = false

    override var canBecomeKey: Bool { wantsKey }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
