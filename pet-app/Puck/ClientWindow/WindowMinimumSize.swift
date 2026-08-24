//
//  WindowMinimumSize.swift
//  Puck
//
//  Keeps the hosting NSWindow's `minSize` in step with what the view is
//  currently showing (2026-08-15).
//
//  Why this exists rather than `.frame(minWidth:)`: PuckClient sets
//  `sizingOptions = []` on its hosting controller (so SwiftUI's fitting size
//  never yanks the window around), which also means a SwiftUI minimum is not
//  a real resize limit -- `NSWindow.minSize` is. The floor also is not one
//  number: opening the editor pane adds a whole column, and a single value
//  that fits both is either too tall a floor for chat alone or too short for
//  chat plus editor. The second case is the one that shipped: the shortfall
//  came out of the file tree and clipped its rows.
//

import AppKit
import SwiftUI

struct WindowMinimumSize: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // Applied on the next runloop pass: at makeNSView time the view is not
        // in a window yet, so `view.window` is nil.
        DispatchQueue.main.async {
            apply(to: view)
            context.coordinator.observe(view.window, floor: floor)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            apply(to: nsView)
            context.coordinator.observe(nsView.window, floor: floor)
        }
    }

    private var floor: CGSize { CGSize(width: width, height: height) }

    /// Puts the floor back whenever the window ends up under it.
    ///
    /// `minSize` alone is not enough: AppKit enforces it while the user drags
    /// a corner and not at all for a frame set any other way -- a display
    /// change, window restoration, Stage Manager, or anything scripting the
    /// window. Under the floor the panes do not compress, they overflow: the
    /// sidebar slides out of view and the editor's empty state is cut off
    /// mid-sentence.
    /// `@MainActor`: an NSViewRepresentable's coordinator is only ever
    /// touched by SwiftUI's update pass and by AppKit callbacks, both of
    /// which are the main thread.
    @MainActor
    final class Coordinator {
        private let observers = NotificationTokens()
        private var floor: CGSize = .zero
        private weak var observed: NSWindow?

        func observe(_ window: NSWindow?, floor: CGSize) {
            self.floor = floor
            guard let window, window !== observed else { return }
            observed = window
            observers.removeAll()
            observers.observe(NSWindow.didResizeNotification, object: window) { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                // Delivered on `.main` by the queue above, which the
                // signature of a notification block cannot say.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Self.grow(window, toAtLeast: self.floor)
                }
            }
        }

        // No deinit: NotificationTokens unregisters itself when this
        // coordinator releases it -- see its own header for why that is not
        // the same as doing it here.

        static func grow(_ window: NSWindow, toAtLeast floor: CGSize) {
            let size = window.frame.size
            guard size.width < floor.width || size.height < floor.height else { return }
            var frame = window.frame
            // From the top-left, the corner macOS windows are anchored to:
            // growing from the origin would walk the title bar off screen.
            frame.origin.y -= max(0, floor.height - size.height)
            frame.size = CGSize(
                width: max(size.width, floor.width),
                height: max(size.height, floor.height)
            )
            window.setFrame(frame, display: true)
        }
    }

    private func apply(to view: NSView) {
        guard let window = view.window else { return }
        window.minSize = CGSize(width: width, height: height)
        // Raising the floor above the current size does not resize the window
        // on its own, so opening the editor in an already-narrow window has to
        // grow it here.
        Coordinator.grow(window, toAtLeast: floor)
    }
}
