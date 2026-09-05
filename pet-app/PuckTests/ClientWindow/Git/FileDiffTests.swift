//
//  FileDiffTests.swift
//  PuckTests
//
//  Reading `git diff`, including the corners of a unified diff that are easy
//  to be wrong about and impossible to notice: a context line that is empty,
//  a file with no trailing newline, a rename with no edits.
//

import XCTest
@testable import Puck

final class FileDiffTests: XCTestCase {
    func test_oneFileWithOneHunk() {
        let output = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        index 1234567..89abcde 100644
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -10,7 +10,8 @@ struct App {
             let a = 1
        -    let b = 2
        +    let b = 3
        +    let c = 4
             let d = 5
        """

        let files = DiffParser.parse(output)

        XCTAssertEqual(files.count, 1)
        let file = try? XCTUnwrap(files.first)
        XCTAssertEqual(file?.path, "Sources/App.swift")
        XCTAssertEqual(file?.addedCount, 2)
        XCTAssertEqual(file?.removedCount, 1)
        XCTAssertEqual(file?.hunks.count, 1)
        XCTAssertEqual(file?.hunks.first?.header, "@@ -10,7 +10,8 @@ struct App {")
    }

    /// The line numbers are what lets somebody find the change in the file.
    func test_lineNumbersFollowBothSidesOfTheHunk() {
        let output = """
        diff --git a/a.txt b/a.txt
        --- a/a.txt
        +++ b/a.txt
        @@ -10,3 +20,4 @@
         keep
        -gone
        +new one
        +new two
         keep again
        """

        let lines = DiffParser.parse(output).first?.hunks.first?.lines ?? []

        XCTAssertEqual(lines.map(\.kind), [.context, .removed, .added, .added, .context])
        XCTAssertEqual(lines[0].oldLine, 10)
        XCTAssertEqual(lines[0].newLine, 20)
        XCTAssertEqual(lines[1].oldLine, 11, "a removed line has a place in the old file only")
        XCTAssertNil(lines[1].newLine)
        XCTAssertNil(lines[2].oldLine, "an added line has a place in the new file only")
        XCTAssertEqual(lines[2].newLine, 21)
        XCTAssertEqual(lines[4].oldLine, 12)
        XCTAssertEqual(lines[4].newLine, 23)
    }

    /// git writes a blank context line as an empty line, not as a single
    /// space. Reading it as "not part of the hunk" drops real lines and
    /// throws off every number after it.
    func test_anEmptyContextLineIsStillALine() {
        let output = """
        diff --git a/a.txt b/a.txt
        --- a/a.txt
        +++ b/a.txt
        @@ -1,3 +1,3 @@
         first

        -third
        +third changed
        """

        let lines = DiffParser.parse(output).first?.hunks.first?.lines ?? []

        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[1].kind, .context)
        XCTAssertEqual(lines[1].text, "")
        XCTAssertEqual(lines[2].oldLine, 3, "the blank line has to count toward the numbering")
    }

    /// "\\ No newline at end of file" is a note about the line above it, not
    /// a line of the file.
    func test_theNoNewlineMarkerIsNotALine() {
        let output = """
        diff --git a/a.txt b/a.txt
        --- a/a.txt
        +++ b/a.txt
        @@ -1 +1 @@
        -old
        \\ No newline at end of file
        +new
        \\ No newline at end of file
        """

        let lines = DiffParser.parse(output).first?.hunks.first?.lines ?? []

        XCTAssertEqual(lines.map(\.kind), [.removed, .added])
    }

    func test_severalFilesAndSeveralHunks() {
        let output = """
        diff --git a/a.txt b/a.txt
        --- a/a.txt
        +++ b/a.txt
        @@ -1 +1 @@
        -a
        +A
        @@ -10 +10 @@
        -b
        +B
        diff --git a/b.txt b/b.txt
        --- a/b.txt
        +++ b/b.txt
        @@ -1 +1 @@
        -c
        +C
        """

        let files = DiffParser.parse(output)

        XCTAssertEqual(files.map(\.path), ["a.txt", "b.txt"])
        XCTAssertEqual(files.first?.hunks.count, 2)
        XCTAssertEqual(files.first?.addedCount, 2)
    }

    /// A rename is the b-side path, with where it came from kept.
    func test_aRenameKeepsWhereItCameFrom() {
        let output = """
        diff --git a/old/name.swift b/new/name.swift
        similarity index 100%
        rename from old/name.swift
        rename to new/name.swift
        """

        let file = DiffParser.parse(output).first

        XCTAssertEqual(file?.path, "new/name.swift")
        XCTAssertEqual(file?.previousPath, "old/name.swift")
        XCTAssertTrue(file?.isRename ?? false)
        XCTAssertTrue(file?.hasNoVisibleChange ?? false, "a pure rename has nothing to draw")
    }

    /// A binary file is reported as changed with nothing to show, which is
    /// different from a file that did not change.
    func test_aBinaryFileIsMarkedRatherThanEmpty() {
        let output = """
        diff --git a/icon.png b/icon.png
        index 111..222 100644
        Binary files a/icon.png and b/icon.png differ
        """

        let file = DiffParser.parse(output).first

        XCTAssertEqual(file?.path, "icon.png")
        XCTAssertTrue(file?.isBinary ?? false)
        XCTAssertTrue(file?.hasNoVisibleChange ?? false)
    }

    /// A path with a space in it, which is why the header is split on " b/"
    /// rather than on whitespace.
    func test_aPathWithASpaceInIt() {
        let header = "diff --git a/My Folder/a file.txt b/My Folder/a file.txt"

        XCTAssertEqual(DiffParser.path(fromDiffHeader: header), "My Folder/a file.txt")
    }

    /// A one-line hunk header has no comma: `@@ -1 +1 @@`.
    func test_aHunkHeaderWithoutCounts() {
        XCTAssertEqual(DiffParser.lineNumbers(fromHunkHeader: "@@ -1 +1 @@").old, 1)
        XCTAssertEqual(DiffParser.lineNumbers(fromHunkHeader: "@@ -42,7 +58,9 @@ func x()").new, 58)
        XCTAssertEqual(DiffParser.lineNumbers(fromHunkHeader: "@@ -42,7 +58,9 @@ func x()").old, 42)
    }

    /// Nothing changed is an empty list, not a file with no hunks.
    func test_emptyOutputIsNoFiles() {
        XCTAssertTrue(DiffParser.parse("").isEmpty)
        XCTAssertTrue(DiffParser.parse("\n\n").isEmpty)
    }
}
