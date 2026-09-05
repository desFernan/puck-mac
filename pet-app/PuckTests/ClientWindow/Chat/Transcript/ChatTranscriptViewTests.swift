//
//  ChatTranscriptViewTests.swift
//  Puck
//
//  The transcript's own decisions, tested where they are made rather than
//  through SwiftUI: what a failed tool call says while it is still collapsed.
//

import XCTest
@testable import Puck

final class ChatTranscriptViewTests: XCTestCase {
    /// A failed code_editor showed a red triangle next to the word
    /// "code_editor" and nothing else -- the reason lived inside a disclosure
    /// group that starts closed, so the tool read as having failed silently.
    func test_aFailedCall_showsItsReasonWithoutBeingExpanded() {
        let line = toolFailureLine(
            ok: false,
            error: .executionFailed,
            detail: "claude CLI를 찾을 수 없습니다. 설치한 뒤 다시 시도해 주세요.\nvendorCLINotFound(Puck.CodingAgentKind.claude)"
        )

        XCTAssertEqual(line, "claude CLI를 찾을 수 없습니다. 설치한 뒤 다시 시도해 주세요.")
    }

    func test_aFailedCallWithNoDetail_fallsBackToItsErrorCode() {
        XCTAssertEqual(toolFailureLine(ok: false, error: .timeout, detail: nil), "timeout")
        XCTAssertEqual(toolFailureLine(ok: false, error: .executionFailed, detail: ""), "execution_failed")
    }

    func test_aFailedCallWithNothingAtAll_stillSaysSomething() {
        XCTAssertEqual(toolFailureLine(ok: false, error: nil, detail: nil), Strings.text(.chatFailed))
    }

    func test_aSucceededOrPendingCall_showsNoFailureLine() {
        XCTAssertNil(toolFailureLine(ok: true, error: nil, detail: "wrote 3 files"))
        XCTAssertNil(toolFailureLine(ok: nil, error: nil, detail: nil))
    }

    // MARK: - What a collapsed row says it was called with

    /// A tool call is a line now, not a card, and a line is only enough if it
    /// says which call it was: three `read_file` rows are otherwise three
    /// identical rows.
    func test_theSummaryIsTheArgumentWorthReading() {
        let summary = toolArgumentSummary(.object([
            "cwd": .string("/tmp"),
            "command": .string("swift build"),
        ]))

        XCTAssertEqual(summary, "swift build")
    }

    /// Named keys in a fixed order, because a JSON object's key order is not
    /// one: picking "the first string" would put `cwd` on one row and
    /// `command` on the next row of the same tool.
    func test_theSameToolAlwaysSummarisesTheSameField() {
        let fields: [String: JSONValue] = [
            "path": .string("Sources/App.swift"),
            "encoding": .string("utf8"),
        ]

        for _ in 0..<20 {
            XCTAssertEqual(toolArgumentSummary(.object(fields)), "Sources/App.swift")
        }
    }

    /// Nothing recognised still has to be stable across calls, so the fallback
    /// is ordered too.
    func test_anUnrecognisedCallFallsBackToAStableField() {
        let summary = toolArgumentSummary(.object([
            "zebra": .string("last"),
            "alpha": .string("first"),
        ]))

        XCTAssertEqual(summary, "first")
    }

    /// A row is a line: a heredoc'd shell command has to be flattened and cut
    /// rather than made into a paragraph.
    func test_aLongMultiLineArgumentIsFlattenedAndCut() {
        let summary = toolArgumentSummary(
            .object(["command": .string("echo one\n  echo two\n  echo three")]),
            limit: 12
        )

        XCTAssertEqual(summary, "echo one ech…")
    }

    /// Nothing to say is said with nothing, not with an empty line.
    func test_aCallWithNothingToSummarise() {
        XCTAssertNil(toolArgumentSummary(nil))
        XCTAssertNil(toolArgumentSummary(.object([:])))
        XCTAssertNil(toolArgumentSummary(.object(["count": .number(3)])))
        XCTAssertNil(toolArgumentSummary(.object(["command": .string("   ")])))
    }
}
