//
//  EditorAvailability.swift
//  Puck
//
//  Whether a workspace's editor pane can open, resolved synchronously and
//  locally from its projectPath -- no round trip needed now that PuckClient
//  reads/writes files itself instead of waiting on workspace's
//  editor_view_ready. Replaces the old editorViewURL/editorUnavailableReason
//  pair on ClientWorkspace, which could only ever represent "no URL yet"
//  (indistinguishable between "no project" and "workspace hasn't connected")
//  -- this can tell a missing/inaccessible project folder apart from one
//  that was simply never set.
//

import Foundation

enum EditorAvailability: Equatable {
    case noProject
    case ready(rootURL: URL)
    case unavailable(EditorUnavailableReason)
}

enum EditorUnavailableReason: Equatable {
    /// The path existed when the workspace was created but doesn't now --
    /// moved or deleted.
    case pathMissing
    case notADirectory
    case notReadable
}

extension EditorAvailability {
    static func resolve(projectPath: String?) -> EditorAvailability {
        guard let projectPath else { return .noProject }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectPath, isDirectory: &isDirectory) else {
            return .unavailable(.pathMissing)
        }
        guard isDirectory.boolValue else {
            return .unavailable(.notADirectory)
        }
        guard FileManager.default.isReadableFile(atPath: projectPath) else {
            return .unavailable(.notReadable)
        }
        return .ready(rootURL: URL(fileURLWithPath: projectPath, isDirectory: true))
    }
}
