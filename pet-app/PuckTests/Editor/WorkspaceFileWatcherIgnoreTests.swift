//
//  WorkspaceFileWatcherIgnoreTests.swift
//  PuckTests
//
//  Which change events are worth waking the editor for.
//

import XCTest
@testable import Puck

final class WorkspaceFileWatcherIgnoreTests: XCTestCase {
    func testAPathInsideAnIgnoredDirectoryIsIgnored() {
        XCTAssertTrue(WorkspaceFileWatcher.isInsideIgnoredDirectory(
            "/Users/me/project/node_modules/left-pad/index.js",
            root: "/Users/me/project"
        ))
        XCTAssertTrue(WorkspaceFileWatcher.isInsideIgnoredDirectory(
            "/Users/me/project/.git/index",
            root: "/Users/me/project"
        ))
    }

    func testAnOrdinaryPathIsNot() {
        XCTAssertFalse(WorkspaceFileWatcher.isInsideIgnoredDirectory(
            "/Users/me/project/src/index.js",
            root: "/Users/me/project"
        ))
    }

    /// The reported gap. FSEvents reports the filesystem's own spelling of a
    /// path -- `/private/tmp/...` -- while a project opened at `/tmp/x` keeps
    /// that one, so the two never lined up and every write under
    /// node_modules was delivered, each costing a tree reload and a git
    /// status. A real directory, because resolving a symlink is a question
    /// about the filesystem and a made-up path has no answer.
    func testTheRootIsMatchedThroughASymlink() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("puck-watcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // What FSEvents would report for a file in there.
        let canonical = try XCTUnwrap(realpath(root.path, nil).map { pointer -> String in
            defer { free(pointer) }
            return String(cString: pointer)
        })
        try XCTSkipIf(canonical == root.path, "this machine does not symlink /tmp")

        XCTAssertTrue(WorkspaceFileWatcher.isInsideIgnoredDirectory(
            canonical + "/node_modules/left-pad/index.js",
            root: root.path
        ))
        XCTAssertFalse(WorkspaceFileWatcher.isInsideIgnoredDirectory(
            canonical + "/src/index.js",
            root: root.path
        ))
    }

    /// A path outside the project entirely is not "inside an ignored
    /// directory" -- it is somebody else's file, and the caller decides.
    func testAPathOutsideTheRootIsNotClaimed() {
        XCTAssertFalse(WorkspaceFileWatcher.isInsideIgnoredDirectory(
            "/Users/me/elsewhere/node_modules/x",
            root: "/Users/me/project"
        ))
    }
}
