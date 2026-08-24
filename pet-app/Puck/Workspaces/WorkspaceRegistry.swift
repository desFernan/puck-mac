//
//  WorkspaceRegistry.swift
//  Puck
//
//  1:1 port of workspace/src/main/workspace-registry.ts. Workspace metadata
//  (name + which project directory it points at) used to live in the Electron
//  app, which meant "새 워크스페이스" had to round-trip over the bridge and
//  the native editor pane could only ever open for a workspace some *other*
//  process had created. Owning it here is what lets workspace go away.
//
//  The on-disk shape is kept identical to the TS version (`{version: 1,
//  workspaces: [...]}`, millisecond timestamps) -- there is no migration to
//  write, and a shape that already had a reader is a shape worth keeping.
//
//  Main-thread only, like the rest of the bridge-adjacent state: every caller
//  reaches it from BridgeMessageRouter, which hops to main first.
//

import Foundation

struct WorkspaceRecord: Codable, Equatable {
    let id: String
    var name: String
    /// Absolute, symlink-resolved. `nil` for a workspace that is chat-only --
    /// `EditorAvailability.resolve` turns that into `.noProject`.
    var projectPath: String?
    /// Kept as a separate field for wire compatibility with the TS store.
    /// Both are resolved now, so they agree; the pair survives because an
    /// existing store may hold an unresolved `projectPath` from before.
    var realProjectPath: String?
    let createdAt: Int64
    var updatedAt: Int64
}

enum WorkspaceRegistryError: Error, Equatable {
    case notFound
    case alreadyExists
    /// The path is missing, is not a directory, or cannot be read. Mirrors
    /// the TS version's `realpath()` throwing on a bad path, but names the
    /// three cases as one condition since every caller treats them alike.
    case projectPathUnusable
}

final class WorkspaceRegistry {
    static let defaultWorkspaceID = "default"

    private let storageURL: URL
    /// Insertion-ordered: `list()` has to be stable so PuckClient's sidebar
    /// doesn't reshuffle on every save. A dictionary alone cannot promise that.
    private var order: [String] = []
    private var records: [String: WorkspaceRecord] = [:]

    /// - Parameter storageURL: defaults to Application Support, the same
    ///   directory `bridge.sock` and the avatar package already live in.
    init(storageURL: URL? = nil) throws {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        load()
        ensureDefault()
        // Only write when loading produced nothing to write back -- a fresh
        // install should end up with a real file, but an existing one must not
        // be rewritten just because it was read.
        if records.count == 1 && records[Self.defaultWorkspaceID] != nil
            && !FileManager.default.fileExists(atPath: self.storageURL.path) {
            try? persist()
        }
    }

    static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Puck/workspaces.json")
    }

    // MARK: - Reading

    func list() -> [WorkspaceRecord] {
        order.compactMap { records[$0] }
    }

    func get(id: String) -> WorkspaceRecord? {
        records[id]
    }

    // MARK: - Writing

    @discardableResult
    func create(name: String, projectPath: String?, id: String = UUID().uuidString) throws -> WorkspaceRecord {
        guard records[id] == nil else { throw WorkspaceRegistryError.alreadyExists }
        let resolved = try projectPath.map(Self.resolveProjectDirectory)
        let now = Self.nowMilliseconds()
        let record = WorkspaceRecord(
            id: id,
            name: Self.displayName(from: name),
            projectPath: resolved,
            realProjectPath: resolved,
            createdAt: now,
            updatedAt: now
        )
        records[id] = record
        order.append(id)
        try persist()
        return record
    }

    @discardableResult
    func bindProject(id: String, projectPath: String) throws -> WorkspaceRecord {
        guard var record = records[id] else { throw WorkspaceRegistryError.notFound }
        let resolved = try Self.resolveProjectDirectory(projectPath)
        record.projectPath = resolved
        record.realProjectPath = resolved
        record.updatedAt = Self.nowMilliseconds()
        records[id] = record
        try persist()
        return record
    }

    /// - Returns: false for the default workspace, which is not removable --
    ///   it is the one every session can always fall back to.
    @discardableResult
    func remove(id: String) throws -> Bool {
        guard id != Self.defaultWorkspaceID, records.removeValue(forKey: id) != nil else { return false }
        order.removeAll { $0 == id }
        try persist()
        return true
    }

    // MARK: - Persistence

    private struct PersistedRegistry: Codable {
        let version: Int
        let workspaces: [WorkspaceRecord]
    }

    private static let storeVersion = 1

    /// Set when a store was there and could not be read. The next write
    /// moves it aside first -- starting empty is survivable, but writing a
    /// fresh store over one we simply failed to parse destroys the only copy
    /// of every workspace the user had, including one written by a newer
    /// build they might go back to.
    private var unreadableStoreNeedsBackup = false

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let parsed = try? JSONDecoder().decode(PersistedRegistry.self, from: data),
              parsed.version == Self.storeVersion
        else {
            // Unreadable, malformed, or written by a newer build. Starting
            // empty loses workspace *metadata*, never a project's files, so
            // refusing to launch over it would trade a small loss for a total one.
            unreadableStoreNeedsBackup = true
            return
        }
        for record in parsed.workspaces where records[record.id] == nil {
            records[record.id] = record
            order.append(record.id)
        }
    }

    private func persist() throws {
        backUpUnreadableStoreIfNeeded()
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(PersistedRegistry(version: Self.storeVersion, workspaces: list()))
        // .atomic is the temp-file-then-rename the TS version spelled out by
        // hand; a half-written store would strand every workspace at once.
        try data.write(to: storageURL, options: .atomic)
    }

    /// Keeps a store we could not parse, once, beside the new one.
    ///
    /// Best effort on purpose: if the copy fails there is nothing useful to
    /// do about it, and refusing to save would mean losing the workspaces the
    /// user is creating right now on top of the ones already lost.
    private func backUpUnreadableStoreIfNeeded() {
        guard unreadableStoreNeedsBackup else { return }
        unreadableStoreNeedsBackup = false
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = storageURL.appendingPathExtension("unreadable-\(stamp)")
        try? FileManager.default.moveItem(at: storageURL, to: backup)
    }

    // MARK: - Helpers

    private func ensureDefault() {
        guard records[Self.defaultWorkspaceID] == nil else { return }
        let now = Self.nowMilliseconds()
        records[Self.defaultWorkspaceID] = WorkspaceRecord(
            id: Self.defaultWorkspaceID,
            name: ClientWorkspace.defaultName,
            projectPath: nil,
            realProjectPath: nil,
            createdAt: now,
            updatedAt: now
        )
        order.insert(Self.defaultWorkspaceID, at: 0)
    }

    private static func displayName(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Workspace" : trimmed
    }

    /// Validated here rather than at the editor: a workspace that records an
    /// unusable path looks identical to a chat-only one everywhere downstream.
    private static func resolveProjectDirectory(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: url.path)
        else {
            throw WorkspaceRegistryError.projectPathUnusable
        }
        return url.path
    }

    private static func nowMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
