//
//  ChangeReviewModelTests.swift
//  PuckTests
//
//  The review's own decisions, without a repository: what it loads, what it
//  opens, and what reverting takes out of the list.
//

import XCTest
@testable import Puck

@MainActor
final class ChangeReviewModelTests: XCTestCase {
    private func diff(path: String, added: Int = 1, removed: Int = 1) -> FileDiff {
        var lines: [DiffLine] = []
        for index in 0..<removed {
            lines.append(DiffLine(kind: .removed, text: "old \(index)", oldLine: index + 1, newLine: nil))
        }
        for index in 0..<added {
            lines.append(DiffLine(kind: .added, text: "new \(index)", oldLine: nil, newLine: index + 1))
        }
        return FileDiff(
            path: path,
            previousPath: nil,
            isBinary: false,
            hunks: [DiffHunk(header: "@@ -1 +1 @@", lines: lines)]
        )
    }

    func test_itLoadsWhatGitReports() async {
        let model = ChangeReviewModel(read: { _ in [self.diff(path: "a.swift"), self.diff(path: "b.swift")] })

        await model.reload(projectPath: "/tmp/project")

        XCTAssertEqual(model.files.map(\.path), ["a.swift", "b.swift"])
        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.isLoading)
    }

    /// A workspace with no project has nothing to review, and says so rather
    /// than showing the last project's changes.
    func test_noProjectMeansNothingToReview() async {
        let model = ChangeReviewModel(read: { _ in [self.diff(path: "a.swift")] })
        await model.reload(projectPath: "/tmp/project")

        await model.reload(projectPath: nil)

        XCTAssertTrue(model.files.isEmpty)
    }

    /// Everything starts closed: a run that touched twelve files would
    /// otherwise open onto twelve expanded diffs, and the list of *what*
    /// changed is what is being looked at first.
    func test_everythingStartsClosed() async {
        let model = ChangeReviewModel(read: { _ in [self.diff(path: "a.swift")] })

        await model.reload(projectPath: "/tmp/project")

        XCTAssertTrue(model.expanded.isEmpty)
        model.toggle("a.swift")
        XCTAssertEqual(model.expanded, ["a.swift"])
        model.toggle("a.swift")
        XCTAssertTrue(model.expanded.isEmpty)
    }

    /// A reverted file leaves the list, because it is no longer a change --
    /// removed here rather than by re-reading, which costs a subprocess.
    func test_revertingTakesTheFileOutOfTheList() async {
        var reverted: [String] = []
        let model = ChangeReviewModel(
            read: { _ in [self.diff(path: "a.swift"), self.diff(path: "b.swift")] },
            revertFile: { path, _, _ in reverted.append(path); return true }
        )
        await model.reload(projectPath: "/tmp/project")
        model.toggle("a.swift")

        await model.revert(model.files[0], projectPath: "/tmp/project")

        XCTAssertEqual(reverted, ["a.swift"])
        XCTAssertEqual(model.files.map(\.path), ["b.swift"])
        XCTAssertTrue(model.expanded.isEmpty, "the row it was open in has gone")
    }

    /// A revert that did not happen must not take the row away: the file is
    /// still changed, and a list that says otherwise is worse than an error.
    func test_aFailedRevertLeavesTheListAlone() async {
        let model = ChangeReviewModel(
            read: { _ in [self.diff(path: "a.swift")] },
            revertFile: { _, _, _ in false }
        )
        await model.reload(projectPath: "/tmp/project")

        await model.revert(model.files[0], projectPath: "/tmp/project")

        XCTAssertEqual(model.files.map(\.path), ["a.swift"])
    }

    /// A file git has never seen has no committed version to go back to, so
    /// reverting it means deleting it -- and the two are different enough
    /// that the distinction has to reach DiffReader.
    func test_aNewlyCreatedFileIsRevertedAsUntracked() async {
        var sawUntracked: Bool?
        let created = FileDiff(
            path: "new.swift",
            previousPath: nil,
            isBinary: false,
            hunks: [DiffHunk(header: "@@ -0,0 +1,2 @@", lines: [
                DiffLine(kind: .added, text: "one", oldLine: nil, newLine: 1),
                DiffLine(kind: .added, text: "two", oldLine: nil, newLine: 2),
            ])]
        )
        let model = ChangeReviewModel(
            read: { _ in [created] },
            revertFile: { _, _, untracked in sawUntracked = untracked; return true }
        )
        await model.reload(projectPath: "/tmp/project")

        await model.revert(model.files[0], projectPath: "/tmp/project")

        XCTAssertEqual(sawUntracked, true)
    }

    /// And an edited file is not: it has a committed version, so it is put
    /// back rather than deleted.
    func test_anEditedFileIsNotTreatedAsUntracked() async {
        var sawUntracked: Bool?
        let model = ChangeReviewModel(
            read: { _ in [self.diff(path: "a.swift", added: 1, removed: 1)] },
            revertFile: { _, _, untracked in sawUntracked = untracked; return true }
        )
        await model.reload(projectPath: "/tmp/project")

        await model.revert(model.files[0], projectPath: "/tmp/project")

        XCTAssertEqual(sawUntracked, false)
    }

    /// The header's counts are the whole review's, so a glance says how big
    /// the change is before anything is opened.
    func test_theCountsAreTheWholeReviews() async {
        let model = ChangeReviewModel(read: { _ in [
            self.diff(path: "a.swift", added: 3, removed: 1),
            self.diff(path: "b.swift", added: 2, removed: 5),
        ] })

        await model.reload(projectPath: "/tmp/project")

        XCTAssertEqual(model.addedCount, 5)
        XCTAssertEqual(model.removedCount, 6)
    }
}
