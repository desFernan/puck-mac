//
//  ProjectChangeTracker.swift
//  Puck
//
//  Which files a code_editor run touched. Port of acp-adapter.ts's pairing of
//  a chokidar watcher with a before/after directory snapshot.
//
//  Both halves are kept because each covers the other's blind spot: the
//  watcher sees a file that was written and then deleted again (a snapshot
//  diff would show nothing), and the snapshot catches whatever the watcher
//  dropped while coalescing a burst. The union is what the agent reports.
//
//  The watcher itself is WorkspaceFileWatcher, already in the tree for the
//  native editor pane -- there was no reason to write a second one.
//

import Foundation

final class ProjectChangeTracker {
    /// Same exclusions the TS version used. `.git` above all: a single commit
    /// rewrites hundreds of paths under it and none of them are the agent's edit.
    static let ignoredDirectories: Set<String> = [".git", "node_modules"]

    private let root: URL
    private let lock = NSLock()
    private var changed: Set<String> = []
    private var before: [String: String] = [:]
    private var watcher: WorkspaceFileWatcher?

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// Takes the "before" snapshot and starts watching. Failing to start the
    /// watcher is not fatal -- the snapshot diff alone still produces a usable
    /// list, which is better than failing the edit over its bookkeeping.
    func start() {
        lock.lock()
        before = Self.snapshot(of: root)
        lock.unlock()

        watcher = WorkspaceFileWatcher(
            root: root,
            onChange: { [weak self] changes in
                guard let self else { return }
                self.lock.lock()
                for change in changes {
                    if let relative = self.relativePath(for: change.path) { self.changed.insert(relative) }
                }
                self.lock.unlock()
            },
            onRootChanged: {}
        )
        watcher?.start()
    }

    /// Stops watching and returns the union of what was observed and what the
    /// snapshot diff shows, sorted for a stable tool result.
    func finish() -> [String] {
        watcher?.stop()
        watcher = nil

        let after = Self.snapshot(of: root)
        lock.lock()
        defer { lock.unlock() }
        for (path, fingerprint) in after where before[path] != fingerprint {
            changed.insert(path)
        }
        for path in before.keys where after[path] == nil {
            changed.insert(path)
        }
        return changed.sorted()
    }

    // MARK: - Internals

    /// Path relative to the root, or nil when it escapes it. Containment is
    /// re-checked here rather than trusted: FSEvents reports the path it was
    /// given, and a symlinked subdirectory can name a file outside the project.
    private func relativePath(for absolutePath: String) -> String? {
        Self.relativePath(for: absolutePath, under: root.path)
    }

    static func relativePath(for absolutePath: String, under rootPath: String) -> String? {
        guard let relative = PathContainment.relativePath(root: rootPath, candidate: absolutePath) else { return nil }
        // The root itself is inside itself but is not a changed *file*.
        guard !relative.isEmpty else { return nil }
        let first = relative.split(separator: "/").first.map(String.init)
        if let first, ignoredDirectories.contains(first) { return nil }
        return relative
    }

    /// Relative path -> "size:mtime". Cheap enough to run twice per edit on a
    /// project of ordinary size, and it does not read file contents.
    static func snapshot(of root: URL) -> [String: String] {
        var result: [String: String] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return result }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if ignoredDirectories.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            guard let relative = relativePath(for: url.standardizedFileURL.path, under: root.standardizedFileURL.path)
            else { continue }
            let size = values?.fileSize ?? 0
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            result[relative] = "\(size):\(modified)"
        }
        return result
    }
}
