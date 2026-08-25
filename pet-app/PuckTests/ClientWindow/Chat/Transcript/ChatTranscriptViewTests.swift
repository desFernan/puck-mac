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
}
