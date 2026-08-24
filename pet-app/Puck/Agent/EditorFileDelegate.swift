//
//  EditorFileDelegate.swift
//  Puck
//
//  Lets the local agent (AgentRunner) reach read_file/open_in_editor, the
//  same way CodeEditorDelegate lets it reach code_editor. Placed here
//  (Puck/Agent, not PuckClient) for the same reason CodeEditorDelegate is:
//  PuckTests only depends on the Puck target, so anything that needs its
//  own test coverage has to live where @testable import Puck can reach it.
//
//  Unlike CodeEditorDelegate, this never crosses bridge.sock or waits on
//  workspace at all -- WorkspaceFileService/EditorPaneStorePool (also under
//  Puck/ClientWindow/Editor) read/write the project directly, so this type
//  is a thin adapter over them rather than a socket-correlation table.
//

import Foundation

final class EditorFileDelegate {
    /// workspaceId -> that workspace's bound project path, or nil for a
    /// pure-chat workspace / one AgentHost doesn't recognize. Injected
    /// rather than read from a store directly: this type has no business
    /// knowing ClientWindowStore exists, only that *something* can answer
    /// this one question.
    private let resolveProjectPath: (String) -> String?

    init(resolveProjectPath: @escaping (String) -> String?) {
        self.resolveProjectPath = resolveProjectPath
    }

    /// How many paths `listFiles` will return before truncating. A project
    /// tree is unbounded and this goes straight into the model's context, so
    /// the cap is the point -- 400 paths is enough to recognize a project and
    /// pick the next file to read, and small enough not to crowd out the
    /// conversation.
    static let listFileLimit = 400

    /// Paths containing `contains`, case-insensitively, anywhere in them --
    /// so "bubble" and "Input/Speech" both work.
    ///
    /// Applied before the cap, which is the whole point: truncating first and
    /// filtering second would search only the alphabetically-first 400 files.
    /// An empty or whitespace-only filter is treated as none rather than as a
    /// filter nothing can match.
    static func filtered(_ paths: [String], contains: String?) -> [String] {
        guard let needle = contains?.trimmingCharacters(in: .whitespacesAndNewlines), !needle.isEmpty else {
            return paths
        }
        return paths.filter { $0.range(of: needle, options: .caseInsensitive) != nil }
    }

    /// list_files' delegate body: the project's files as a flat list of
    /// relative paths.
    ///
    /// Added 2026-08-15. The agent could already *read* a file, but only if
    /// the user named it -- there was no way to find out what was in the
    /// project, or even that one was open, so "이 디렉토리 분석해줘" had no
    /// path to an answer and the model fell back to get_frontmost_window,
    /// which reports a window and knows nothing about directories.
    ///
    /// Flat rather than nested: the model only needs paths, and a nested JSON
    /// tree spends most of its tokens on structure.
    @MainActor
    func listFiles(workspaceId: String, contains: String? = nil) async -> DispatchedToolResult {
        guard let projectPath = resolveProjectPath(workspaceId) else {
            return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: Strings.text(.toolNoProjectLinked))
        }
        do {
            let service = try WorkspaceFileService(root: URL(fileURLWithPath: projectPath, isDirectory: true))
            let paths = Self.filtered(FileTreeEntry.flattenedPaths(try service.listTree()), contains: contains)
            let truncated = paths.count > Self.listFileLimit
            let data = JSONValue.object([
                "projectPath": .string(projectPath),
                "files": .array(paths.prefix(Self.listFileLimit).map(JSONValue.string)),
                "truncated": .bool(truncated),
                "totalCount": .number(Double(paths.count)),
                "filter": contains.map(JSONValue.string) ?? .null,
            ])
            return DispatchedToolResult(ok: true, data: data, error: nil, detail: nil)
        } catch let error as WorkspaceFileServiceError {
            return .failed(error.agentDetail)
        } catch {
            return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: error.localizedDescription)
        }
    }

    /// read_file's delegate body. A one-off WorkspaceFileService rather than
    /// going through EditorPaneStorePool -- a plain read has no tab/watcher
    /// state worth keeping alive, unlike openInEditor below.
    @MainActor
    func readFile(path: String, workspaceId: String) async -> DispatchedToolResult {
        guard let projectPath = resolveProjectPath(workspaceId) else {
            return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: Strings.text(.toolNoProjectLinked))
        }
        do {
            let service = try WorkspaceFileService(root: URL(fileURLWithPath: projectPath, isDirectory: true))
            let content = try service.readFile(at: path)
            let data = JSONValue.object([
                "path": .string(content.path),
                "content": .string(content.content),
                "language": content.language.map(JSONValue.string) ?? .null,
                "size": .number(Double(content.size)),
                "readOnly": .bool(content.readOnly),
            ])
            return DispatchedToolResult(ok: true, data: data, error: nil, detail: nil)
        } catch let error as WorkspaceFileServiceError {
            return .failed(error.agentDetail)
        } catch {
            return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: error.localizedDescription)
        }
    }

    /// open_in_editor's delegate body. Goes through the same
    /// EditorPaneStorePool the visible editor pane uses, so the tab the
    /// agent opens is actually there when the user looks -- and if the user
    /// already has the pane open on this workspace, this reuses that exact
    /// store rather than creating a second, disconnected one.
    @MainActor
    func openInEditor(path: String, workspaceId: String) async -> DispatchedToolResult {
        guard let projectPath = resolveProjectPath(workspaceId) else {
            return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: Strings.text(.toolNoProjectLinked))
        }
        do {
            let store = try EditorPaneStorePool.shared.store(
                forWorkspace: workspaceId,
                root: URL(fileURLWithPath: projectPath, isDirectory: true),
                onRootChanged: {}
            )
            store.open(path: path)
            if let lastError = store.lastError {
                return .failed(lastError.agentDetail)
            }
            return DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil)
        } catch let error as WorkspaceFileServiceError {
            return .failed(error.agentDetail)
        } catch {
            return DispatchedToolResult(ok: false, data: nil, error: "execution_failed", detail: error.localizedDescription)
        }
    }
}
