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
    /// Whether the notch this is drawn around is one the display already has.
    ///
    /// A real one is camera housing: nothing under it to click, so the shut
    /// panel may take the pointer there. A given one is drawn over live menu
    /// bar -- see `activeRect`.
    private var isVirtual = false

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
    func present(notchAppKitRect: CGRect?, isVirtual: Bool) {
        guard let notchAppKitRect else { return stop() }
        notch = notchAppKitRect
        self.isVirtual = isVirtual

        let panel = window ?? makeWindow()
        panel.setFrame(NotchPanelGeometry.windowFrame(notch: notchAppKitRect), display: true)
        panel.orderFrontRegardless()
        window = panel
        // Reasserted rather than left to setOpen: the panel may already have
        // been shut, and the notch it is shut around has just changed size.
        isOpen = false
        hosting?.rootView = shell(isOpen: false)
        hoverView?.activeRect = activeRect(isOpen: false)
        music.stop()
        // Shut means shut, including the half of it setOpen would have done.
        // A Space switch or a display change lands here while the panel is
        // open, and leaving `wantsKey` set left a panel drawn closed that
        // could still take the caret -- the thing wantsKey exists to stop.
        resignKeyhood()
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
        hover.onPointerMoved = { [weak self] cursor in
            guard let self else { return }
            guard let cursor else { return self.setOpen(false) }
            self.setOpen(NotchPanelGeometry.shouldBeOpen(
                cursor: cursor, notch: self.notch, isOpen: self.isOpen
            ))
        }
        panel.contentView = hover
        hoverView = hover

        let hosted = NSHostingView(rootView: shell(isOpen: false))
        hosted.autoresizingMask = [.width, .height]
        hosted.frame = hover.bounds
        hover.addSubview(hosted)
        hosting = hosted

        return panel
    }

    /// Every pointer move asks for a state, and most of them ask for the one
    /// it is already in. Rebuilding the SwiftUI tree and restarting the
    /// music timer on each of those would be a redraw per mouse move.
    private func setOpen(_ open: Bool) {
        guard open != isOpen else { return }
        isOpen = open
        // Key *before* the view is built, not after. The prompt field focuses
        // itself as it appears, and a window that cannot become key yet drops
        // that focus on the floor -- which is why the field used to need a
        // click. Key only while open, so the rest of the time a borderless
        // window cannot steal the caret from whatever the user is working in.
        (window as? NotchPanelWindow)?.wantsKey = open
        if open { window?.makeKeyAndOrderFront(nil) }

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
            resignKeyhood()
        }
    }

    /// Gives the caret back. Both halves, because `wantsKey` left set is a
    /// window that can take it again on the next click.
    private func resignKeyhood() {
        (window as? NotchPanelWindow)?.wantsKey = false
        if window?.isKeyWindow == true { window?.resignKey() }
    }

    /// What the pointer may *click* through to this window, in the window's
    /// own coordinates. AppKit's Y grows upward, so it hangs from the top.
    ///
    /// Empty while a given notch is shut, and only then. This window sits at
    /// `.statusBar`, above the menu bar, so whatever it claims it takes: over
    /// a real notch that is camera housing and there was never anything to
    /// click, but a given one is drawn over 185 points of live menu bar in
    /// the middle of the screen. An app with enough menus to reach there --
    /// Xcode's Source Control and Window, on a laptop display -- had them
    /// swallowed by a panel that was not even open.
    ///
    /// Hovering is unaffected: NotchHoverView's tracking area is the whole
    /// window and is deliberately not gated on this, so the panel still opens
    /// when the pointer arrives. Open, it takes the pointer either way --
    /// by then the user is pointing at a panel rather than at the menu bar.
    private func activeRect(isOpen: Bool) -> CGRect {
        guard isOpen || !isVirtual else { return .zero }
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
                // Passed in as well as gating the shell: the content is built
                // in both states so the field keeps what was typed across an
                // open and shut, which means `onAppear` fires once, while
                // shut, and never again. The view needs to be told.
                isOpen: isOpen,
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
