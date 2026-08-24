//
//  JSONLinesDecoderTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Incremental JSON Lines parsing over an arbitrarily-chunked byte stream,
//  per protocol/01_protocol.md section 2 ("인코딩: JSON Lines"). Also covers
//  code-review findings on commit 57615a8: unbounded buffer growth and
//  unobservable malformed-line drops (#5).
//

import XCTest
@testable import Puck

final class JSONLinesDecoderTests: XCTestCase {
    private func line(_ json: String) -> Data {
        Data((json + "\n").utf8)
    }

    func test_feedsOneCompleteLine_returnsOneMessage() {
        var decoder = JSONLinesDecoder()
        let result = decoder.feed(line(#"{"type":"event","event":"agent_thinking","workspace_id":"default","session_id":"default"}"#))

        XCTAssertEqual(result.messages, [.event(.agentThinking, workspaceId: "default", sessionId: "default")])
        XCTAssertFalse(result.didOverflow)
    }

    func test_feedsPartialLine_returnsNothingUntilNewlineArrives() {
        var decoder = JSONLinesDecoder()
        let partial = Data(#"{"type":"event","event":"agent_thinking","workspace_id":"default","session_id":"default""#.utf8) // no closing brace, no newline

        XCTAssertEqual(decoder.feed(partial).messages, [])
        XCTAssertEqual(decoder.feed(Data("}\n".utf8)).messages, [.event(.agentThinking, workspaceId: "default", sessionId: "default")])
    }

    func test_feedsMultipleLinesAtOnce_returnsAllMessages() {
        var decoder = JSONLinesDecoder()
        let chunk = line(#"{"type":"event","event":"agent_thinking","workspace_id":"default","session_id":"default"}"#)
            + line(#"{"type":"event","event":"tool_result","id":"t1","ok":true,"workspace_id":"default","session_id":"default"}"#)

        XCTAssertEqual(decoder.feed(chunk).messages, [.event(.agentThinking, workspaceId: "default", sessionId: "default"), .event(.toolResult(id: "t1", ok: true, data: nil, error: nil, detail: nil), workspaceId: "default", sessionId: "default")])
    }

    func test_malformedLine_isSkipped_subsequentLinesStillParse() {
        var decoder = JSONLinesDecoder()
        let chunk = line("not json") + line(#"{"type":"event","event":"agent_thinking","workspace_id":"default","session_id":"default"}"#)

        XCTAssertEqual(decoder.feed(chunk).messages, [.event(.agentThinking, workspaceId: "default", sessionId: "default")])
    }

    func test_malformedLine_incrementsDroppedLineCount() {
        var decoder = JSONLinesDecoder()
        _ = decoder.feed(line("not json") + line("also not json"))

        XCTAssertEqual(decoder.droppedLineCount, 2)
    }

    // droppedLineCount was only ever read by these tests -- nothing in
    // BridgeConnection/BridgeServer surfaced a drop happening live, so
    // protocol drift or a hostile connection produced zero operational
    // signal (found via review). FeedResult.droppedThisCall is what
    // BridgeConnection wires into a per-connection callback.
    func test_malformedLine_reportsHowManyWereDroppedInThisCall() {
        var decoder = JSONLinesDecoder()
        let result = decoder.feed(line("not json") + line("also not json") + line(#"{"type":"event","event":"agent_thinking","workspace_id":"default","session_id":"default"}"#))

        XCTAssertEqual(result.droppedThisCall, 2)
    }

    func test_noMalformedLines_reportsZeroDroppedThisCall() {
        var decoder = JSONLinesDecoder()
        let result = decoder.feed(line(#"{"type":"event","event":"agent_thinking","workspace_id":"default","session_id":"default"}"#))

        XCTAssertEqual(result.droppedThisCall, 0)
    }

    func test_emptyLine_isSkipped() {
        var decoder = JSONLinesDecoder()
        XCTAssertEqual(decoder.feed(Data("\n".utf8)).messages, [])
    }

    // MARK: - #5: unbounded buffer growth

    func test_lineExceedingMaxLength_withoutNewline_reportsOverflowAndClearsBuffer() {
        var decoder = JSONLinesDecoder(maxLineLength: 16)
        let oversized = Data(repeating: UInt8(ascii: "a"), count: 32) // no newline, over the cap

        let result = decoder.feed(oversized)

        XCTAssertTrue(result.didOverflow)
        XCTAssertEqual(result.messages, [])

        // Buffer was cleared, so a fresh valid line after the overflow parses normally.
        let next = decoder.feed(line(#"{"type":"event","event":"agent_thinking","workspace_id":"default","session_id":"default"}"#))
        XCTAssertEqual(next.messages, [.event(.agentThinking, workspaceId: "default", sessionId: "default")])
        XCTAssertFalse(next.didOverflow)
    }

    func test_lineUnderMaxLength_doesNotOverflow() {
        var decoder = JSONLinesDecoder(maxLineLength: 1024)
        let result = decoder.feed(line(#"{"type":"event","event":"agent_thinking","workspace_id":"default","session_id":"default"}"#))

        XCTAssertFalse(result.didOverflow)
    }
}
