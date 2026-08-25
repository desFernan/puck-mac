//
//  OverlayWindowController.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Creates/positions the overlay window, rebuilding on display changes
//
//  TODO(perf, plan/02_pet-app.md F1): downshift frame rate 60->15 after 30s
//  idle. Needs the FSM wired in (P2+) to know when nothing is moving.

import AppKit

/// Creates and positions the single OverlayWindow (hosting a SpriteLayerView)
/// the pet is drawn in, rebuilding whenever ScreenManager reports a display
/// change.
///
/// One window covering every display, not one per display. The pet is one
/// character in one layer tree: a window per display means deciding which one
/// it belongs to on every frame, reparenting its layer and rebasing its
/// coordinates the moment it crosses an edge -- and any place that forgets to
/// ask loses the pet on the other monitor. Covering the whole arrangement
/// makes crossing from one display to the next ordinary movement, and leaves
/// exactly one coordinate space between the pet and the screen. What the
/// window cannot say -- that the box around several displays contains space
/// belonging to none of them -- is ScreenGround's job.
///
/// The frame comes from ScreenManager's `appKitBounds` (real AppKit screen
/// coordinates), NOT the normalized Y-down space -- that one is for
/// movement/FSM logic only; actual window placement needs AppKit's own
/// bottom-left-origin coordinates (plan/02_pet-app.md F3: every movement rule
/// works in pixels, and the transform happens only at render time).
/// `@MainActor`: an NSWindow and the layer tree the pet is drawn into. The
/// frame loop hops here before touching either.
@MainActor
final class OverlayWindowController {
    private(set) var window: OverlayWindow?
    private let screenManager: ScreenManager

    /// Fires every time the window is torn down and recreated (initial
    /// start() and every real display change) -- consumers holding a
    /// reference into it or its SpriteLayerView (e.g. the avatar's sprite
    /// layer parent) must re-fetch it here or they're left pointing at an
    /// orphaned window.
    var onWindowsRebuilt: (() -> Void)?

    init(screenManager: ScreenManager) {
        self.screenManager = screenManager
    }

    func start() {
        rebuildWindow(for: screenManager.current)
        screenManager.onChange = { [weak self] space in
            self?.rebuildWindow(for: space)
        }
        screenManager.startObserving()
    }

    func stop() {
        screenManager.stopObserving()
        window?.orderOut(nil)
        window = nil
    }

    private func rebuildWindow(for space: GlobalScreenSpace) {
        window?.orderOut(nil)
        let frame = space.appKitBounds
        let overlay = OverlayWindow(screenFrame: frame)
        let spriteView = SpriteLayerView(frame: NSRect(origin: .zero, size: frame.size))
        spriteView.autoresizingMask = [.width, .height]
        overlay.contentView = spriteView
        overlay.orderFrontRegardless()
        window = overlay
        onWindowsRebuilt?()
    }
}
