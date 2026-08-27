//
//  ChangedLinesTests.swift
//  Puck
//
//  Where the agent just wrote, so the editor can scroll there. Not a diff --
//  it only has to point.
//

import XCTest
@testable import Puck

final class ChangedLinesTests: XCTestCase {
    private func lines(_ old: String, _ new: String) -> ClosedRange<Int>? {
        EditorPaneStore.changedLines(from: old, to: new)
    }

    func test_identicalRevisionsChangedNothing() {
        XCTAssertNil(lines("a\nb\nc", "a\nb\nc"))
        XCTAssertNil(lines("", ""))
    }

    /// The common case: a method appended inside a type, which is what a
    /// "add a reset() method" turn produces.
    func test_findsAnInsertionInTheMiddle() {
        let before = """
        struct Counter {
            func increment() {}
        }
        """
        let after = """
        struct Counter {
            func increment() {}

            func reset() {}
        }
        """
        XCTAssertEqual(lines(before, after), 3...4)
    }

    func test_findsAOneLineEdit() {
        XCTAssertEqual(lines("a\nb\nc", "a\nB\nc"), 2...2)
    }

    func test_findsAnAppendAtTheEnd() {
        XCTAssertEqual(lines("a\nb", "a\nb\nc"), 3...3)
    }

    func test_findsAnInsertAtTheTop() {
        XCTAssertEqual(lines("b\nc", "a\nb\nc"), 1...1)
    }

    /// Nothing new to point at, so it points at the seam the removal left --
    /// and never past the end of the file that remains.
    func test_aDeletionPointsAtWhereItHappened() {
        let range = lines("a\nb\nc", "a\nc")
        XCTAssertEqual(range, 2...2)

        let everything = lines("a\nb\nc", "")
        XCTAssertNotNil(everything)
        XCTAssertEqual(everything?.lowerBound, 1)
        XCTAssertLessThanOrEqual(everything?.upperBound ?? 0, 1)
    }

    /// A rewrite reports the whole file, which is the truth rather than a
    /// failure to be precise.
    func test_aFullRewriteReportsTheWholeFile() {
        XCTAssertEqual(lines("a\nb\nc", "x\ny\nz"), 1...3)
    }

    /// The range indexes the *new* revision, since that is what the editor is
    /// showing by the time it scrolls.
    func test_theRangeNeverPointsPastTheNewFile() {
        for (old, new) in [("a\nb\nc\nd", "a"), ("a", "a\nb\nc\nd"), ("", "x"), ("x", "")] {
            guard let range = lines(old, new) else { continue }
            let count = new.components(separatedBy: "\n").count
            XCTAssertGreaterThanOrEqual(range.lowerBound, 1, "\(old) -> \(new)")
            XCTAssertLessThanOrEqual(range.upperBound, count, "\(old) -> \(new)")
        }
    }
}
