//
//  FileTreeChangedFilterTests.swift
//  PuckTests
//
//  Xcode's "modified" filter, which is the useful question in a project of
//  any size: what did that turn touch. The tree already knows -- it marks
//  changed files -- it just had no way to show only them.
//

import XCTest
@testable import Puck

final class FileTreeChangedFilterTests: XCTestCase {
    private let tree = [
        FileTreeEntry(
            name: "Sources",
            path: "Sources",
            kind: .directory,
            children: [
                FileTreeEntry(name: "App.swift", path: "Sources/App.swift", kind: .file, children: nil),
                FileTreeEntry(name: "Util.swift", path: "Sources/Util.swift", kind: .file, children: nil),
            ]
        ),
        FileTreeEntry(name: "README.md", path: "README.md", kind: .file, children: nil),
    ]

    func test_onlyTheChangedFilesSurvive() {
        let kept = FileTreeView.keepingChanged(tree, changedPaths: ["Sources/App.swift": "M"])

        XCTAssertEqual(FileTreeEntry.flattenedPaths(kept), ["Sources/App.swift"])
    }

    /// The directories that lead to a changed file stay, or the file has
    /// nowhere to be drawn.
    func test_theDirectoriesLeadingToThemStay() {
        let kept = FileTreeView.keepingChanged(tree, changedPaths: ["Sources/App.swift": "M"])

        XCTAssertEqual(kept.map(\.path), ["Sources"])
    }

    /// A directory with nothing changed under it is not a row worth drawing.
    func test_aDirectoryWithNothingChanged_isDropped() {
        let kept = FileTreeView.keepingChanged(tree, changedPaths: ["README.md": "A"])

        XCTAssertEqual(kept.map(\.path), ["README.md"])
    }

    func test_nothingChanged_leavesAnEmptyTree() {
        XCTAssertTrue(FileTreeView.keepingChanged(tree, changedPaths: [:]).isEmpty)
    }
}
