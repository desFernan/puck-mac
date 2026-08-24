//
//  OverlayWindowController.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Creates/positions one overlay window per display, orderOut when idle
//
//  TODO(perf, plan/02_pet-app.md F1): downshift frame rate 60->15 after 30s
//  idle, and orderOut windows on displays with no character on them. Needs
//  the FSM wired in (P2+) to know where the character actually is; placing
//  one window per display unconditionally is the correct starting point.

import AppKit

/// Creates and positions one OverlayWindow (hosting a SpriteLayerView) per
/// display, rebuilding whenever ScreenManager reports a display change.
/// Window frames use ScreenManager's `appKitFrames` (real AppKit screen
/// coordinates), NOT `normalizedScreenFrames` — the normalized, Y-down space
/// is for movement/FSM logic only; actual window placement needs AppKit's
/// own bottom-left-origin coordinates (plan/02_pet-app.md F3: every movement
/// rule works in pixels, and the transform happens only at render time).
/// `@MainActor`: an NSWindow and the layer tree the pet is drawn into. The
/// frame loop hops here before touching either.
@MainActor
final class OverlayWindowController {
    private(set) var windows: [OverlayWindow] = []
    private let screenManager: ScreenManager

    /// Fires every time `windows` is torn down and recreated (initial start()
    /// and every real display change) -- consumers holding a reference into a
    /// specific window/SpriteLayerView (e.g. the avatar's sprite layer parent)
    /// must re-fetch it here or they're left pointing at an orphaned window.
    var onWindowsRebuilt: (() -> Void)?

    init(screenManager: ScreenManager) {
        self.screenManager = screenManager
    }

    func start() {
        rebuildWindows(for: screenManager.current)
        screenManager.onChange = { [weak self] space in
            self?.rebuildWindows(for: space)
        }
        screenManager.startObserving()
    }

    func stop() {
        screenManager.stopObserving()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func rebuildWindows(for space: GlobalScreenSpace) {
        windows.forEach { $0.orderOut(nil) }
        windows = space.appKitFrames.map { frame in
            let window = OverlayWindow(screenFrame: frame)
            let spriteView = SpriteLayerView(frame: NSRect(origin: .zero, size: frame.size))
            spriteView.autoresizingMask = [.width, .height]
            window.contentView = spriteView
            window.orderFrontRegardless()
            return window
        }
        onWindowsRebuilt?()
    }
}
