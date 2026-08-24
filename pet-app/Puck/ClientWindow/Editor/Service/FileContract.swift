//
//  FileContract.swift
//  Puck
//
//  Swift port of workspace/src/shared/file-contract.ts -- the data shapes
//  WorkspaceFileService produces/consumes, kept 1:1 with the TS originals.
//

import Foundation

enum FileEntryKind: String, Equatable {
    case file, directory, symlink
}

struct FileTreeEntry: Identifiable, Equatable {
    let name: String
    let path: String
    let kind: FileEntryKind
    var children: [FileTreeEntry]?

    /// Path, not a fresh UUID: SwiftUI's List(_:children:selection:) needs a
    /// stable identity across re-fetched trees (a watcher-triggered reload
    /// tears down and rebuilds the whole array) so selection/expansion state
    /// survives, and two entries never share a path within one tree.
    var id: String { path }

    /// Every file in `entries`, as a flat list of relative paths. Files only:
    /// a directory holds nothing anyone can open, and its name is already
    /// implied by its children.
    static func flattenedPaths(_ entries: [FileTreeEntry]) -> [String] {
        entries.flatMap { entry in
            entry.children.map(flattenedPaths) ?? [entry.path]
        }
    }
}

struct FileContent: Equatable {
    let path: String
    let content: String
    let revision: String
    let readOnly: Bool
    let size: Int
    var language: String?
    var previewUrl: String?
    var mimeType: String?
}

struct SaveFileRequest: Equatable {
    let path: String
    let content: String
    let expectedRevision: String
}

struct SaveFileResult: Equatable {
    let path: String
    let revision: String
    let size: Int
}

enum WorkspaceFileServiceErrorCode: String, Equatable {
    case pathOutsideWorkspace
    case fileNotFound
    case fileConflict
    case fileTooLarge
    case binaryFile
    case encodingError
    case invalidPath
}

struct WorkspaceFileServiceError: Error, LocalizedError, Equatable {
    let code: WorkspaceFileServiceErrorCode
    let message: String

    var errorDescription: String? { message }
}
