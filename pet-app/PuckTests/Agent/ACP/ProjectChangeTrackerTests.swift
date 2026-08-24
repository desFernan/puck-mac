//
//  ProjectChangeTrackerTests.swift
//  PuckTests
//
//  What counts as a file the agent changed.
//

import XCTest
@testable import Puck

final class ProjectChangeTrackerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("puck-tracker-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relative: String, _ contents: String = "x") throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The reported gap: the snapshot skipped every hidden path, so a CI
    /// workflow or a .env was invisible to it. The watcher was then the only
    /// witness, and a coalesced burst there cannot be recovered -- an agent
    /// asked to fix a workflow reported changing nothing.
    func testDotfilesAreSeen() throws {
        try write(".github/workflows/ci.yml")
        try write(".env")
        try write("README.md")

        let snapshot = ProjectChangeTracker.snapshot(of: root)

        XCTAssertNotNil(snapshot[".github/workflows/ci.yml"])
        XCTAssertNotNil(snapshot[".env"])
        XCTAssertNotNil(snapshot["README.md"])
    }

    /// What keeps the walk cheap now that hidden paths are not skipped
    /// wholesale. A commit rewrites hundreds of paths under .git and none of
    /// them are the agent's edit.
    func testMachineOwnedDirectoriesAreNot() throws {
        try write(".git/objects/ab/cdef")
        try write("node_modules/left-pad/index.js")
        try write(".build/debug/thing.o")
        try write(".DS_Store")

        let snapshot = ProjectChangeTracker.snapshot(of: root)

        XCTAssertTrue(snapshot.isEmpty, "got \(snapshot.keys.sorted())")
    }

    /// Nested, not only at the root: a package with its own node_modules is
    /// the same noise one directory down.
    func testNestedMachineOwnedDirectoriesAreNotEither() {
        XCTAssertNil(ProjectChangeTracker.relativePath(
            for: "/p/packages/web/node_modules/x/index.js",
            under: "/p"
        ))
        XCTAssertEqual(
            ProjectChangeTracker.relativePath(for: "/p/packages/web/src/index.js", under: "/p"),
            "packages/web/src/index.js"
        )
    }

    /// A directory named like an ignored one is still a file's own name: only
    /// the path *to* a file decides, not the file itself.
    func testAFileNamedLikeAnIgnoredDirectoryIsKept() {
        XCTAssertEqual(
            ProjectChangeTracker.relativePath(for: "/p/docs/node_modules", under: "/p"),
            "docs/node_modules"
        )
    }
}
