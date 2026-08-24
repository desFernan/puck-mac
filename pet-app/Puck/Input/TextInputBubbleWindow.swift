//
//  TextInputBubbleWindow.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  canBecomeKey borderless bubble window, restores frontmost app on close
//
//  The one deliberate exception to OverlayWindow's "never take focus" rule
//  (plan/02_pet-app.md F1/F6) — this window hosts the text-input bubble and
//  must become key so the user can actually type into it.

import AppKit

final class TextInputBubbleWindow: NSWindow, NSWindowDelegate {
    private(set) var previouslyFrontmostApp: NSRunningApplication?
    /// Injectable for tests -- real NSWorkspace frontmost-app state can't be
    /// relied on to change inside a test runner the way it does in a live app.
    var frontmostAppProvider: () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }

    convenience init(contentRect: CGRect) {
        self.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Drag it anywhere by its blurred background. Dragging by the text
        // itself still selects text, as it does in any field.
        isMovableByWindowBackground = true
        delegate = self
    }

    /// True once the user has dragged the panel somewhere, after which the
    /// caller stops placing it -- being yanked back to the default spot on
    /// every open is the whole point of moving it.
    private(set) var wasMovedByUser = false

    func windowDidMove(_ notification: Notification) {
        // The caller positions the panel while it is hidden, so only a move
        // that happens on screen can be the user's own drag.
        guard isVisible else { return }
        wasMovedByUser = true
    }

    override var canBecomeKey: Bool { true }

    /// Clicking away dismisses the panel, the way Spotlight's does. The
    /// caller supplies this rather than the window closing itself, because
    /// dismissing also has to unpin the pet.
    var onDismiss: (() -> Void)?

    override func resignKey() {
        super.resignKey()
        // closeAndRestoreFocus() activates the previous app, which resigns key
        // again -- without this the dismissal would run twice.
        guard isVisible else { return }
        onDismiss?()
    }

    /// Remembers whichever app is frontmost right now, then takes focus.
    /// Skips recapturing while already visible: this window itself would be
    /// frontmost at that point (a re-triggered hotkey while the bubble is
    /// still open), so recapturing would clobber the real target app with
    /// Puck -- closeAndRestoreFocus() would then "restore" focus to
    /// Puck instead of the app the user actually invoked this from.
    func showAndActivate() {
        // The window is shared with speech, so opening the input panel has to
        // take the flag back or the panel would start chasing the pet.
        isShowingSpeech = false
        guard !isVisible else {
            makeKeyAndOrderFront(nil)
            return
        }
        previouslyFrontmostApp = frontmostAppProvider()
        // Puck is LSUIElement/.accessory, and a background app's window
        // can be "key" without the app being active -- the keystrokes still
        // go to whatever app is frontmost, so the bubble appeared but typing
        // landed somewhere else. Activating is what actually hands the keyboard over;
        // closeAndRestoreFocus() gives it back afterwards.
        NSApp.activate(ignoringOtherApps: true)
        // Spotlight fades in rather than popping. Short enough not to be in
        // the way of typing immediately.
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
    }

    /// True while the bubble is up as the pet's speech rather than as the
    /// input panel. The frame loop reads this to keep speech anchored to a
    /// pet that walks away mid-sentence; the input panel deliberately stays
    /// where it is, because the user is aiming at it.
    private(set) var isShowingSpeech = false

    /// Shows the bubble as the pet *speaking*: visible, but it never becomes
    /// key and never activates Puck.
    ///
    /// showAndActivate() is wrong for speech in both directions. Taking focus
    /// interrupts whatever the user is typing for the sake of a message they
    /// only need to read — and worse, it made speech invisible in practice:
    /// `resignKey` dismisses this window, and a background LSUIElement app
    /// that activates while another app is frontmost loses key almost
    /// immediately, so the bubble closed in the same breath it opened.
    func showSpeech() {
        isShowingSpeech = true
        alphaValue = 0
        // Regardless: Puck is .accessory and usually not the active app,
        // which is exactly when the pet has something to say.
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
    }

    /// Hides the bubble *without* restoring focus -- for submit, where focus
    /// is about to go to PuckClient's window instead of back to the app
    /// the user invoked the bubble from (2026-07-30).
    func closeAndYieldFocus() {
        isShowingSpeech = false
        orderOut(nil)
        previouslyFrontmostApp = nil
    }

    /// Hides the bubble and restores focus to whatever was frontmost before `showAndActivate()`.
    func closeAndRestoreFocus() {
        isShowingSpeech = false
        orderOut(nil)
        previouslyFrontmostApp?.activate()
        previouslyFrontmostApp = nil
    }
}
