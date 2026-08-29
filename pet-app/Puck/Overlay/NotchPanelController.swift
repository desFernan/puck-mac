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
import Combine
import SwiftUI

@MainActor
final class NotchPanelController {
    private var window: NSPanel?
    private var hoverView: NotchHoverView?
    private var hosting: NSHostingView<NotchPanelRoot>?
    /// The hardware notch, and the shape drawn around it -- which is wider
    /// while something is playing. The drawn one is what the pointer is
    /// measured against, so the wings are targets rather than decoration.
    private var notch: CGRect = .zero
    private var shutNotch: CGRect { NotchPanelGeometry.shutRect(notch: notch, isLive: isLive) }
    private var isLive: Bool { music.track != nil }
    private var isOpen = false

    /// What is playing. Owned here rather than by the view so it survives the
    /// view being rebuilt on every open and close, and so it can be polling
    /// only while somebody is looking at it.
    private let music = NowPlayingStore()
    private var liveness: AnyCancellable?

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
        // Reasserted rather than left to setOpen: the panel may already have
        // been shut, and the notch it is shut around has just changed size.
        isOpen = false
        hosting?.rootView = shell(isOpen: false)
        hoverView?.activeRect = activeRect(isOpen: false)
        music.start(every: NowPlayingStore.idleInterval)
        watchLiveness()
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
        liveness?.cancel()
        liveness = nil
        music.stop()
    }

    /// The wings appear when a song starts, and nobody is pointing at
    /// anything when that happens. SwiftUI redraws itself, but what the
    /// pointer can touch is AppKit's and has to be told.
    private func watchLiveness() {
        liveness?.cancel()
        liveness = music.$track
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, !self.isOpen else { return }
                self.hoverView?.activeRect = self.activeRect(isOpen: false)
            }
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
                cursor: cursor, notch: self.shutNotch, isOpen: self.isOpen
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
        // Kept running either way, because the shut notch shows what is
        // playing too -- but slowly, since a thumbnail and whether anything
        // is playing do not change between one second and the next.
        music.start(every: open ? NowPlayingStore.interval : NowPlayingStore.idleInterval)
        if !open { resignKeyhood() }
    }

    /// Gives the caret back. Both halves, because `wantsKey` left set is a
    /// window that can take it again on the next click.
    private func resignKeyhood() {
        (window as? NotchPanelWindow)?.wantsKey = false
        if window?.isKeyWindow == true { window?.resignKey() }
    }

    /// What the pointer can *click*, in the window's own coordinates.
    /// AppKit's Y grows upward, so it hangs from the window's top edge.
    ///
    /// Nothing at all while shut. On a display with no camera housing the
    /// panel draws its own notch, and that sits over live menu bar in the
    /// middle of the screen -- a status-bar-level window there swallows the
    /// clicks meant for whatever app owns those menus, which is what got the
    /// drawn notch taken out once already.
    ///
    /// Giving it up costs nothing, because the shut state has nothing to
    /// press: hovering is read from a tracking area, and a tracking area
    /// reports the pointer whether or not the view accepts clicks. So the
    /// panel still opens when you point at it, and the menu bar underneath
    /// keeps working until it does.
    private func activeRect(isOpen: Bool) -> CGRect {
        guard isOpen else { return .zero }
        let size = window?.frame.size ?? .zero
        return CGRect(
            x: (size.width - NotchPanelGeometry.openWidth) / 2,
            y: size.height - NotchPanelGeometry.openHeight,
            width: NotchPanelGeometry.openWidth,
            height: NotchPanelGeometry.openHeight
        )
    }

    private func shell(isOpen: Bool) -> NotchPanelRoot {
        NotchPanelRoot(
            music: music,
            isOpen: isOpen,
            notch: notch.size,
            toysOut: toysOut?() ?? [],
            onToggleToy: { [weak self] toy in self?.onToggleToy?(toy) ?? [] },
            onSubmit: { [weak self] text in self?.onSubmit?(text) }
        )
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
