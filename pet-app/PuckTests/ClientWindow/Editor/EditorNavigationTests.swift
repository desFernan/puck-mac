//
//  EditorNavigationTests.swift
//  PuckTests
//
//  Moving around without the mouse: between the files already open (⌘⇧[ and
//  ⌘⇧]) and to a line inside one (⌘L). Both were things the pane had no
//  answer to at all -- switching files meant finding them in the tree again.
//

import XCTest
@testable import Puck

@MainActor
final class EditorNavigationTests: XCTestCase {
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

    private func makeStore(withOpenFiles files: [String]) throws -> EditorPaneStore {
        for file in files { try write("one\ntwo\nthree\n", at: file) }
        let store = try EditorPaneStore(workspaceId: "w1", root: root, onRootChanged: {})
        for file in files { store.open(path: file) }
        return store
    }

    // MARK: - Between tabs

    func test_selectNextTab_movesAlongTheStrip() throws {
        let store = try makeStore(withOpenFiles: ["a.txt", "b.txt", "c.txt"])
        store.select(path: "a.txt")

        store.selectNextTab()

        XCTAssertEqual(store.activeTabPath, "b.txt")
    }

    /// Round the end rather than stopping: the strip is a ring in every
    /// editor that has this, and stopping dead at the last tab makes the
    /// shortcut feel broken exactly when it is held down.
    func test_selectNextTab_wrapsAtTheEnd() throws {
        let store = try makeStore(withOpenFiles: ["a.txt", "b.txt"])
        store.select(path: "b.txt")

        store.selectNextTab()

        XCTAssertEqual(store.activeTabPath, "a.txt")
    }

    func test_selectPreviousTab_wrapsAtTheStart() throws {
        let store = try makeStore(withOpenFiles: ["a.txt", "b.txt"])
        store.select(path: "a.txt")

        store.selectPreviousTab()

        XCTAssertEqual(store.activeTabPath, "b.txt")
    }

    func test_selectNextTab_withNothingOpen_doesNothing() throws {
        let store = try EditorPaneStore(workspaceId: "w1", root: root, onRootChanged: {})

        store.selectNextTab()

        XCTAssertNil(store.activeTabPath)
    }

    /// A pane with tabs but no selection still has somewhere to go.
    func test_selectNextTab_withNoSelection_takesTheFirstTab() throws {
        let store = try makeStore(withOpenFiles: ["a.txt", "b.txt"])
        store.activeTabPath = nil

        store.selectNextTab()

        XCTAssertEqual(store.activeTabPath, "a.txt")
    }

    // MARK: - To a line

    func test_goToLine_asksTheEditorToShowThatLine() throws {
        let store = try makeStore(withOpenFiles: ["a.txt"])

        store.goToLine(2)

        XCTAssertEqual(store.pendingReveal?.path, "a.txt")
        XCTAssertEqual(store.pendingReveal?.lines, 2...2)
    }

    /// Someone typing a line number is aiming. The end of the file is the
    /// honest answer to a number past it, and a refusal is not.
    func test_goToLine_pastTheEnd_landsOnTheLastLine() throws {
        let store = try makeStore(withOpenFiles: ["a.txt"])

        store.goToLine(9999)

        XCTAssertEqual(store.pendingReveal?.lines, 3...3, "three lines and a trailing newline")
    }

    func test_goToLine_belowOne_landsOnTheFirstLine() throws {
        let store = try makeStore(withOpenFiles: ["a.txt"])

        store.goToLine(0)

        XCTAssertEqual(store.pendingReveal?.lines, 1...1)
    }

    func test_goToLine_withNothingOpen_doesNothing() throws {
        let store = try EditorPaneStore(workspaceId: "w1", root: root, onRootChanged: {})

        store.goToLine(3)

        XCTAssertNil(store.pendingReveal)
    }

    /// A trailing newline ends the last line rather than starting an empty
    /// one after it -- otherwise every file has a phantom line at the bottom.
    func test_clampedLine_countsATrailingNewlineAsTheEndOfTheLastLine() {
        XCTAssertEqual(EditorPaneStore.clampedLine(99, in: "a\nb\n"), 2)
        XCTAssertEqual(EditorPaneStore.clampedLine(99, in: "a\nb"), 2)
        XCTAssertEqual(EditorPaneStore.clampedLine(99, in: ""), 1)
    }
    // MARK: - Find

    /// The editor package has a find bar; nothing in this app ever opened it,
    /// so searching inside a file meant reading it.
    func test_showFind_asksTheEditorForTheFileBeingLookedAt() throws {
        let store = try makeStore(withOpenFiles: ["a.txt", "b.txt"])
        store.select(path: "a.txt")

        store.showFind()

        XCTAssertEqual(store.pendingFind?.path, "a.txt")
    }

    /// Asking twice has to fire twice: the bar may have been closed in
    /// between, and an unchanged value is a value the view ignores.
    func test_showFind_twice_changesTheToken() throws {
        let store = try makeStore(withOpenFiles: ["a.txt"])

        store.showFind()
        let first = store.pendingFind?.token
        store.showFind()

        XCTAssertNotEqual(store.pendingFind?.token, first)
    }

    func test_showFind_withNothingOpen_doesNothing() throws {
        let store = try EditorPaneStore(workspaceId: "w1", root: root, onRootChanged: {})

        store.showFind()

        XCTAssertNil(store.pendingFind)
    }
}
