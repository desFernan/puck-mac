//
//  ChangeReviewFocusTests.swift
//  PuckTests
//
//  Reviewing what one run changed, rather than everything in the project.
//

import XCTest
@testable import Puck

@MainActor
final class ChangeReviewFocusTests: XCTestCase {
    private func diff(_ path: String, previous: String? = nil) -> FileDiff {
        FileDiff(path: path, previousPath: previous, isBinary: false, hunks: [])
    }

    /// The toolbar's question is about the project.
    func test_withNoFocusEverythingIsShown() {
        let files = [diff("a.swift"), diff("b.swift")]

        XCTAssertEqual(ChangeReviewModel.narrowed(files, to: []).map(\.path), ["a.swift", "b.swift"])
    }

    /// A run's own row is about that run: a list that also carried what the
    /// user has been editing since makes "did the agent do this?"
    /// unanswerable.
    func test_withAFocusOnlyThoseFilesAreShown() {
        let files = [diff("a.swift"), diff("b.swift"), diff("c.swift")]

        XCTAssertEqual(ChangeReviewModel.narrowed(files, to: ["b.swift"]).map(\.path), ["b.swift"])
    }

    /// The agent reports where it wrote, which is often absolute; git reports
    /// a path relative to the repository root. They are the same file.
    func test_anAbsolutePathFromTheAgentMatchesGitsRelativeOne() {
        let files = [diff("Sources/main.swift")]

        let narrowed = ChangeReviewModel.narrowed(files, to: ["/Users/x/project/Sources/main.swift"])

        XCTAssertEqual(narrowed.map(\.path), ["Sources/main.swift"])
    }

    /// A renamed file is one file, and the agent may name either end of it.
    func test_eitherSideOfARenameFindsIt() {
        let files = [diff("new.swift", previous: "old.swift")]

        XCTAssertEqual(ChangeReviewModel.narrowed(files, to: ["old.swift"]).count, 1)
        XCTAssertEqual(ChangeReviewModel.narrowed(files, to: ["new.swift"]).count, 1)
    }

    /// Reverted, committed, or touched and put back: the file is simply not
    /// in the diff any more, and an empty review says so.
    func test_aFocusedFileWithNothingToShowIsAbsentRatherThanBlank() {
        XCTAssertTrue(ChangeReviewModel.narrowed([diff("a.swift")], to: ["gone.swift"]).isEmpty)
    }

    /// A partial name is not a match: `b.swift` and `sub/b.swift` are
    /// different files, and only a whole path component boundary makes them
    /// the same one.
    func test_aPathIsNotMatchedByAccident() {
        XCTAssertTrue(ChangeReviewModel.narrowed([diff("lib.swift")], to: ["b.swift"]).isEmpty)
    }
}
