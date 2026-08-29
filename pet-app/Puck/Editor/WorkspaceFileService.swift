//
//  WorkspaceFileService.swift
//  Puck
//
//  Swift port of workspace/src/main/file-service.ts -- the file I/O logic
//  the native editor pane needs, with no dependency on workspace (the
//  Electron app) being launched. Deliberately synchronous/throwing: these
//  are local-disk syscalls, not network calls, and callers (EditorPaneStore)
//  offload off the main thread when needed rather than this type adopting
//  async/await for its own sake.
//

import CryptoKit
import Foundation

enum WorkspaceFileServiceDefaults {
    static let editableSizeLimit = 2 * 1024 * 1024
    static let imagePreviewSizeLimit = 10 * 1024 * 1024
}

/// Skipped at every directory level, both in tree listing and (once wired,
/// see WorkspaceFileWatcher) file watching. Not `.gitignore`-aware, matching
/// file-service.ts's own deliberate choice.
let workspaceFileServiceDefaultIgnores: Set<String> = [
    ".git", "node_modules", "dist", "dist-main", "release", ".next", "build",
    "target", ".venv", "venv", "__pycache__", ".pytest_cache", ".cache",
    "coverage", ".turbo", "Pods", ".build", "DerivedData",
]

final class WorkspaceFileService {
    let root: URL
    let editableSizeLimit: Int

    init(root: URL, editableSizeLimit: Int = WorkspaceFileServiceDefaults.editableSizeLimit) throws {
        self.root = try Self.realpath(root.standardizedFileURL)
        self.editableSizeLimit = editableSizeLimit
    }

    func listTree() throws -> [FileTreeEntry] {
        try readDirectory(root)
    }

    func readFile(at requestPath: String) throws -> FileContent {
        let target = try resolveExisting(requestPath)
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw WorkspaceFileServiceError(code: .invalidPath, message: Strings.text(.fileNotAFilePath))
        }
        let data = try Data(contentsOf: target)
        guard !Self.isBinary(data) else {
            throw WorkspaceFileServiceError(code: .binaryFile, message: Strings.text(.fileBinaryNotEditable))
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw WorkspaceFileServiceError(code: .encodingError, message: Strings.text(.fileOnlyUTF8))
        }
        let size = (attributes[.size] as? Int) ?? data.count
        return FileContent(
            path: relativeForWire(target),
            content: content,
            revision: Self.revision(of: data),
            readOnly: size > editableSizeLimit,
            size: size,
            language: EditorLanguage.displayName(forPath: target.path)
        )
    }

    func readImagePreview(at requestPath: String) throws -> FileContent {
        let target = try resolveExisting(requestPath)
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw WorkspaceFileServiceError(code: .invalidPath, message: Strings.text(.fileNotAFilePath))
        }
        let size = (attributes[.size] as? Int) ?? 0
        guard size <= WorkspaceFileServiceDefaults.imagePreviewSizeLimit else {
            throw WorkspaceFileServiceError(code: .fileTooLarge, message: Strings.text(.fileImageTooLargeToPreview))
        }
        let data = try Data(contentsOf: target)
        let extensionName = "." + target.pathExtension.lowercased()
        guard let detected = ImageMime.detect(data),
              let expected = ImageMime.extensionMap[extensionName],
              detected == expected else {
            throw WorkspaceFileServiceError(code: .binaryFile, message: Strings.text(.fileImageFormatMismatch))
        }
        return FileContent(
            path: relativeForWire(target),
            content: "",
            revision: Self.revision(of: data),
            readOnly: true,
            size: size,
            language: "image",
            previewUrl: "data:\(detected);base64,\(data.base64EncodedString())",
            mimeType: detected
        )
    }

    func save(_ request: SaveFileRequest) throws -> SaveFileResult {
        let target = try resolveExisting(request.path)
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw WorkspaceFileServiceError(code: .invalidPath, message: Strings.text(.fileNotAFilePath))
        }
        let size = (attributes[.size] as? Int) ?? 0
        guard size <= editableSizeLimit else {
            throw WorkspaceFileServiceError(code: .fileTooLarge, message: Strings.text(.fileTooLargeReadOnly))
        }
        let current = try Data(contentsOf: target)
        guard !Self.isBinary(current) else {
            throw WorkspaceFileServiceError(code: .binaryFile, message: Strings.text(.fileBinaryNotSavable))
        }
        guard Self.revision(of: current) == request.expectedRevision else {
            throw WorkspaceFileServiceError(code: .fileConflict, message: Strings.text(.fileChangedOnDisk))
        }
        guard let next = request.content.data(using: .utf8) else {
            throw WorkspaceFileServiceError(code: .encodingError, message: Strings.text(.fileOnlyUTF8))
        }
        guard next.count <= editableSizeLimit else {
            throw WorkspaceFileServiceError(code: .fileTooLarge, message: Strings.text(.fileSaveExceedsLimit))
        }

        let temporary = target.deletingLastPathComponent().appendingPathComponent(
            ".\(target.lastPathComponent).\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString).tmp"
        )
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try next.write(to: temporary, options: .atomic)
            if let posixPermissions = attributes[.posixPermissions] {
                try? FileManager.default.setAttributes([.posixPermissions: posixPermissions], ofItemAtPath: temporary.path)
            }
            // replaceItemAt is the Foundation equivalent of file-service.ts's
            // temp-file-then-rename: atomic within the volume, preserves the
            // rest of the target's metadata. A concurrent writer (e.g. the
            // AI's code_editor tool, via a separate ACP subprocess) holding
            // the target open can make this throw -- normalized to
            // .fileConflict below, same intent as the TS EPERM/EBUSY branch,
            // though less selective about which underlying errors qualify.
            _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
        } catch {
            throw WorkspaceFileServiceError(code: .fileConflict, message: Strings.text(.fileInUseByAnotherProcess))
        }
        return SaveFileResult(path: relativeForWire(target), revision: Self.revision(of: next), size: next.count)
    }

    // MARK: - Changing the tree

    /// Renames a file or directory in place. The new name is a name, not a
    /// path: "rename" in a file tree means the last component, and accepting
    /// a path here would turn a typo with a slash in it into a move.
    @discardableResult
    func rename(_ requestPath: String, to newName: String) throws -> String {
        let target = try resolveExisting(requestPath)
        try Self.validate(name: newName)
        let destination = target.deletingLastPathComponent().appendingPathComponent(newName)
        guard isInside(destination.path) else {
            throw WorkspaceFileServiceError(code: .pathOutsideWorkspace, message: Strings.text(.fileOutsideProject))
        }
        // Case-only renames are a real rename on a case-insensitive volume
        // and would otherwise trip the "already exists" check against the
        // file being renamed.
        guard destination.path.caseInsensitiveCompare(target.path) == .orderedSame
            || !FileManager.default.fileExists(atPath: destination.path)
        else {
            throw WorkspaceFileServiceError(code: .invalidPath, message: Strings.text(.fileNameTaken))
        }
        try FileManager.default.moveItem(at: target, to: destination)
        return relativeForWire(destination)
    }

    /// Moves a file or directory to the Trash rather than unlinking it.
    ///
    /// The tree is the user's project, not scratch space: a delete here has
    /// to be undoable by the same means every other delete on the machine is,
    /// which is the Trash. `trashItem` also refuses on volumes that have
    /// none, which is the honest answer in that case.
    func trash(_ requestPath: String) throws {
        let target = try resolveExisting(requestPath)
        guard target.path != root.path else {
            throw WorkspaceFileServiceError(code: .invalidPath, message: Strings.text(.fileCannotDeleteRoot))
        }
        try FileManager.default.trashItem(at: target, resultingItemURL: nil)
    }

    /// Creates an empty file, or a directory, inside `parent` -- the project
    /// root when that is nil.
    @discardableResult
    func create(name: String, directory: Bool, in parent: String?) throws -> String {
        try Self.validate(name: name)
        let base = try parent.map { try resolveExisting($0) } ?? root
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: base.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkspaceFileServiceError(code: .invalidPath, message: Strings.text(.fileNotADirectoryPath))
        }
        let destination = base.appendingPathComponent(name)
        guard isInside(destination.path) else {
            throw WorkspaceFileServiceError(code: .pathOutsideWorkspace, message: Strings.text(.fileOutsideProject))
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw WorkspaceFileServiceError(code: .invalidPath, message: Strings.text(.fileNameTaken))
        }
        if directory {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        } else {
            guard FileManager.default.createFile(atPath: destination.path, contents: Data()) else {
                throw WorkspaceFileServiceError(code: .invalidPath, message: Strings.text(.fileCouldNotCreate))
            }
        }
        return relativeForWire(destination)
    }

    /// What a single path component may be. Everything here is about the name
    /// being a name: a separator would make it a path, and the two dot names
    /// are directories that already exist.
    static func validate(name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\0"),
              trimmed != ".",
              trimmed != ".."
        else {
            throw WorkspaceFileServiceError(code: .invalidPath, message: Strings.text(.fileInvalidName))
        }
    }

    // MARK: - Tree listing

    private struct DirEntry {
        let name: String
        let url: URL
        let isSymbolicLink: Bool
        let isDirectory: Bool
        let isRegularFile: Bool
    }

    private func readDirectory(_ directory: URL) throws -> [FileTreeEntry] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { !workspaceFileServiceDefaultIgnores.contains($0) }
        let entries: [DirEntry] = names.compactMap { name in
            let url = directory.appendingPathComponent(name)
            guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]) else {
                return nil
            }
            let isSymlink = values.isSymbolicLink ?? false
            // Sort/dirent parity: a symlink is never treated as a directory
            // for ordering or branching purposes here, matching Node's
            // Dirent.isDirectory() (d_type-based, not target-resolved) that
            // file-service.ts sorts and branches on.
            return DirEntry(
                name: name,
                url: url,
                isSymbolicLink: isSymlink,
                isDirectory: !isSymlink && (values.isDirectory ?? false),
                isRegularFile: !isSymlink && (values.isRegularFile ?? false)
            )
        }
        let sorted = entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        var result: [FileTreeEntry] = []
        for entry in sorted {
            if entry.isSymbolicLink {
                guard let resolved = try? Self.realpath(entry.url), isInside(resolved.path) else { continue }
                result.append(FileTreeEntry(name: entry.name, path: relativeForWire(entry.url), kind: .symlink))
            } else if entry.isDirectory {
                result.append(FileTreeEntry(
                    name: entry.name,
                    path: relativeForWire(entry.url),
                    kind: .directory,
                    children: try readDirectory(entry.url)
                ))
            } else if entry.isRegularFile {
                result.append(FileTreeEntry(name: entry.name, path: relativeForWire(entry.url), kind: .file))
            }
        }
        return result
    }

    // MARK: - Path resolution

    private func resolveExisting(_ requestPath: String) throws -> URL {
        guard !requestPath.isEmpty, !requestPath.contains("\0") else {
            throw WorkspaceFileServiceError(code: .invalidPath, message: Strings.text(.fileInvalidPath))
        }
        let candidate = requestPath.hasPrefix("/")
            ? URL(fileURLWithPath: requestPath).standardizedFileURL
            : root.appendingPathComponent(requestPath).standardizedFileURL
        guard isInside(candidate.path) else {
            throw WorkspaceFileServiceError(code: .pathOutsideWorkspace, message: Strings.text(.fileOutsideProject))
        }
        let resolved = try Self.realpath(candidate)
        guard isInside(resolved.path) else {
            throw WorkspaceFileServiceError(code: .pathOutsideWorkspace, message: Strings.text(.fileSymlinkEscapesProject))
        }
        return resolved
    }

    private func isInside(_ candidate: String) -> Bool {
        PathContainment.isInside(root: root.path, candidate: candidate)
    }

    private func relativeForWire(_ target: URL) -> String {
        PathContainment.relativePath(root: root.path, candidate: target.path) ?? target.path
    }

    // MARK: - Primitives

    /// realpath(3) directly, not URL.resolvingSymlinksInPath() -- the latter
    /// doesn't cleanly surface ENOENT for a nonexistent path, whereas this is
    /// the same primitive Node's fs.realpath (which file-service.ts uses)
    /// wraps. Also runs the result through .standardizedFileURL, which on
    /// Apple platforms silently collapses a leading "/private" (e.g.
    /// /private/var -> /var, since these ARE symlinks and Foundation
    /// special-cases them back out) -- realpath(3) expands that same
    /// symlink the other way, so without this the stored root and a freshly
    /// standardized candidate path would use different, incompatible string
    /// forms of the identical file and every containment check would fail.
    static func realpath(_ url: URL) throws -> URL {
        var buffer = [Int8](repeating: 0, count: Int(PATH_MAX))
        guard let resolvedC = Darwin.realpath(url.path, &buffer) else {
            if errno == ENOENT {
                throw WorkspaceFileServiceError(code: .fileNotFound, message: Strings.text(.fileNotFound))
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return URL(fileURLWithPath: String(cString: resolvedC)).standardizedFileURL
    }

    private static func isBinary(_ data: Data) -> Bool {
        data.prefix(min(data.count, 8192)).contains(0)
    }

    private static func revision(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
