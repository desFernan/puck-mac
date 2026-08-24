//
//  EditorPaneView.swift
//  Puck
//
//  Replaces EditorWebView -- a fully native file tree + tabs + syntax-
//  highlighted editor, backed directly by WorkspaceFileService instead of a
//  WKWebView pointed at workspace's EditorGateway. Branches on
//  ClientWorkspace's EditorAvailability, computed synchronously and locally
//  now that no round trip to workspace is needed to know whether a project
//  folder is usable.
//

import SwiftUI

struct EditorPaneView: View {
    let workspaceId: String
    let availability: EditorAvailability
    /// Called if store creation fails (the root turned out to be invalid at
    /// the moment of attaching) or a live store's watcher detects the root
    /// itself was moved/deleted -- the caller is expected to react by
    /// re-deriving ClientWorkspace.editorAvailability, this view doesn't own
    /// that decision.
    let onUnavailable: () -> Void
    /// The tank strip's frame, or nil when it is off screen. This view does
    /// not hold ClientWindowStore -- see onUnavailable above -- so reporting
    /// is threaded in the same way.
    let onTankFrameChange: (CGRect?) -> Void

    @State private var store: EditorPaneStore?

    var body: some View {
        VStack(spacing: 0) {
            PetTankView(onFrameChange: onTankFrameChange)
            paneContent
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch availability {
        case .noProject, .unavailable:
            EditorEmptyStateView(availability: availability)
        case .ready(let rootURL):
            if let store, store.workspaceId == workspaceId {
                EditorPaneContentView(store: store)
                    // Re-attach on a workspace switch. SwiftUI reuses this view
                    // when only its properties change, so onAppear does not
                    // fire again -- without this the pane kept showing the
                    // first project it was ever opened on while the sidebar,
                    // the status bar and the chat had all moved on.
                    .onChange(of: workspaceId) { attachStore(root: rootURL) }
            } else {
                Color.clear.onAppear { attachStore(root: rootURL) }
            }
        }
    }

    /// Idempotent for the workspace already attached; swaps the store
    /// otherwise. The pool keeps one store per workspace alive for the
    /// process's life, so switching back and forth costs nothing and keeps
    /// each workspace's open tabs.
    private func attachStore(root: URL) {
        guard store?.workspaceId != workspaceId else { return }
        do {
            store = try EditorPaneStorePool.shared.store(forWorkspace: workspaceId, root: root, onRootChanged: onUnavailable)
        } catch {
            onUnavailable()
        }
    }
}

/// The detached window's contents: the file list and the file, side by side.
///
/// The attached layout puts these in different columns of the main window --
/// explorer on the right, code beside the conversation -- but a window of its
/// own has no conversation to sit beside, so here they stay together.
private struct EditorPaneContentView: View {
    @ObservedObject var store: EditorPaneStore

    var body: some View {
        HSplitView {
            FileExplorerPane(store: store)
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
            CodeSplitView(store: store)
                .frame(minWidth: 360)
        }
    }
}
