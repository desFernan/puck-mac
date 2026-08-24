//
//  EditorPaneStoreTests.swift
//  Puck
//
//  Runs against a real, temp-directory-backed WorkspaceFileService rather
//  than a hand-rolled fake -- WorkspaceFileServiceTests already covers that
//  type's own correctness in isolation, and local-disk I/O here is fast and
//  deterministic enough that a fake would only add an abstraction with no
//  real benefit over exercising the real integration.
//

import XCTest
@testable import Puck

final class EditorPaneStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ string: String, at relativePath: String) throws {
        let target = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(string.utf8).write(to: target)
    }

    private func makeStore() throws -> EditorPaneStore {
        try EditorPaneStore(workspaceId: "w1", root: root, onRootChanged: {})
    }

    func test_open_addsATabAndMakesItActive() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()

        store.open(path: "a.txt")

        XCTAssertEqual(store.openTabs.map(\.path), ["a.txt"])
        XCTAssertEqual(store.activeTabPath, "a.txt")
        XCTAssertEqual(store.activeTab?.content, "hello")
        XCTAssertFalse(store.activeTab?.isDirty ?? true)
    }

    func test_open_sameFileTwice_doesNotDuplicateTheTab() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()

        store.open(path: "a.txt")
        store.open(path: "a.txt")

        XCTAssertEqual(store.openTabs.count, 1)
    }

    func test_updateDraft_marksTheTabDirtyWithoutTouchingDisk() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")

        store.updateDraft(path: "a.txt", content: "hello world")

        XCTAssertTrue(store.activeTab?.isDirty ?? false)
        let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(onDisk, "hello")
    }

    func test_save_writesToDiskAndClearsDirty() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "hello world")

        store.save(path: "a.txt")

        XCTAssertFalse(store.activeTab?.isDirty ?? true)
        let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(onDisk, "hello world")
    }

    func test_close_removesTheTabAndFallsBackToTheOneBeforeIt() throws {
        try write("a", at: "a.txt")
        try write("b", at: "b.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.open(path: "b.txt")

        store.close(path: "b.txt")

        XCTAssertEqual(store.openTabs.map(\.path), ["a.txt"])
        XCTAssertEqual(store.activeTabPath, "a.txt")
    }

    /// Closing one from the middle goes to the tab that took its place, not
    /// to the far end of the strip -- where the eye is not.
    func test_close_movesToTheNeighbourRatherThanTheLastTab() throws {
        for name in ["a", "b", "c"] { try write(name, at: "\(name).txt") }
        let store = try makeStore()
        for name in ["a", "b", "c"] { store.open(path: "\(name).txt") }
        store.select(path: "b.txt")

        store.close(path: "b.txt")

        XCTAssertEqual(store.activeTabPath, "c.txt", "the tab that took its place")
    }

    /// Closing the last tab has no successor, so focus goes to the one before.
    func test_close_ofTheLastTabMovesLeft() throws {
        for name in ["a", "b"] { try write(name, at: "\(name).txt") }
        let store = try makeStore()
        for name in ["a", "b"] { store.open(path: "\(name).txt") }

        store.close(path: "b.txt")

        XCTAssertEqual(store.activeTabPath, "a.txt")
    }

    /// Closing the only tab leaves nothing to focus, and nothing is a valid
    /// answer -- the code column shows its empty state.
    func test_close_ofTheOnlyTabLeavesNothingActive() throws {
        try write("a", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")

        store.close(path: "a.txt")

        XCTAssertNil(store.activeTabPath)
    }

    func test_save_onExternalConflict_setsDiskChangedAndDoesNotOverwrite() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "my edit")

        // Simulate an external process changing the file after this tab read it.
        try write("changed elsewhere", at: "a.txt")

        store.save(path: "a.txt")

        XCTAssertEqual(store.lastError?.code, .fileConflict)
        XCTAssertTrue(store.activeTab?.diskChanged ?? false)
        let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(onDisk, "changed elsewhere", "a conflicting save must not touch the file on disk")
    }

    func test_useDisk_discardsTheDraftAndClearsConflict() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "my edit")
        try write("changed elsewhere", at: "a.txt")
        store.save(path: "a.txt")
        XCTAssertTrue(store.activeTab?.diskChanged ?? false)

        store.useDisk(path: "a.txt")

        XCTAssertEqual(store.activeTab?.content, "changed elsewhere")
        XCTAssertFalse(store.activeTab?.isDirty ?? true)
        XCTAssertFalse(store.activeTab?.diskChanged ?? true)
        // The count the editor view is keyed on. Without it the view is not
        // rebuilt, the discarded draft stays on screen, and the next
        // keystroke writes it back over the file the user chose to keep --
        // so "the tab holds the right text" is only half the assertion.
        XCTAssertEqual(store.activeTab?.adoptions, 1)
    }

    func test_keepMine_reanchorsAndSavesTheDraft() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "my edit")
        try write("changed elsewhere", at: "a.txt")
        store.save(path: "a.txt")
        XCTAssertTrue(store.activeTab?.diskChanged ?? false)

        store.keepMine(path: "a.txt")

        XCTAssertFalse(store.activeTab?.diskChanged ?? true)
        XCTAssertFalse(store.activeTab?.isDirty ?? true)
        let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(onDisk, "my edit")
    }

    func test_readOnlyTab_ignoresDraftUpdatesAndSave() throws {
        try write(String(repeating: "x", count: 20), at: "big.txt")
        let store = try EditorPaneStore(workspaceId: "w1", root: root, editableSizeLimit: 10, onRootChanged: {})
        store.open(path: "big.txt")

        XCTAssertTrue(store.activeTab?.readOnly ?? false)

        store.updateDraft(path: "big.txt", content: "should be ignored")
        XCTAssertEqual(store.activeTab?.content, String(repeating: "x", count: 20))

        store.save(path: "big.txt")
        let onDisk = try String(contentsOf: root.appendingPathComponent("big.txt"), encoding: .utf8)
        XCTAssertEqual(onDisk, String(repeating: "x", count: 20), "a read-only tab's save must be a no-op")
    }

    /// Renaming the file you are looking at keeps you on it, under its new
    /// name.
    func test_rename_followsTheActiveTab() throws {
        try write("a", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")

        store.rename(path: "a.txt", to: "b.txt")

        XCTAssertEqual(store.openTabs.map(\.path), ["b.txt"])
        XCTAssertEqual(store.activeTabPath, "b.txt")
    }

    /// Renaming one you are *not* looking at must not drag you over to it,
    /// nor to whatever tab happens to be last.
    func test_rename_ofAnInactiveTabLeavesFocusAlone() throws {
        for name in ["a", "b", "c"] { try write(name, at: "\(name).txt") }
        let store = try makeStore()
        for name in ["a", "b", "c"] { store.open(path: "\(name).txt") }
        store.select(path: "c.txt")

        store.rename(path: "a.txt", to: "z.txt")

        XCTAssertEqual(store.activeTabPath, "c.txt")
        XCTAssertTrue(store.openTabs.contains { $0.path == "z.txt" })
    }

    /// Trashing a directory closes what was open from inside it -- a tab with
    /// nowhere to save to is worse than no tab.
    func test_trash_closesTabsUnderTheDeletedDirectory() throws {
        try write("a", at: "src/a.txt")
        try write("b", at: "keep.txt")
        let store = try makeStore()
        store.open(path: "src/a.txt")
        store.open(path: "keep.txt")

        store.trash(path: "src")

        XCTAssertEqual(store.openTabs.map(\.path), ["keep.txt"])
    }

    /// A rename onto a name that is taken has to say so. It set an error
    /// nothing displayed, so the menu item appeared to do nothing at all.
    func test_aFailedRenameReportsWhyAndChangesNothing() throws {
        try write("a", at: "a.txt")
        try write("b", at: "b.txt")
        let store = try makeStore()
        store.open(path: "a.txt")

        store.rename(path: "a.txt", to: "b.txt")

        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(store.lastError?.message.isEmpty ?? true)
        XCTAssertEqual(store.openTabs.map(\.path), ["a.txt"], "and the tab still points at the file that is still there")
    }

    /// The next attempt starts clean: an error from a minute ago must not be
    /// shown as if it were about the thing just done.
    func test_theNextOperationClearsTheLastError() throws {
        try write("a", at: "a.txt")
        try write("b", at: "b.txt")
        let store = try makeStore()
        store.rename(path: "a.txt", to: "b.txt")
        XCTAssertNotNil(store.lastError)

        store.rename(path: "a.txt", to: "c.txt")

        XCTAssertNil(store.lastError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("c.txt").path))
    }

    /// Same for the other two, which fail the same way and were equally
    /// silent about it.
    func test_creatingAndTrashingReportTheirFailures() throws {
        try write("a", at: "a.txt")
        let store = try makeStore()

        store.create(name: "a.txt", directory: false, in: nil)
        XCTAssertNotNil(store.lastError, "a name that is taken")

        store.trash(path: "gone.txt")
        XCTAssertNotNil(store.lastError, "something that is not there")
    }
}
