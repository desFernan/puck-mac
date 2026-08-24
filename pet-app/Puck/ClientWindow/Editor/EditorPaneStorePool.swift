//
//  EditorPaneStorePool.swift
//  Puck
//
//  One EditorPaneStore per workspace the user (or a tool call) has actually
//  opened the editor for, kept alive for the rest of the process -- same
//  "no eviction until quit" shape the old EditorWebViewPool used for its
//  WKWebViews, so open tabs/scroll state survive the chat-web toggle.
//  Unlike that pool, each entry here holds a live FSEvents stream, which
//  WorkspaceFileWatcher.stop() tears down in EditorPaneStore's deinit.
//

import Foundation

/// Main-thread only, and now stated rather than conventional: every caller
/// is a SwiftUI view or the store it owns, and under strict concurrency a
/// shared mutable singleton has to say which actor it belongs to.
@MainActor
final class EditorPaneStorePool {
    static let shared = EditorPaneStorePool()

    private var storesByWorkspace: [String: EditorPaneStore] = [:]

    private init() {}

    /// Gets the existing store for `workspaceId`, or creates one against
    /// `root` if none exists yet. Throws only if creation is needed and the
    /// root turns out to be invalid at that moment (a narrow race with
    /// whatever validated `root` just before calling this).
    @discardableResult
    func store(forWorkspace workspaceId: String, root: URL, onRootChanged: @escaping () -> Void) throws -> EditorPaneStore {
        if let existing = storesByWorkspace[workspaceId], existing.watches(root) {
            // The latest caller's callback wins -- see EditorPaneStore.onRootChanged's doc comment.
            existing.onRootChanged = onRootChanged
            return existing
        }
        // A store keyed on the workspace but watching a different directory
        // would show one project's files under another's name, with a file
        // watcher on the wrong tree. Nothing repoints a workspace today; this
        // is what stops that staying true by accident.
        let created = try EditorPaneStore(workspaceId: workspaceId, root: root, onRootChanged: onRootChanged)
        storesByWorkspace[workspaceId] = created
        return created
    }

    /// The existing store for `workspaceId`, if the editor pane (or a tool
    /// call routed through it) has created one before -- never creates one
    /// itself. Tool handlers that shouldn't implicitly start a workspace's
    /// file watcher just because the AI asked to open a file use this.
    func existingStore(forWorkspace workspaceId: String) -> EditorPaneStore? {
        storesByWorkspace[workspaceId]
    }
}
