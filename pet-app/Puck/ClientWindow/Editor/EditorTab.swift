//
//  EditorTab.swift
//  Puck
//
//  One open file in the editor pane. `content` is the live, possibly-edited
//  draft; `savedContent`/`revision` are what's actually confirmed on disk,
//  which is what isDirty and the next save's optimistic-concurrency check
//  compare against.
//

import Foundation

struct EditorTab: Identifiable, Equatable {
    let path: String
    var content: String
    var savedContent: String
    var revision: String
    var readOnly: Bool
    var language: String?
    var previewUrl: String?
    var mimeType: String?
    /// Set when the disk copy has changed since this tab last synced with
    /// it -- either a failed save (revision mismatch) or an external edit
    /// detected while the tab was open. Cleared by keepMine/useDisk.
    var diskChanged = false
    /// Bumped every time the file is taken on from disk. The editor view is
    /// keyed on it: CodeEditSourceEditor reads its text binding when it is
    /// built and pushes edits outward after that, so a write it did not make
    /// never reaches the screen unless the view is rebuilt. Counting only
    /// adoptions keeps typing and ⌘S from rebuilding it, which would throw
    /// the caret to the top of the file mid-edit.
    private(set) var adoptions = 0

    /// Takes on the file's current contents, discarding nothing -- only
    /// called for a tab with no unsaved edits (EditorPaneStore's watcher).
    mutating func adopt(_ fileContent: FileContent) {
        content = fileContent.content
        savedContent = fileContent.content
        revision = fileContent.revision
        diskChanged = false
        adoptions += 1
    }

    var id: String { path }
    var isDirty: Bool { content != savedContent }
    var isImage: Bool { previewUrl != nil }

    init(_ fileContent: FileContent) {
        path = fileContent.path
        content = fileContent.content
        savedContent = fileContent.content
        revision = fileContent.revision
        readOnly = fileContent.readOnly
        language = fileContent.language
        previewUrl = fileContent.previewUrl
        mimeType = fileContent.mimeType
    }
}
