//
//  GitStatusParserTests.swift
//  Puck
//
//  Fixtures are real `git status --porcelain=v2 --branch` output.
//

import XCTest
@testable import Puck

final class GitStatusParserTests: XCTestCase {
    private let header = """
    # branch.oid bc3825cfff365899a33cea3c2fd85c6da0de6288
    # branch.head main
    # branch.upstream origin/main
    # branch.ab +5 -2
    """

    func test_readsTheBranchAndHowFarItHasDiverged() {
        let status = GitStatusParser.parse(status: header, numstat: "")
        XCTAssertEqual(status.branch, "main")
        XCTAssertEqual(status.upstream, "origin/main")
        XCTAssertEqual(status.ahead, 5)
        XCTAssertEqual(status.behind, 2)
        XCTAssertTrue(status.files.isEmpty)
    }

    /// A detached HEAD reports "(detached)", which is not a branch name and
    /// would read as one.
    func test_aDetachedHeadHasNoBranch() {
        let status = GitStatusParser.parse(status: "# branch.head (detached)", numstat: "")
        XCTAssertNil(status.branch)
    }

    func test_readsAModifiedFileAndItsLineCounts() {
        let line = "1 .M N... 100644 100644 100644 0212e23 0212e23 pet-app/Puck/ClientWindow/ClientWorkspace.swift"
        let status = GitStatusParser.parse(
            status: header + "\n" + line,
            numstat: "2\t0\tpet-app/Puck/ClientWindow/ClientWorkspace.swift"
        )
        let file = try? XCTUnwrap(status.files.first)
        XCTAssertEqual(file?.path, "pet-app/Puck/ClientWindow/ClientWorkspace.swift")
        XCTAssertEqual(file?.displayStatus, "M")
        XCTAssertEqual(file?.addedLines, 2)
        XCTAssertEqual(file?.deletedLines, 0)
        XCTAssertEqual(status.addedLines, 2)
    }

    /// The index's letter is what a commit would take, so it wins when both
    /// halves moved.
    func test_theIndexStatusWinsOverTheWorktreeOne() {
        let staged = GitStatusParser.parse(status: "1 A. N... 0 0 0 x y new.swift", numstat: "")
        XCTAssertEqual(staged.files.first?.displayStatus, "A")
        XCTAssertTrue(staged.files.first?.isStaged ?? false)

        let unstaged = GitStatusParser.parse(status: "1 .D N... 0 0 0 x y gone.swift", numstat: "")
        XCTAssertEqual(unstaged.files.first?.displayStatus, "D")
        XCTAssertFalse(unstaged.files.first?.isStaged ?? true)
    }

    /// An untracked file has no diff to count, and reads as an addition
    /// because that is what committing it would be.
    func test_untrackedFilesAreListedAsAdditionsWithNoCounts() {
        let status = GitStatusParser.parse(status: "? Notes.md", numstat: "")
        XCTAssertEqual(status.files.first?.path, "Notes.md")
        XCTAssertEqual(status.files.first?.displayStatus, "A")
        XCTAssertTrue(status.files.first?.isUntracked ?? false)
        XCTAssertNil(status.files.first?.addedLines)
    }

    /// A rename carries "new\told"; the new name is the one to show.
    func test_aRenameIsShownUnderItsNewName() {
        let line = "2 R. N... 100644 100644 100644 x y R100 after.swift\tbefore.swift"
        let status = GitStatusParser.parse(status: line, numstat: "")
        XCTAssertEqual(status.files.first?.path, "after.swift")
    }

    /// The path is the rest of the line, not a fixed column, so a space in it
    /// survives.
    func test_keepsAPathThatContainsSpaces() {
        let line = "1 .M N... 100644 100644 100644 x y My Notes/read me.md"
        let status = GitStatusParser.parse(status: line, numstat: "")
        XCTAssertEqual(status.files.first?.path, "My Notes/read me.md")
    }

    /// Binary files come back as `-` and have no count to show.
    func test_aBinaryFileHasNoLineCounts() {
        let status = GitStatusParser.parse(
            status: "1 .M N... 0 0 0 x y icon.png",
            numstat: "-\t-\ticon.png"
        )
        XCTAssertNil(status.files.first?.addedLines)
        XCTAssertEqual(status.addedLines, 0)
    }

    /// Alphabetical, so the list does not reshuffle between reads.
    func test_filesComeBackInPathOrder() {
        let status = GitStatusParser.parse(
            status: "? zebra.swift\n? alpha.swift\n1 .M N... 0 0 0 x y middle.swift",
            numstat: ""
        )
        XCTAssertEqual(status.files.map(\.path), ["alpha.swift", "middle.swift", "zebra.swift"])
    }

    func test_noUpstreamIsNotAFailure() {
        let status = GitStatusParser.parse(status: "# branch.head feature/x", numstat: "")
        XCTAssertEqual(status.branch, "feature/x")
        XCTAssertNil(status.upstream)
        XCTAssertEqual(status.ahead, 0)
    }

    /// git answers in paths relative to the repository root. A workspace one
    /// directory down deals in its own paths, so the two have to be made to
    /// agree -- otherwise opening a changed file looks in the wrong place and
    /// the file tree matches none of them.
    func test_reroot_makesPathsRelativeToTheWorkspace() {
        let status = GitStatus(
            branch: "main",
            upstream: nil,
            ahead: 0,
            behind: 0,
            files: [
                GitFileChange(indexStatus: ".", worktreeStatus: "M", path: "app/Sources/a.swift", addedLines: 2, deletedLines: 1),
                GitFileChange(indexStatus: ".", worktreeStatus: "M", path: "docs/readme.md", addedLines: nil, deletedLines: nil),
            ]
        )

        let rerooted = GitStatusReader.reroot(status, under: "app/")

        XCTAssertEqual(rerooted.files.map(\.path), ["Sources/a.swift"], "and what is outside the workspace is dropped")
        XCTAssertEqual(rerooted.files.first?.addedLines, 2, "the counts come with it")
        XCTAssertEqual(rerooted.branch, "main")
    }
}
