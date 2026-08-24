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
    /// `.git` above all: a single commit rewrites hundreds of paths under it
    /// and none of them are the agent's edit. The rest are the same shape --
    /// directories a build tool owns, where a change is a by-product of the
    /// work rather than the work.
    ///
    /// This list is what keeps the walk cheap now that hidden files are *not*
    /// skipped wholesale. They used to be, which meant an agent asked to fix
    /// a CI workflow, a .env or a .gitignore reported changing nothing at
    /// all: the snapshot could not see the file, so the watcher was the only
    /// witness, and a coalesced burst there is unrecoverable.
    static let ignoredDirectories: Set<String> = [
        ".git", "node_modules", ".build", ".swiftpm", "DerivedData",
        ".next", ".venv", "__pycache__",
    ]

    /// Finder writes this into whichever folder someone looked at, which has
    /// nothing to do with the agent.
    static let ignoredFileNames: Set<String> = [".DS_Store"]

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
        let components = relative.split(separator: "/").map(String.init)
        // Any level, not only the first: a `.git` or a `node_modules` nested
        // inside a package is the same noise as one at the root.
        if components.dropLast().contains(where: ignoredDirectories.contains) { return nil }
        if let first = components.first, ignoredDirectories.contains(first) { return nil }
        if let name = components.last, ignoredFileNames.contains(name) { return nil }
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
            // Hidden files included: `.github/workflows`, `.env`, `.gitignore`
            // and `.vscode` are edited as often as anything else, and skipping
            // them meant the snapshot half of this tracker never saw them.
            // `ignoredDirectories` is what keeps the walk cheap instead.
            options: []
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
