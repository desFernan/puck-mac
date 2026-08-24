//
//  PaneFrameReporter.swift
//  Puck
//
//  Publishes the editor pane's on-screen rect so the pet can be sent to it.
//  An NSView rather than a GeometryReader: GeometryReader reports view-local
//  coordinates, and only the backing view knows where its window is, which
//  is the part the pet needs.
//

import AppKit
import SwiftUI

struct PaneFrameReporter: NSViewRepresentable {
    let onChange: (CGRect?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ReportingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ReportingView)?.onChange = onChange
    }

    /// `@MainActor`: an NSView, reporting its frame from `layout()` and the
    /// window notifications AppKit delivers on the main thread.
    @MainActor
    final class ReportingView: NSView {
        var onChange: ((CGRect?) -> Void)?
        private let windowObservers = NotificationTokens()

        /// Moving a window lays nothing out, so `layout()` never runs and the
        /// rect reported from it goes stale the moment the window is dragged:
        /// the pet stayed standing where the window used to be. The window's
        /// own notifications are the only thing that says it moved.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observeWindow()
            report()
        }

        // No deinit: NotificationTokens unregisters itself when this view
        // releases it, which is the only way a nonisolated deinit and
        // main-actor state can both be honest about each other.

        private func observeWindow() {
            windowObservers.removeAll()
            guard let window else { return }
            // The displays themselves, not only this window: unplugging a
            // second monitor while this window stays put moves nothing and
            // resizes nothing, so none of the notifications below fire -- and
            // pet-app, which rebuilds its overlay on exactly that event, is
            // left holding a rect measured against a window that no longer
            // exists. Observed with `object: nil` because it is posted by the
            // application, not by a window.
            windowObservers.observe(
                NSApplication.didChangeScreenParametersNotification,
                object: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }
            // Screen changes matter as much as moves: the same window on a
            // display with a different origin is a different rect in the
            // coordinates the pet lives in.
            for name: NSNotification.Name in [
                NSWindow.didMoveNotification,
                NSWindow.didResizeNotification,
                NSWindow.didChangeScreenNotification,
            ] {
                windowObservers.observe(name, object: window) { [weak self] _ in
                    // `queue: .main` (NotificationTokens' default) is what
                    // makes this true; a notification block is not isolated in
                    // its signature, so the compiler cannot see it.
                    MainActor.assumeIsolated { self?.report() }
                }
            }
        }

        override func layout() {
            super.layout()
            report()
        }

        private func report() {
            guard let window, window.isVisible else {
                onChange?(nil)
                return
            }
            onChange?(window.convertToScreen(convert(bounds, to: nil)))
        }
    }
}
