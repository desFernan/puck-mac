//
//  ClientWorkspace.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  A workspace (project folder or pure-chat) shown in the sidebar's
//  workspace switcher (plan/02_pet-app.md F13, plan/01_protocol.md 3.4).
//

import Foundation

struct ClientWorkspace: Identifiable, Equatable {
    /// The name WorkspaceRegistry writes for the workspace the app creates
    /// for itself. Stored and sent over the bridge, so it is deliberately
    /// language-independent; `displayName` is where the language enters.
    /// Defined here rather than on the registry because both targets compile
    /// this file and only Puck compiles that one.
    static let defaultName = "기본 워크스페이스"

    let id: String
    var name: String
    /// nil for a pure-chat workspace -- code_editor and the editor pane are
    /// unavailable for it.
    var projectPath: String?
    /// Cached rather than recomputed on every read: resolving this touches
    /// the filesystem (EditorAvailability.resolve), and ClientWorkspace
    /// values get read from SwiftUI body evaluations often enough that a
    /// syscall there would be a real hot path. Refreshed via
    /// refreshEditorAvailability() -- see ClientWindowStore for the call
    /// sites (workspace creation, editor toggle opened, watcher-detected
    /// root loss).
    private(set) var editorAvailability: EditorAvailability

    init(id: String, name: String, projectPath: String?) {
        self.id = id
        self.name = name
        self.projectPath = projectPath
        editorAvailability = EditorAvailability.resolve(projectPath: projectPath)
    }

    /// The name to show. The one workspace this app creates for itself is
    /// stored under a language-independent name (see
    /// `ClientWorkspace.defaultName`), so this is where it becomes
    /// words; a workspace the user named stands as-is.
    var displayName: String {
        name == Self.defaultName ? Strings.text(.workspaceDefaultName) : name
    }

    /// The project as a person names it out loud: the last two path
    /// components. The head of an absolute path is the least informative part
    /// of it and the same for every project on the machine, so truncating
    /// from the front -- which is what a narrow column does -- hides the only
    /// part that identifies anything.
    var projectLabel: String? {
        guard let projectPath else { return nil }
        let parts = (projectPath as NSString).pathComponents.filter { $0 != "/" }
        return parts.suffix(2).joined(separator: "/")
    }

    var canOpenEditor: Bool {
        if case .ready = editorAvailability { return true }
        return false
    }

    mutating func refreshEditorAvailability() {
        editorAvailability = EditorAvailability.resolve(projectPath: projectPath)
    }
}
