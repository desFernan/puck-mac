//
//  EditorFollowsWritesTests.swift
//  Puck
//
//  An open file follows what the agent writes to it, and the view is told
//  where to look. Driven through handleFileSystemChanges rather than a real
//  FSEvents delivery, which is what that method is internal for.
//

import XCTest
@testable import Puck

final class EditorFollowsWritesTests: XCTestCase {
    private var directories: [URL] = []

    override func tearDown() {
        for url in directories { try? FileManager.default.removeItem(at: url) }
        directories = []
        super.tearDown()
    }

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("puck-follow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        directories.append(root)
        try "one\ntwo\nthree\n".write(to: root.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        return root
    }

    private func makeStore(root: URL) throws -> EditorPaneStore {
        try EditorPaneStore(workspaceId: UUID().uuidString, root: root, onRootChanged: {})
    }

    func test_aCleanTabTakesOnWhatWasWrittenToIt() throws {
        let root = try makeProject()
        let store = try makeStore(root: root)
        store.open(path: "a.swift")
        XCTAssertEqual(store.activeTab?.content, "one\ntwo\nthree\n")

        let file = root.appendingPathComponent("a.swift")
        try "one\ntwo\nthree\nfour\n".write(to: file, atomically: true, encoding: .utf8)
        store.handleFileSystemChanges([FileSystemChange(kind: .change, path: file.path)])

        XCTAssertEqual(store.activeTab?.content, "one\ntwo\nthree\nfour\n")
        XCTAssertFalse(store.activeTab?.diskChanged ?? true, "a clean tab follows rather than warning")
    }

    /// Watching the edit land is most of the reason to keep the file open
    /// beside the conversation, and a write below the fold is invisible.
    func test_theViewIsToldWhereTheWriteLanded() throws {
        let root = try makeProject()
        let store = try makeStore(root: root)
        store.open(path: "a.swift")

        let file = root.appendingPathComponent("a.swift")
        try "one\nTWO\nthree\n".write(to: file, atomically: true, encoding: .utf8)
        store.handleFileSystemChanges([FileSystemChange(kind: .change, path: file.path)])

        XCTAssertEqual(store.pendingReveal?.path, "a.swift")
        XCTAssertEqual(store.pendingReveal?.lines, 2...2)
    }

    /// Nothing silently overwrites typing: a tab with unsaved edits gets the
    /// banner instead, and is not scrolled somewhere the user did not ask for.
    func test_aDirtyTabWarnsInsteadOfFollowing() throws {
        let root = try makeProject()
        let store = try makeStore(root: root)
        store.open(path: "a.swift")
        store.updateDraft(path: "a.swift", content: "mine\n")

        let file = root.appendingPathComponent("a.swift")
        try "theirs\n".write(to: file, atomically: true, encoding: .utf8)
        store.handleFileSystemChanges([FileSystemChange(kind: .change, path: file.path)])

        XCTAssertEqual(store.activeTab?.content, "mine\n")
        XCTAssertTrue(store.activeTab?.diskChanged ?? false)
        XCTAssertNil(store.pendingReveal)
    }

    /// The path FSEvents reports is canonical, while the root is stored the
    /// way it was chosen. On a project reached through a symlink -- /tmp, or
    /// a home behind one -- the two never matched as plain strings, so no
    /// open tab ever followed anything. The file tree hid it by reloading on
    /// any event at all.
    func test_followsAWriteReportedThroughASymlinkedPath() throws {
        let root = try makeProject()
        let store = try makeStore(root: root)
        store.open(path: "a.swift")

        let file = root.appendingPathComponent("a.swift")
        try "one\ntwo\nthree\nfour\n".write(to: file, atomically: true, encoding: .utf8)
        // What the watcher actually delivers for a temp directory on macOS.
        let asDelivered = "/private" + file.path
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: asDelivered),
            "this machine's temporary directory is not behind /private"
        )
        store.handleFileSystemChanges([FileSystemChange(kind: .change, path: asDelivered)])

        XCTAssertEqual(store.activeTab?.content, "one\ntwo\nthree\nfour\n")
    }
}
