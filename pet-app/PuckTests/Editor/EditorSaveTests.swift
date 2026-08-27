//
//  EditorSaveTests.swift
//  PuckTests
//
//  Saving from the editor pane. Until this existed the only caller of
//  EditorPaneStore.save(path:) was the conflict banner's "내 내용 유지", so a
//  draft could only ever reach disk by provoking a conflict first -- and
//  closing a tab dropped it outright. These cover the save command, the
//  guards that make it a no-op when there is nothing to write, and the
//  close-with-unsaved-changes prompt.
//

import AppKit
import SwiftUI
import XCTest
@testable import Puck

final class EditorSaveTests: XCTestCase {
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

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func makeStore(editableSizeLimit: Int = WorkspaceFileServiceDefaults.editableSizeLimit) throws -> EditorPaneStore {
        try EditorPaneStore(
            workspaceId: "w-\(UUID().uuidString)",
            root: root,
            editableSizeLimit: editableSizeLimit,
            onRootChanged: {}
        )
    }

    // MARK: - The save command

    func test_saveActiveTab_writesTheDraftToDisk() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "hello world")

        store.saveActiveTab()

        XCTAssertEqual(try read("a.txt"), "hello world")
        XCTAssertFalse(store.activeTab?.isDirty ?? true, "the dirty dot has to clear once the file is on disk")
    }

    func test_saveActiveTab_savesTheActiveTabOnly() throws {
        try write("a", at: "a.txt")
        try write("b", at: "b.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.open(path: "b.txt")
        store.updateDraft(path: "a.txt", content: "a edited")
        store.updateDraft(path: "b.txt", content: "b edited")

        store.saveActiveTab()

        XCTAssertEqual(try read("b.txt"), "b edited")
        XCTAssertEqual(try read("a.txt"), "a", "a background tab is not part of this save")
    }

    func test_saveActiveTab_withNoTabOpen_isAHarmlessNoOp() throws {
        let store = try makeStore()

        XCTAssertFalse(store.canSaveActiveTab)
        store.saveActiveTab()

        XCTAssertNil(store.lastError)
    }

    func test_saveActiveTab_withNothingDirty_doesNotTouchTheFile() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        let modifiedBefore = try FileManager.default
            .attributesOfItem(atPath: root.appendingPathComponent("a.txt").path)[.modificationDate] as? Date

        XCTAssertFalse(store.canSaveActiveTab)
        store.saveActiveTab()

        let modifiedAfter = try FileManager.default
            .attributesOfItem(atPath: root.appendingPathComponent("a.txt").path)[.modificationDate] as? Date
        XCTAssertEqual(modifiedBefore, modifiedAfter, "a save with nothing to save must not rewrite the file")
        XCTAssertNil(store.lastError)
    }

    func test_canSaveActiveTab_isFalseForAReadOnlyTab() throws {
        try write(String(repeating: "x", count: 20), at: "big.txt")
        let store = try makeStore(editableSizeLimit: 10)
        store.open(path: "big.txt")

        XCTAssertFalse(store.canSaveActiveTab)
    }

    func test_canSaveActiveTab_followsTheDraft() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        XCTAssertFalse(store.canSaveActiveTab)

        store.updateDraft(path: "a.txt", content: "typed")
        XCTAssertTrue(store.canSaveActiveTab)

        store.saveActiveTab()
        XCTAssertFalse(store.canSaveActiveTab)
    }

    /// The watcher sees our own write and would otherwise raise the conflict
    /// banner against a save the user just asked for.
    func test_saveActiveTab_doesNotMakeTheWatcherFlagItsOwnWrite() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "hello world")

        store.saveActiveTab()
        store.handleFileSystemChanges([
            FileSystemChange(kind: .change, path: root.appendingPathComponent("a.txt").resolvingSymlinksInPath().path),
        ])

        XCTAssertFalse(store.activeTab?.diskChanged ?? true, "our own save is not an external change")
        XCTAssertEqual(store.activeTab?.content, "hello world")
    }

    func test_saveActiveTab_onConflict_raisesTheBannerAndKeepsTheDraft() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "my edit")
        try write("changed elsewhere", at: "a.txt")

        store.saveActiveTab()

        XCTAssertEqual(store.lastError?.code, .fileConflict)
        XCTAssertTrue(store.activeTab?.diskChanged ?? false)
        XCTAssertEqual(store.activeTab?.content, "my edit")
        XCTAssertEqual(try read("a.txt"), "changed elsewhere")
    }

    // MARK: - Closing a tab with unsaved changes

    func test_requestClose_withUnsavedChanges_keepsTheTabAndAsks() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "unsaved work")

        store.requestClose(path: "a.txt")

        XCTAssertEqual(store.pendingClosePath, "a.txt")
        XCTAssertEqual(store.openTabs.map(\.path), ["a.txt"], "closing must not throw the draft away before asking")
        XCTAssertEqual(store.activeTab?.content, "unsaved work")
    }

    func test_requestClose_withNothingUnsaved_closesStraightAway() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")

        store.requestClose(path: "a.txt")

        XCTAssertNil(store.pendingClosePath, "a clean tab has nothing to ask about")
        XCTAssertTrue(store.openTabs.isEmpty)
    }

    func test_confirmPendingCloseSaving_writesThenCloses() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "unsaved work")
        store.requestClose(path: "a.txt")

        store.confirmPendingCloseSaving()

        XCTAssertEqual(try read("a.txt"), "unsaved work")
        XCTAssertTrue(store.openTabs.isEmpty)
        XCTAssertNil(store.pendingClosePath)
    }

    func test_confirmPendingCloseSaving_onConflict_leavesTheTabOpen() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "unsaved work")
        try write("changed elsewhere", at: "a.txt")
        store.requestClose(path: "a.txt")

        store.confirmPendingCloseSaving()

        XCTAssertEqual(store.openTabs.map(\.path), ["a.txt"], "a save that failed must not close the tab anyway")
        XCTAssertEqual(store.activeTab?.content, "unsaved work")
        XCTAssertTrue(store.activeTab?.diskChanged ?? false)
        XCTAssertNil(store.pendingClosePath)
    }

    func test_confirmPendingCloseDiscarding_closesWithoutWriting() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "unsaved work")
        store.requestClose(path: "a.txt")

        store.confirmPendingCloseDiscarding()

        XCTAssertTrue(store.openTabs.isEmpty)
        XCTAssertEqual(try read("a.txt"), "hello")
        XCTAssertNil(store.pendingClosePath)
    }

    func test_cancelPendingClose_keepsTheTabAndItsDraft() throws {
        try write("hello", at: "a.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "unsaved work")
        store.requestClose(path: "a.txt")

        store.cancelPendingClose()

        XCTAssertNil(store.pendingClosePath)
        XCTAssertEqual(store.openTabs.map(\.path), ["a.txt"])
        XCTAssertEqual(store.activeTab?.content, "unsaved work")
    }

    func test_requestClose_onADifferentDirtyTab_asksAboutThatTab() throws {
        try write("a", at: "a.txt")
        try write("b", at: "b.txt")
        let store = try makeStore()
        store.open(path: "a.txt")
        store.updateDraft(path: "a.txt", content: "a edited")
        store.open(path: "b.txt")

        store.requestClose(path: "a.txt")

        XCTAssertEqual(store.pendingClosePath, "a.txt")
        XCTAssertEqual(store.activeTabPath, "b.txt", "asking about a background tab does not steal the selection")
    }
}

/// ⌘S has to reach the save command from whichever window has focus -- the
/// split pane in the client window and the detached editor window are two
/// NSHostingControllers over the same `EditorTabStripView`, so what this
/// pins down is that the shortcut survives being hosted in a plain AppKit
/// window at all. Driven through NSWindow.performKeyEquivalent, which is the
/// same entry point AppKit uses for a real key press.
@MainActor
final class EditorSaveShortcutTests: XCTestCase {
    private func makeTab(path: String, content: String, saved: String) -> EditorTab {
        var tab = EditorTab(FileContent(
            path: path,
            content: saved,
            revision: "r1",
            readOnly: false,
            size: saved.count,
            language: "Swift"
        ))
        tab.content = content
        return tab
    }

    private func hostTabStrip(canSave: Bool, onSave: @escaping () -> Void) -> NSWindow {
        let strip = EditorTabStripView(
            tabs: [makeTab(path: "a.txt", content: "typed", saved: "hello")],
            activeTabPath: "a.txt",
            canSave: canSave,
            onSelect: { _ in },
            onClose: { _ in },
            onSave: onSave
        )
        .environment(\.clientPalette, ClientPalette.dark)
        let controller = NSHostingController(rootView: AnyView(strip))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // Never ordered on screen, and never `close()`d: a test host that
        // puts real windows up and tears them down mid-suite destabilises
        // the shared NSApplication other tests are running in. The view only
        // has to be in a window for SwiftUI to register its key equivalents.
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.layoutIfNeeded()
        return window
    }

    private func commandS(for window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "s",
            charactersIgnoringModifiers: "s",
            isARepeat: false,
            keyCode: 1
        )!
    }

    func test_commandS_firesTheSaveCommand() {
        var saves = 0
        let window = hostTabStrip(canSave: true) { saves += 1 }

        let handled = window.performKeyEquivalent(with: commandS(for: window))

        XCTAssertTrue(handled, "⌘S has to be claimed by the editor, not fall through")
        XCTAssertEqual(saves, 1)
    }

    func test_commandS_withNothingToSave_doesNothing() {
        var saves = 0
        let window = hostTabStrip(canSave: false) { saves += 1 }

        _ = window.performKeyEquivalent(with: commandS(for: window))

        XCTAssertEqual(saves, 0, "a disabled save must not run")
    }
}
