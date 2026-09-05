//
//  TerminalOutputBufferTests.swift
//  PuckTests
//
//  What a long-running command has said, and how much of it the agent has
//  already been told.
//

import XCTest
@testable import Puck

final class TerminalOutputBufferTests: XCTestCase {
    private func data(_ text: String) -> Data { Data(text.utf8) }

    /// The point of the cursor: a second read hands back what is new, not the
    /// log again. Without it a model watching a build re-reads the same ten
    /// thousand lines every turn.
    func test_aReadTakesOnlyWhatIsNew() {
        var buffer = TerminalOutputBuffer()
        buffer.append(data("첫 줄\n"))

        XCTAssertEqual(buffer.read().text, "첫 줄\n")
        XCTAssertTrue(buffer.read().isEmpty, "nothing has been said since")

        buffer.append(data("둘째 줄\n"))
        XCTAssertEqual(buffer.read().text, "둘째 줄\n")
    }

    /// Nothing new is a normal answer, not a failure: a server that is up and
    /// quiet is a server that is working.
    func test_nothingNewIsAnEmptyRead() {
        var buffer = TerminalOutputBuffer()

        let read = buffer.read()

        XCTAssertEqual(read.text, "")
        XCTAssertEqual(read.droppedBytes, 0)
        XCTAssertTrue(read.isEmpty)
    }

    /// A dev server left running for a day is unbounded, so the oldest goes.
    func test_theOldestIsDroppedPastTheLimit() {
        var buffer = TerminalOutputBuffer(limit: 100)

        buffer.append(data(String(repeating: "a", count: 80)))
        buffer.append(data(String(repeating: "b", count: 80)))

        XCTAssertEqual(buffer.all.count, 100)
        XCTAssertTrue(buffer.all.hasSuffix(String(repeating: "b", count: 80)))
    }

    /// And a read that arrives after a drop is told, because a log with a
    /// hole in it that does not say so is worse than one that does.
    func test_aReadAfterADropSaysHowMuchItMissed() {
        var buffer = TerminalOutputBuffer(limit: 100)
        buffer.append(data(String(repeating: "a", count: 80)))
        buffer.append(data(String(repeating: "b", count: 80)))

        let read = buffer.read()

        XCTAssertEqual(read.droppedBytes, 60, "80 + 80 over a 100 limit loses the first 60")
        XCTAssertEqual(read.text.count, 100)
        XCTAssertFalse(read.isEmpty)
    }

    /// A build that produced a megabyte while nobody was looking must not
    /// arrive as one message -- the far end of this is a model's context.
    func test_oneReadIsCappedAndTheRestWaits() {
        var buffer = TerminalOutputBuffer()
        buffer.append(data(String(repeating: "x", count: 5_000)))

        let first = buffer.read(maximumBytes: 1_000)
        XCTAssertEqual(first.text.count, 1_000)

        let second = buffer.read(maximumBytes: 1_000)
        XCTAssertEqual(second.text.count, 1_000, "the rest is still there to read")
    }

    /// A cut lands anywhere, including inside a character. The broken half
    /// becomes a replacement rather than losing the line it was in.
    func test_aCutInsideACharacterDoesNotLoseTheLine() {
        var buffer = TerminalOutputBuffer()
        buffer.append(data("가나다라마바사"))

        // 한 글자가 3바이트라, 4는 반드시 글자 가운데를 자른다.
        let read = buffer.read(maximumBytes: 4)

        XCTAssertFalse(read.text.isEmpty)
        XCTAssertTrue(read.text.hasPrefix("가"))
    }

    /// For a caller that wants the session from the beginning rather than
    /// what is new.
    func test_rewindingHandsTheWholeThingBack() {
        var buffer = TerminalOutputBuffer()
        buffer.append(data("전부"))
        _ = buffer.read()

        buffer.rewind()

        XCTAssertEqual(buffer.read().text, "전부")
    }

    /// Appending nothing is not an event -- a readability handler fires with
    /// an empty slice at end of file.
    func test_anEmptyAppendChangesNothing() {
        var buffer = TerminalOutputBuffer()
        buffer.append(Data())

        XCTAssertTrue(buffer.isEmpty)
        XCTAssertTrue(buffer.read().isEmpty)
    }
}
