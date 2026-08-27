//
//  EditorPaneStore.swift
//  Puck
//
//  Source of truth for one workspace's editor pane: file tree, open tabs,
//  which one is active. Owns the WorkspaceFileService (root validated at
//  construction, so a failed init means the project folder is genuinely
//  gone/inaccessible right now) and the WorkspaceFileWatcher that keeps the
//  tree and open tabs' diskChanged state live.
//

import Foundation

final class EditorPaneStore: ObservableObject {
    let workspaceId: String

    @Published private(set) var tree: [FileTreeEntry] = []
    /// Bumped every time the tree is re-read. Views that derive something
    /// from the project's files -- the explorer's git marks -- watch this
    /// rather than the tree itself, which is a deep array they would have to
    /// diff to notice.
    @Published private(set) var treeRevision = 0
    @Published private(set) var openTabs: [EditorTab] = []
    @Published var activeTabPath: String?
    /// The last thing that went wrong, for the pane to show. Cleared when
    /// the next operation starts, and by the view once it has been read --
    /// an error nothing displays is an operation that silently did nothing,
    /// which is what a failed rename looked like.
    @Published var lastError: WorkspaceFileServiceError?
    /// Set by `requestClose(path:)` when the tab still holds unsaved edits:
    /// the view turns it into a confirmation dialog. Nil means nothing is
    /// waiting on the user.
    @Published private(set) var pendingClosePath: String?

    /// A request for the editor view to select a line range and scroll it
    /// into view. `token` changes on every request, so the same range asked
    /// for twice still fires -- the user may have scrolled away since, and
    /// an equal value is a value the view ignores.
    struct RevealRequest: Equatable {
        let path: String
        let lines: ClosedRange<Int>
        let token: Int
    }

    /// The last range someone asked to be shown, for the editor view to
    /// apply. Consumed by whichever tab's editor matches `path`.
    @Published private(set) var pendingReveal: RevealRequest?

    /// A request to open the find bar over one file. Same token shape as
    /// `pendingReveal`, and for the same reason: asking twice has to fire
    /// twice, because the user may have closed it in between.
    struct FindRequest: Equatable {
        let path: String
        let token: Int
    }

    /// Consumed by whichever tab's editor matches `path`. The find bar itself
    /// belongs to the text view -- this only says when to show it.
    @Published private(set) var pendingFind: FindRequest?
    /// Bumped on every `open(path:)`, whether or not it changed the tab.
    @Published private(set) var openRequests = 0
    /// Where the editor pane is, in AppKit global (bottom-left) screen
    /// coordinates, or nil when it is not on screen. Published by the view,
    /// because only the view knows where it ended up -- the pet is sent here.
    @Published private(set) var paneScreenFrame: CGRect?

    private var revealToken = 0
    private var findToken = 0

    private let service: WorkspaceFileService

    /// The project this store is attached to. Exposed for the git view, which
    /// runs against the same directory the tree reads.
    var rootPath: String { service.root.path }

    /// Whether this store is watching `candidate`, symlinks and all -- the
    /// service resolves its root, so a path that points at the same directory
    /// by another name is the same root.
    func watches(_ candidate: URL) -> Bool {
        guard let resolved = try? WorkspaceFileService.realpath(candidate.standardizedFileURL) else {
            return candidate.standardizedFileURL.path == service.root.path
        }
        return resolved.path == service.root.path
    }
    private var watcher: WorkspaceFileWatcher?

    /// Called (on the main queue) if the project root itself is moved/
    /// deleted while this store is alive -- the owner is expected to react
    /// by re-deriving ClientWorkspace.editorAvailability rather than this
    /// type owning that decision itself. A `var`, not baked into the
    /// watcher at construction: EditorPaneStorePool.store(forWorkspace:...)
    /// can return an existing store created by an earlier caller (e.g. a
    /// tool call, which has no ClientWorkspace to refresh and passes a
    /// no-op), and a later caller that *does* care about root-loss (the
    /// real editor pane UI) needs its callback to actually take over rather
    /// than silently losing detection to whichever caller happened to
    /// create the store first.
    var onRootChanged: (() -> Void)?

    init(
        workspaceId: String,
        root: URL,
        editableSizeLimit: Int = WorkspaceFileServiceDefaults.editableSizeLimit,
        onRootChanged: @escaping () -> Void
    ) throws {
        self.workspaceId = workspaceId
        self.onRootChanged = onRootChanged
        service = try WorkspaceFileService(root: root, editableSizeLimit: editableSizeLimit)
        loadTree()
        let watcher = WorkspaceFileWatcher(
            root: service.root,
            onChange: { [weak self] changes in self?.handleFileSystemChanges(changes) },
            onRootChanged: { [weak self] in self?.onRootChanged?() }
        )
        self.watcher = watcher
        watcher.start()
    }

    deinit {
        watcher?.stop()
    }

    var activeTab: EditorTab? {
        guard let activeTabPath else { return nil }
        return openTabs.first { $0.path == activeTabPath }
    }

    func loadTree() {
        do {
            tree = try service.listTree()
            treeRevision += 1
        } catch {
            lastError = error as? WorkspaceFileServiceError
        }
    }

    /// Renames a file or directory, and follows it: a tab open on the old
    /// name is now open on a file that no longer exists, and a tree still
    /// showing it is a tree that lies.
    func rename(path: String, to newName: String) {
        // Whatever went wrong last time is not what is being reported now.
        lastError = nil
        do {
            let renamed = try service.rename(path, to: newName)
            if let index = openTabs.firstIndex(where: { $0.path == path }) {
                // Renaming a file you are not looking at must not move you to
                // it, nor to whatever happens to be last.
                let previouslyActive = activeTabPath == path ? renamed : activeTabPath
                openTabs.remove(at: index)
                loadTree()
                open(path: renamed)
                activeTabPath = previouslyActive
            } else {
                loadTree()
            }
        } catch let error as WorkspaceFileServiceError {
            lastError = error
        } catch {
            lastError = nil
        }
    }

    /// Moves a file or directory to the Trash and closes anything open from
    /// under it -- a tab on a trashed file has nowhere to save to.
    func trash(path: String) {
        // Whatever went wrong last time is not what is being reported now.
        lastError = nil
        do {
            try service.trash(path)
            for tab in openTabs where tab.path == path || tab.path.hasPrefix(path + "/") {
                close(path: tab.path)
            }
            loadTree()
        } catch let error as WorkspaceFileServiceError {
            lastError = error
        } catch {
            lastError = nil
        }
    }

    /// Creates an empty file or a directory. A new file is opened straight
    /// away, because the only reason to make one is to put something in it.
    func create(name: String, directory: Bool, in parent: String?) {
        // Whatever went wrong last time is not what is being reported now.
        lastError = nil
        do {
            let created = try service.create(name: name, directory: directory, in: parent)
            loadTree()
            if !directory { open(path: created) }
        } catch let error as WorkspaceFileServiceError {
            lastError = error
        } catch {
            lastError = nil
        }
    }

    /// The absolute path of something in the tree, for Finder and the
    /// pasteboard -- both of which deal in real paths, not the project
    /// relative ones the tree carries.
    func absolutePath(for path: String) -> String {
        path.hasPrefix("/") ? path : service.root.appendingPathComponent(path).path
    }

    func open(path: String) {
        // Counted even when nothing changes. Clicking a file that is already
        // the active tab is still a request to look at it, and a view that
        // put the code away has no other way to hear it -- keyed on
        // `activeTabPath` alone, that click did nothing at all.
        openRequests += 1
        if openTabs.contains(where: { $0.path == path }) {
            activeTabPath = path
            return
        }
        do {
            let content = Self.isImagePath(path) ? try service.readImagePreview(at: path) : try service.readFile(at: path)
            openTabs.append(EditorTab(content))
            activeTabPath = path
        } catch let error as WorkspaceFileServiceError {
            lastError = error
        } catch {
            lastError = nil
        }
    }

    /// Opens `path` if it is not open already, then asks the view to select
    /// and scroll to `lines`. What a code tour calls for each of its stops.
    func reveal(path: String, lines: ClosedRange<Int>) {
        open(path: path)
        // The tab being active is the direct evidence that the file opened;
        // lastError is not, because it may be left over from an earlier call.
        guard activeTabPath == path else { return }
        revealToken += 1
        pendingReveal = RevealRequest(path: path, lines: lines, token: revealToken)
    }

    func setPaneScreenFrame(_ frame: CGRect?) {
        guard frame != paneScreenFrame else { return }
        paneScreenFrame = frame
    }

    func select(path: String) {
        guard openTabs.contains(where: { $0.path == path }) else { return }
        activeTabPath = path
    }

    /// The tab after the active one, wrapping round at the end. What ⌘⇧] is
    /// for in every editor with tabs: moving between what is already open
    /// without reaching for the mouse or the file tree.
    func selectNextTab() {
        selectTab(offsetFromActive: 1)
    }

    func selectPreviousTab() {
        selectTab(offsetFromActive: -1)
    }

    private func selectTab(offsetFromActive offset: Int) {
        guard !openTabs.isEmpty else { return }
        // From the start when nothing is active, so the shortcut still does
        // something on a pane that has tabs but no selection.
        guard let current = activeTabPath.flatMap({ path in openTabs.firstIndex { $0.path == path } }) else {
            activeTabPath = openTabs.first?.path
            return
        }
        let count = openTabs.count
        // +count before the modulo: Swift's % keeps the sign of the left
        // operand, so -1 % count is -1 and would index off the front.
        activeTabPath = openTabs[(current + offset + count) % count].path
    }

    /// Opens the editor's own find bar over the file being looked at. ⌘F.
    func showFind() {
        guard let path = activeTabPath else { return }
        findToken += 1
        pendingFind = FindRequest(path: path, token: findToken)
    }

    /// Puts the caret on `line` of the file already open, the way ⌘L does.
    ///
    /// Out-of-range numbers are clamped rather than refused: someone typing a
    /// line number is aiming, and the end of the file is the honest answer to
    /// a number past it.
    func goToLine(_ line: Int) {
        guard let path = activeTabPath, let tab = openTabs.first(where: { $0.path == path }) else { return }
        let target = Self.clampedLine(line, in: tab.content)
        reveal(path: path, lines: target...target)
    }

    /// The line `line` names in `content`, kept inside it. 1-based, like
    /// every line number a person reads or types.
    static func clampedLine(_ line: Int, in content: String) -> Int {
        // A trailing newline ends the last line rather than starting another,
        // which is what `split` gets right and `components` does not.
        let lineCount = max(content.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
        let lastLine = content.hasSuffix("\n") ? max(lineCount - 1, 1) : lineCount
        return min(max(line, 1), lastLine)
    }

    func close(path: String) {
        // The neighbour, not the last tab. Closing one in the middle of a
        // strip jumped focus to the far end, which is nowhere near where the
        // eye is -- every editor moves to the tab that takes the closed one's
        // place, or to the one before it when there is none.
        let closing = openTabs.firstIndex { $0.path == path }
        openTabs.removeAll { $0.path == path }
        if activeTabPath == path {
            activeTabPath = closing.map { min($0, openTabs.count - 1) }
                .flatMap { $0 >= 0 ? openTabs[$0].path : nil }
        }
        if pendingClosePath == path { pendingClosePath = nil }
    }

    /// The close path the UI goes through. A clean tab closes straight away;
    /// a dirty one raises `pendingClosePath` instead, because dropping the
    /// tab here would throw away edits that exist nowhere else.
    func requestClose(path: String) {
        guard let tab = openTabs.first(where: { $0.path == path }), tab.isDirty else {
            close(path: path)
            return
        }
        pendingClosePath = path
    }

    /// Save-then-close. A save that fails (most likely the disk copy moved
    /// under the tab) leaves the tab open with its draft and its conflict
    /// banner rather than closing anyway -- the point of asking was not to
    /// lose the edit.
    func confirmPendingCloseSaving() {
        guard let path = pendingClosePath else { return }
        pendingClosePath = nil
        save(path: path)
        guard let tab = openTabs.first(where: { $0.path == path }), !tab.isDirty else { return }
        close(path: path)
    }

    /// Discard-then-close. Only reachable from an explicit "저장 안 함", so
    /// the loss is the user's own decision rather than a side effect of
    /// hitting the tab's ✕.
    func confirmPendingCloseDiscarding() {
        guard let path = pendingClosePath else { return }
        pendingClosePath = nil
        close(path: path)
    }

    func cancelPendingClose() {
        pendingClosePath = nil
    }

    func updateDraft(path: String, content: String) {
        guard let index = openTabs.firstIndex(where: { $0.path == path }), !openTabs[index].readOnly else { return }
        openTabs[index].content = content
    }

    func save(path: String) {
        guard let index = openTabs.firstIndex(where: { $0.path == path }), !openTabs[index].readOnly else { return }
        let tab = openTabs[index]
        do {
            let result = try service.save(SaveFileRequest(path: path, content: tab.content, expectedRevision: tab.revision))
            openTabs[index].savedContent = tab.content
            openTabs[index].revision = result.revision
            openTabs[index].diskChanged = false
        } catch let error as WorkspaceFileServiceError {
            if error.code == .fileConflict {
                openTabs[index].diskChanged = true
            }
            lastError = error
        } catch {
            lastError = nil
        }
    }

    /// True when ⌘S / the save button has something to do: an active tab
    /// that is editable and actually holds unsaved edits.
    var canSaveActiveTab: Bool {
        guard let tab = activeTab else { return false }
        return !tab.readOnly && tab.isDirty
    }

    /// What ⌘S and the tab strip's save button call. A no-op with no tab
    /// open, on a read-only tab, or when nothing has been typed -- saving an
    /// unchanged tab would rewrite the file for no reason and make the
    /// watcher re-read it.
    func saveActiveTab() {
        guard canSaveActiveTab, let path = activeTabPath else { return }
        save(path: path)
    }

    /// Conflict resolution: keep the in-editor draft, re-anchored to disk's
    /// current revision, then retry the save. No diff view -- this and
    /// useDisk are the only two resolutions offered.
    func keepMine(path: String) {
        guard let index = openTabs.firstIndex(where: { $0.path == path }) else { return }
        do {
            let fresh = try service.readFile(at: path)
            openTabs[index].revision = fresh.revision
            save(path: path)
        } catch let error as WorkspaceFileServiceError {
            lastError = error
        } catch {
            lastError = nil
        }
    }

    /// Conflict resolution: discard the draft, load whatever's on disk now.
    ///
    /// Through `adopt`, not by replacing the tab with a fresh one. A fresh
    /// tab starts its adoption count at zero, and the editor view is keyed on
    /// `path#adoptions` precisely so it rebuilds when the text changes under
    /// it -- so replacing a never-adopted tab (which is exactly the tab that
    /// can be in conflict: the watcher only auto-adopts clean ones) left the
    /// key identical, the view unrebuilt, and the user's draft still on
    /// screen. The next keystroke then pushed that draft back out through
    /// `updateDraft` and overwrote the disk contents they had just asked to
    /// keep.
    func useDisk(path: String) {
        guard let index = openTabs.firstIndex(where: { $0.path == path }) else { return }
        do {
            openTabs[index].adopt(try service.readFile(at: path))
        } catch let error as WorkspaceFileServiceError {
            lastError = error
        } catch {
            lastError = nil
        }
    }

    /// Internal rather than private so the adopt-vs-warn decision can be
    /// driven directly: FSEvents delivery is WorkspaceFileWatcherTests'
    /// subject, and going through a real OS event to reach this branch makes
    /// a logic test depend on scheduling it has no stake in.
    func handleFileSystemChanges(_ changes: [FileSystemChange]) {
        loadTree()
        for change in changes {
            guard let relativePath = relativePath(for: change.path),
                  let index = openTabs.firstIndex(where: { $0.path == relativePath }) else { continue }
            if change.kind == .unlink {
                openTabs[index].diskChanged = true
                continue
            }
            guard change.kind == .change else { continue }
            // Re-read and compare revisions rather than trusting the raw FS
            // event alone -- our own just-completed save fires this same
            // event, and would otherwise flag itself as an external conflict.
            guard let fresh = try? service.readFile(at: relativePath), fresh.revision != openTabs[index].revision else { continue }
            // A tab the user has not touched follows the file.
            // The conflict banner is the right answer for an edit the user
            // would lose and the wrong one for a file they are only watching
            // -- which is the whole of the code_editor case, where every
            // change is one the agent was asked to make. Dirty tabs still
            // get the banner: nothing silently overwrites typing.
            if openTabs[index].isDirty {
                openTabs[index].diskChanged = true
            } else {
                let before = openTabs[index].content
                openTabs[index].adopt(fresh)
                follow(change: before, to: fresh.content, at: relativePath)
            }
        }
    }

    /// Scrolls to what the agent just wrote.
    ///
    /// The content already updated -- a clean tab follows the file on its own
    /// -- but a write below the fold is invisible, and watching an edit land
    /// is most of the reason to have the file open beside the conversation.
    ///
    /// Only the tab on screen. Revealing a background one would scroll it
    /// where nobody is looking and throw away the reveal the visible tab may
    /// be waiting for.
    private func follow(change before: String, to after: String, at path: String) {
        guard path == activeTabPath, let lines = Self.changedLines(from: before, to: after) else { return }
        revealToken += 1
        pendingReveal = RevealRequest(path: path, lines: lines, token: revealToken)
    }

    /// The lines that differ between two revisions of a file, 1-based and
    /// inclusive, or nil when nothing did.
    ///
    /// Matching prefix and suffix are trimmed and what is left is the answer.
    /// Not a real diff: this only has to say *where* to look, and an edit in
    /// the middle of a file is exactly what that finds. A rewrite of
    /// everything reports the whole file, which is also the truth.
    static func changedLines(from old: String, to new: String) -> ClosedRange<Int>? {
        guard old != new else { return nil }
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        var prefix = 0
        while prefix < oldLines.count, prefix < newLines.count, oldLines[prefix] == newLines[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldLines.count - prefix,
              suffix < newLines.count - prefix,
              oldLines[oldLines.count - 1 - suffix] == newLines[newLines.count - 1 - suffix] {
            suffix += 1
        }

        // Lines the new revision gained or changed, 1-based.
        let first = prefix + 1
        let last = newLines.count - suffix
        // A pure deletion leaves nothing new to point at, so point at the
        // seam it left behind, clamped into the file that remains.
        guard last >= first else {
            let seam = min(max(first, 1), max(newLines.count, 1))
            return seam...seam
        }
        return first...last
    }

    /// The root with its symlinks resolved, computed once. FSEvents reports
    /// canonical paths, and the root is stored the way it was chosen.
    private lazy var canonicalRoot = URL(fileURLWithPath: service.root.path).resolvingSymlinksInPath().path

    private func relativePath(for absolutePath: String) -> String? {
        if let direct = PathContainment.relativePath(root: service.root.path, candidate: absolutePath) {
            return direct
        }
        // A project reached through a symlink -- /tmp, or a home directory
        // behind one -- is stored as the user chose it while its events
        // arrive canonical: `/tmp/x` against `/private/tmp/x`. Compared as
        // plain strings no open tab ever matched, so the file on screen never
        // followed what was written to it. The tree hid this: it reloads on
        // any event at all, so it looked like the watcher was working.
        let canonical = URL(fileURLWithPath: absolutePath).resolvingSymlinksInPath().path
        return PathContainment.relativePath(root: canonicalRoot, candidate: canonical)
    }

    private static func isImagePath(_ path: String) -> Bool {
        ImageMime.extensionMap["." + (path as NSString).pathExtension.lowercased()] != nil
    }
}
