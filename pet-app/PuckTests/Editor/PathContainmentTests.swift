//
//  PathContainmentTests.swift
//  Puck
//

import XCTest
@testable import Puck

final class PathContainmentTests: XCTestCase {
    func test_rootItself_isInside() {
        XCTAssertTrue(PathContainment.isInside(root: "/a/b", candidate: "/a/b"))
    }

    func test_childPath_isInside() {
        XCTAssertTrue(PathContainment.isInside(root: "/a/b", candidate: "/a/b/c"))
    }

    func test_siblingWithSharedPrefix_isNotInside() {
        // "/a/bc" shares the "/a/b" text prefix but is not inside "/a/b".
        XCTAssertFalse(PathContainment.isInside(root: "/a/b", candidate: "/a/bc"))
    }

    func test_parentPath_isNotInside() {
        XCTAssertFalse(PathContainment.isInside(root: "/a/b", candidate: "/a"))
    }

    func test_unrelatedAbsolutePath_isNotInside() {
        XCTAssertFalse(PathContainment.isInside(root: "/a/b", candidate: "/etc/passwd"))
    }

    func test_rootWithTrailingSlash_normalizesTheSameAsWithout() {
        XCTAssertTrue(PathContainment.isInside(root: "/a/b/", candidate: "/a/b/c"))
        XCTAssertTrue(PathContainment.isInside(root: "/a/b/", candidate: "/a/b"))
    }

    // MARK: - relativePath

    func test_relativePath_stripsTheRoot() {
        XCTAssertEqual(PathContainment.relativePath(root: "/a/b", candidate: "/a/b/c/d.swift"), "c/d.swift")
    }

    /// The callers of this all used a bare `hasPrefix(root)` before, so a
    /// sibling directory sharing the root's text came back as a relative path
    /// starting mid-component -- `/a/b-old/x.swift` under root `/a/b` became
    /// `-old/x.swift`, which the editor pane then matched against an open tab.
    func test_relativePath_ofASiblingWithASharedPrefix_isNil() {
        XCTAssertNil(PathContainment.relativePath(root: "/a/b", candidate: "/a/b-old/x.swift"))
    }

    func test_relativePath_ofTheRootItself_isEmpty() {
        XCTAssertEqual(PathContainment.relativePath(root: "/a/b", candidate: "/a/b"), "")
    }

    func test_relativePath_outsideTheRoot_isNil() {
        XCTAssertNil(PathContainment.relativePath(root: "/a/b", candidate: "/etc/passwd"))
    }

    func test_relativePath_rootWithTrailingSlash_stripsTheSame() {
        XCTAssertEqual(PathContainment.relativePath(root: "/a/b/", candidate: "/a/b/c.swift"), "c.swift")
    }
}
