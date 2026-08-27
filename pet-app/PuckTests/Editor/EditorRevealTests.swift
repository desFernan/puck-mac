//
//  EditorRevealTests.swift
//  Puck
//
//  The store half of a code tour stop: open the file and publish the range
//  the view should select. Applying it to the text view is
//  EditorRevealCoordinator's job and needs a live editor, so it is not
//  tested here.
//

import XCTest
@testable import Puck

final class EditorRevealTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("line1\nline2\nline3\n".utf8).write(to: root.appendingPathComponent("a.swift"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore() throws -> EditorPaneStore {
        try EditorPaneStore(workspaceId: "w1", root: root, onRootChanged: {})
    }

    func test_revealOpensTheTabAndPublishesTheRange() throws {
        let store = try makeStore()

        store.reveal(path: "a.swift", lines: 1...2)

        XCTAssertEqual(store.activeTabPath, "a.swift")
        XCTAssertEqual(store.pendingReveal?.path, "a.swift")
        XCTAssertEqual(store.pendingReveal?.lines, 1...2)
    }

    /// The same range twice has to fire twice -- the user may have scrolled
    /// away and asked to see it again. Without a changing token the view
    /// sees an equal value and does nothing.
    func test_revealingTheSameRangeTwiceChangesTheToken() throws {
        let store = try makeStore()

        store.reveal(path: "a.swift", lines: 1...2)
        let first = try XCTUnwrap(store.pendingReveal?.token)
        store.reveal(path: "a.swift", lines: 1...2)
        let second = try XCTUnwrap(store.pendingReveal?.token)

        XCTAssertNotEqual(first, second)
    }

    /// A stop that names a file the workspace does not have must not leave a
    /// stale range behind for the view to apply to whatever is open.
    func test_revealOfAMissingFilePublishesNothing() throws {
        let store = try makeStore()

        store.reveal(path: "gone.swift", lines: 1...2)

        XCTAssertNil(store.pendingReveal)
        XCTAssertNotNil(store.lastError)
    }

    /// The pane rect is what the pet is sent to; nil means "not on screen",
    /// which is a fact the caller has to be able to see.
    func test_paneScreenFrameRoundTrips() throws {
        let store = try makeStore()

        store.setPaneScreenFrame(CGRect(x: 10, y: 20, width: 30, height: 40))
        XCTAssertEqual(store.paneScreenFrame, CGRect(x: 10, y: 20, width: 30, height: 40))

        store.setPaneScreenFrame(nil)
        XCTAssertNil(store.paneScreenFrame)
    }
}
