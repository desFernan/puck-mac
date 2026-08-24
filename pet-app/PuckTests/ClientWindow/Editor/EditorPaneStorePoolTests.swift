//
//  EditorPaneStorePoolTests.swift
//  PuckTests
//
//  Covers the invariant EditorPaneView relies on to decide whether the pane
//  it is showing belongs to the workspace that is actually selected: each
//  store knows its own workspace, and the pool hands back a distinct one per
//  workspace while keeping each alive.
//
//  The bug this was written for: the pane attached a store once and never
//  swapped it, so after switching workspaces it kept rendering the first
//  project's tree while the sidebar, the status bar and the chat had all
//  moved on.
//

import XCTest
@testable import Puck

final class EditorPaneStorePoolTests: XCTestCase {
    private var root: URL!
    private var first: URL!
    private var second: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EditorPaneStorePoolTests-\(UUID().uuidString)", isDirectory: true)
        first = root.appendingPathComponent("first", isDirectory: true)
        second = root.appendingPathComponent("second", isDirectory: true)
        for directory in [first, second] {
            try FileManager.default.createDirectory(at: directory!, withIntermediateDirectories: true)
        }
        try Data("one".utf8).write(to: first.appendingPathComponent("only-in-first.txt"))
        try Data("two".utf8).write(to: second.appendingPathComponent("only-in-second.txt"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @MainActor
    func testEachStoreKnowsItsWorkspace() throws {
        // This is what EditorPaneView compares against the workspace it was
        // handed; without it there is no way to notice a stale pane.
        let store = try EditorPaneStorePool.shared.store(
            forWorkspace: "w-\(UUID().uuidString)", root: first, onRootChanged: {}
        )

        XCTAssertFalse(store.workspaceId.isEmpty)
    }

    @MainActor
    func testTwoWorkspacesGetDifferentStoresShowingTheirOwnFiles() throws {
        let firstID = "w-first-\(UUID().uuidString)"
        let secondID = "w-second-\(UUID().uuidString)"

        let firstStore = try EditorPaneStorePool.shared.store(forWorkspace: firstID, root: first, onRootChanged: {})
        let secondStore = try EditorPaneStorePool.shared.store(forWorkspace: secondID, root: second, onRootChanged: {})

        XCTAssertNotIdentical(firstStore, secondStore)
        XCTAssertEqual(firstStore.workspaceId, firstID)
        XCTAssertEqual(secondStore.workspaceId, secondID)
        XCTAssertEqual(firstStore.tree.map(\.name), ["only-in-first.txt"])
        XCTAssertEqual(secondStore.tree.map(\.name), ["only-in-second.txt"])
    }

    @MainActor
    func testAskingTwiceForOneWorkspaceReusesItsStore() throws {
        let workspaceID = "w-\(UUID().uuidString)"

        let once = try EditorPaneStorePool.shared.store(forWorkspace: workspaceID, root: first, onRootChanged: {})
        let twice = try EditorPaneStorePool.shared.store(forWorkspace: workspaceID, root: first, onRootChanged: {})

        // Why switching away and back is cheap, and why open tabs survive it.
        XCTAssertIdentical(once, twice)
    }

    /// A store keyed on the workspace but watching a different directory
    /// would show one project's files under another's name, with a file
    /// watcher on the wrong tree.
    @MainActor
    func test_aDifferentRootGetsItsOwnStore() throws {
        let pool = EditorPaneStorePool.shared
        let id = "workspace-\(UUID().uuidString)"

        let one = try pool.store(forWorkspace: id, root: first, onRootChanged: {})
        let two = try pool.store(forWorkspace: id, root: second, onRootChanged: {})

        XCTAssertFalse(one === two)
        XCTAssertEqual(two.rootPath, (try WorkspaceFileService.realpath(second)).path)
    }

    /// The same directory reached by another name is the same root, so the
    /// open tabs and the watcher are kept.
    @MainActor
    func test_theSameRootByAnotherNameKeepsTheStore() throws {
        let pool = EditorPaneStorePool.shared
        let id = "workspace-\(UUID().uuidString)"

        let one = try pool.store(forWorkspace: id, root: first, onRootChanged: {})
        let again = try pool.store(
            forWorkspace: id,
            root: first.appendingPathComponent("."),
            onRootChanged: {}
        )

        XCTAssertTrue(one === again)
    }
}
