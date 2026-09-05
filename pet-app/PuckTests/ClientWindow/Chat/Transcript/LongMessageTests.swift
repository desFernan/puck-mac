//
//  LongMessageTests.swift
//  PuckTests
//
//  When a sent message is folded, and what is left showing.
//
//  A pasted log used to be drawn whole, in a tinted bubble, and one of them
//  pushed the conversation it belonged to off the top of the window.
//

import XCTest
@testable import Puck

final class LongMessageTests: XCTestCase {
    /// An ordinary message is not touched at all.
    func test_anOrdinaryMessageIsLeftAlone() {
        let text = "run.sh 만들어줘"

        XCTAssertFalse(LongMessage.isLong(text))
        XCTAssertEqual(LongMessage.preview(of: text), text)
    }

    /// Tall: a stack trace or a log, many short lines.
    func test_aMessageWithTooManyLinesIsFolded() {
        let text = (0..<40).map { "line \($0)" }.joined(separator: "\n")

        XCTAssertTrue(LongMessage.isLong(text))
        XCTAssertEqual(LongMessage.lineCount(LongMessage.preview(of: text)), LongMessage.previewLines)
    }

    /// And wide: one paragraph with a single newline in it wraps to the same
    /// wall of text, so a line count alone would let it through.
    func test_aMessageThatIsLongWithoutBeingTallIsFolded() {
        let text = String(repeating: "가", count: 4_000)

        XCTAssertTrue(LongMessage.isLong(text))
        XCTAssertLessThanOrEqual(LongMessage.preview(of: text).count, LongMessage.previewCharacters)
    }

    /// The preview stops at a line break when one is near, because a cut
    /// mid-line reads as damage rather than as a decision.
    func test_thePreviewStopsAtALineBreakWhenItCan() {
        let text = (0..<60).map { "\($0): 어떤 로그 줄입니다" }.joined(separator: "\n")

        let preview = LongMessage.preview(of: text)

        XCTAssertFalse(preview.hasSuffix("\n"))
        XCTAssertTrue(text.hasPrefix(preview), "the preview has to be the message's own opening")
    }

    /// A first line longer than the whole budget has no break to go back to,
    /// and cutting to nothing would be worse than cutting mid-word.
    func test_aSingleUnbrokenLineStillProducesAPreview() {
        let text = String(repeating: "x", count: 5_000)

        let preview = LongMessage.preview(of: text)

        XCTAssertFalse(preview.isEmpty)
        XCTAssertLessThanOrEqual(preview.count, LongMessage.previewCharacters)
    }

    /// What was folded away is described the way someone recognises the thing
    /// they pasted: lines and a size.
    func test_theSummaryNamesLinesAndSize() {
        let text = (0..<40).map { _ in String(repeating: "a", count: 100) }.joined(separator: "\n")

        let summary = LongMessage.summary(of: text)

        XCTAssertTrue(summary.contains("40"), summary)
        XCTAssertTrue(summary.contains("KB"), summary)
    }

    /// A trailing newline is not an extra line -- it is how a file ends.
    func test_lineCountCountsTheWayAPersonDoes() {
        XCTAssertEqual(LongMessage.lineCount(""), 0)
        XCTAssertEqual(LongMessage.lineCount("한 줄"), 1)
        XCTAssertEqual(LongMessage.lineCount("한 줄\n"), 1)
        XCTAssertEqual(LongMessage.lineCount("한 줄\n두 줄"), 2)
        XCTAssertEqual(LongMessage.lineCount("한 줄\n\n세 줄"), 3)
    }

    /// The written-out file is named by the clock, because these land in a
    /// folder somebody opens and a list of timestamps is one they can read.
    func test_theFileIsNamedByTheClock() {
        let name = LongMessage.fileName(now: Date(timeIntervalSince1970: 0))

        XCTAssertTrue(name.hasPrefix("message-"), name)
        XCTAssertTrue(name.hasSuffix(".txt"), name)
        XCTAssertNotEqual(name, LongMessage.fileName(now: Date(timeIntervalSince1970: 86_400)))
    }
}
