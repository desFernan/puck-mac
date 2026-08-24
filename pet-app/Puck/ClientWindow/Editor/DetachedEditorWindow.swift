//
//  DetachedEditorWindow.swift
//  Puck
//
//  The editor in its own window (2026-08-16).
//
//  Same process, same EditorPaneStorePool: the detached window and the split
//  pane are two views of one store per workspace, so open tabs, unsaved edits
//  and the file watcher survive being moved either way. A separate *app* would
//  have had to synchronise that over the bridge -- the kind of complexity this
//  repo just spent a day removing.
//
//  Owned by a SwiftUI modifier rather than AppDelegate because the state that
//  decides whether it should exist (EditorPresentation) lives in the view. The
//  window is created on the first detach and reused after that: an editor
//  someone re-detaches should come back where they left it, not centred again.
//

import AppKit
import SwiftUI

/// Presents `EditorPaneView` in its own window while `presentation` is
/// `.detached`, and closes it otherwise.
struct DetachedEditorWindowPresenter: ViewModifier {
    @Binding var presentation: EditorPresentation
    let workspaceId: String
    let availability: EditorAvailability
    let palette: ClientPalette
    let onUnavailable: () -> Void

    func body(content: Content) -> some View {
        content
            .background(
                DetachedEditorWindowHost(
                    presentation: $presentation,
                    workspaceId: workspaceId,
                    availability: availability,
                    palette: palette,
                    onUnavailable: onUnavailable
                )
                .frame(width: 0, height: 0)
            )
    }
}

private struct DetachedEditorWindowHost: NSViewRepresentable {
    @Binding var presentation: EditorPresentation
    let workspaceId: String
    let availability: EditorAvailability
    let palette: ClientPalette
    let onUnavailable: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.sync(self)
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.sync(self)
    }

    /// `@MainActor`: it owns an NSWindow and a hosting controller, and every
    /// entry point into it is SwiftUI's own update pass or an NSWindowDelegate
    /// callback -- both on the main thread.
    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private var window: NSWindow?
        private var hosting: NSHostingController<AnyView>?
        private var onClose: (() -> Void)?

        func sync(_ host: DetachedEditorWindowHost) {
            let pane = AnyView(
                EditorPaneView(
                    workspaceId: host.workspaceId,
                    availability: host.availability,
                    onUnavailable: host.onUnavailable,
                    // Detached, this pane is a different window: its strip is
                    // not part of the client window's tank, so there is
                    // nothing to report -- ClientWindowView already cleared
                    // the segment when the editor left the split.
                    onTankFrameChange: { _ in }
                )
                .environment(\.clientPalette, host.palette)
            )
            // Closing the window is how the user re-attaches, so the binding
            // has to be written from the delegate as well as read here.
            onClose = { host.presentation = .attached }

            guard host.presentation == .detached else {
                close()
                return
            }
            if let hosting {
                hosting.rootView = pane
                return
            }
            present(pane, title: host.workspaceId)
        }

        private func present(_ pane: AnyView, title: String) {
            let controller = NSHostingController(rootView: pane)
            // Same reason ClientWindow does it: left at the default, the
            // hosting controller keeps pushing its fitting size onto the
            // window and the explicit content size never sticks.
            controller.sizingOptions = []
            let newWindow = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 900, height: 700),
                styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            newWindow.title = Strings.text(.chatEditor)
            newWindow.isReleasedWhenClosed = false
            newWindow.contentViewController = controller
            newWindow.setContentSize(CGSize(width: 900, height: 700))
            // Its own floor: the file tree plus a code column, without the
            // chat's share (ClientTheme.Metrics).
            newWindow.minSize = CGSize(
                width: ClientTheme.Metrics.editorWindowMinWidth,
                height: ClientTheme.Metrics.windowMinHeight
            )
            newWindow.center()
            newWindow.delegate = self
            newWindow.makeKeyAndOrderFront(nil)
            window = newWindow
            hosting = controller
        }

        private func close() {
            guard let window else { return }
            window.delegate = nil
            window.close()
            self.window = nil
            hosting = nil
        }

        func windowWillClose(_ notification: Notification) {
            // Back into the split rather than to `.hidden`: the user asked for
            // the editor at some point and closing the extra window reads as
            // "put it back", not "I'm done with it". ⇧⌘E still hides it.
            window = nil
            hosting = nil
            onClose?()
        }
    }
}

extension View {
    func detachedEditorWindow(
        presentation: Binding<EditorPresentation>,
        workspaceId: String,
        availability: EditorAvailability,
        palette: ClientPalette,
        onUnavailable: @escaping () -> Void
    ) -> some View {
        modifier(DetachedEditorWindowPresenter(
            presentation: presentation,
            workspaceId: workspaceId,
            availability: availability,
            palette: palette,
            onUnavailable: onUnavailable
        ))
    }
}
