//
//  WorkspaceFileWatcher.swift
//  Puck
//
//  FSEvents-based recursive directory watcher -- the native analogue of
//  file-service.ts's chokidar-based startWatching(). FSEvents (not
//  DispatchSource.makeFileSystemObjectSource, which watches one already-open
//  fd and doesn't recurse or notice new paths) is the OS-native primitive
//  built for exactly this -- the same one Finder/Spotlight/git-status use.
//

import CoreServices
import Foundation

enum FileSystemChangeKind: Equatable {
    case add, change, unlink, addDir, unlinkDir
}

struct FileSystemChange: Equatable {
    let kind: FileSystemChangeKind
    /// Absolute path.
    let path: String
}

final class WorkspaceFileWatcher {
    /// Pure classification of a raw FSEvents flag mask -- kept separate from
    /// the real FSEventStreamCreate plumbing so it's unit-testable without
    /// standing up a real stream.
    enum FlagClassification: Equatable {
        case change(FileSystemChangeKind)
        case rootChanged
        case ignore
    }

    private let root: URL
    private let onChange: ([FileSystemChange]) -> Void
    private let onRootChanged: () -> Void
    private var stream: FSEventStreamRef?

    init(root: URL, onChange: @escaping ([FileSystemChange]) -> Void, onRootChanged: @escaping () -> Void) {
        self.root = root
        self.onChange = onChange
        self.onRootChanged = onRootChanged
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, eventFlags, _ in
            guard let clientCallBackInfo else { return }
            let watcher = Unmanaged<WorkspaceFileWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] ?? []
            let flagsBuffer = UnsafeBufferPointer(start: eventFlags, count: numEvents)
            watcher.handle(paths: paths, flags: Array(flagsBuffer))
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,
            flags
        ) else { return }
        stream = created
        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        FSEventStreamStart(created)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handle(paths: [String], flags: [FSEventStreamEventFlags]) {
        if flags.contains(where: { Self.classify(flags: $0) == .rootChanged }) {
            onRootChanged()
        }
        let changes: [FileSystemChange] = zip(paths, flags).compactMap { path, flag in
            guard !Self.isInsideIgnoredDirectory(path, root: root.path) else { return nil }
            guard case let .change(kind) = Self.classify(flags: flag) else { return nil }
            return FileSystemChange(kind: kind, path: path)
        }
        guard !changes.isEmpty else { return }
        onChange(changes)
    }

    // MARK: - Pure classification (unit-testable without a real FSEvents stream)

    static func classify(flags: FSEventStreamEventFlags) -> FlagClassification {
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
            return .rootChanged
        }
        guard let kind = changeKind(for: flags) else { return .ignore }
        return .change(kind)
    }

    private static func changeKind(for flags: FSEventStreamEventFlags) -> FileSystemChangeKind? {
        let isDirectory = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0
        let isRemoved = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0
        let isCreated = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0
        let isModified = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified) != 0
        let isRenamed = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0

        if isRemoved {
            return isDirectory ? .unlinkDir : .unlink
        }
        if isCreated {
            return isDirectory ? .addDir : .add
        }
        if isModified || isRenamed {
            // A rename fires once per side of the move with no reliable
            // order information here to tell "moved away" from "moved to"
            // apart -- both collapse to a plain change/addDir signal, which
            // is enough for EditorPaneStore's actual use (any event just
            // triggers a tree refresh + open-tab revision recheck, it
            // doesn't try to incrementally patch the tree from the kind alone).
            return isDirectory ? .addDir : .change
        }
        return nil
    }

    /// Whether an event path lies inside a directory nobody wants to hear
    /// about.
    ///
    /// Both sides are put through `realpath` first. FSEvents reports the
    /// filesystem's own spelling -- `/private/tmp/...` -- while the root this
    /// watcher was given has been standardized back to `/tmp/...`, so the two
    /// never lined up: `relativePath` answered nil, the guard passed, and
    /// every write under `node_modules` or `.git` was delivered as a change.
    /// Each one costs a full tree reload and a `git status`.
    ///
    /// `realpath`, not `resolvingSymlinksInPath`: the latter standardizes
    /// `/private/tmp` *to* `/tmp`, which is the direction that hid this.
    static func isInsideIgnoredDirectory(_ path: String, root: String) -> Bool {
        guard let relative = PathContainment.relativePath(
            root: canonicalPath(root),
            candidate: canonicalPath(path)
        ) else {
            return false
        }
        return relative.split(separator: "/").contains { workspaceFileServiceDefaultIgnores.contains(String($0)) }
    }

    /// The kernel's spelling of a path, or the path itself when it does not
    /// exist -- a file the event says was deleted has no realpath any more,
    /// and its directory prefix is what matters here.
    private static func canonicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else {
            // Fall back to resolving as much of the parent as exists, so a
            // deleted node_modules/x is still recognised by its directory.
            let parent = (path as NSString).deletingLastPathComponent
            guard !parent.isEmpty, let resolvedParent = realpath(parent, nil) else { return path }
            defer { free(resolvedParent) }
            return String(cString: resolvedParent) + "/" + (path as NSString).lastPathComponent
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
