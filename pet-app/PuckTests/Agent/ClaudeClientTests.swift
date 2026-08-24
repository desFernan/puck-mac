//
//  ClaudeClientTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Encode/decode as pure functions against fixture data -- no network -- plus
//  one network-level test for the "surface the body on a non-2xx" behavior,
//  since that's the one property that only exists once `send` runs.
//

import XCTest
@testable import Puck

final class ClaudeClientTests: XCTestCase {

    // MARK: - system hoisting

    func test_systemMessage_isHoistedOutOfMessagesArray() {
        let messages: [GPTMessage] = [
            .system("You are a helpful pet."),
            .user("hi"),
        ]

        XCTAssertEqual(ClaudeClient.system(from: messages), "You are a helpful pet.")

        let encoded = ClaudeClient.encodeMessages(messages)
        XCTAssertEqual(encoded.count, 1, "the system entry must not become a messages[] entry")
        XCTAssertEqual(encoded.first?["role"] as? String, "user")
    }

    func test_noSystemMessage_hoistsToNil() {
        XCTAssertNil(ClaudeClient.system(from: [.user("hi")]))
    }

    func test_multipleSystemMessages_areJoined() {
        let system = ClaudeClient.system(from: [.system("first"), .user("hi"), .system("second")])
        XCTAssertEqual(system, "first\n\nsecond")
    }

    // MARK: - assistant decode: text + tool_use

    func test_decodeTurn_withTextAndToolUseBlocks_populatesBoth() throws {
        let json = """
        {
          "content": [
            {"type": "text", "text": "Let me check the weather."},
            {"type": "tool_use", "id": "toolu_abc123", "name": "get_weather", "input": {"location": "Seoul"}}
          ]
        }
        """
        let turn = try ClaudeClient.decodeTurn(from: Data(json.utf8))

        XCTAssertEqual(turn.text, "Let me check the weather.")
        XCTAssertEqual(turn.toolCalls.count, 1)
        XCTAssertEqual(turn.toolCalls.first?.id, "toolu_abc123")
        XCTAssertEqual(turn.toolCalls.first?.name, "get_weather")

        // argumentsJSON is raw text the caller parses -- round-trip it rather
        // than string-comparing, since key order in JSONSerialization output
        // isn't guaranteed.
        let arguments = try XCTUnwrap(turn.toolCalls.first?.argumentsJSON)
        let parsed = try JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any]
        XCTAssertEqual(parsed?["location"] as? String, "Seoul")
    }

    func test_decodeTurn_textOnly_hasNoToolCalls() throws {
        let json = """
        {"content": [{"type": "text", "text": "hello"}]}
        """
        let turn = try ClaudeClient.decodeTurn(from: Data(json.utf8))

        XCTAssertEqual(turn.text, "hello")
        XCTAssertTrue(turn.toolCalls.isEmpty)
    }

    func test_decodeTurn_toolUseWithNoInput_decodesAsEmptyObject() throws {
        let json = """
        {"content": [{"type": "tool_use", "id": "toolu_1", "name": "no_args_tool"}]}
        """
        let turn = try ClaudeClient.decodeTurn(from: Data(json.utf8))

        XCTAssertNil(turn.text)
        XCTAssertEqual(turn.toolCalls.first?.argumentsJSON, "{}")
    }

    func test_decodeTurn_missingContentArray_throwsMalformedResponse() {
        let json = "{\"not_content\": []}"

        XCTAssertThrowsError(try ClaudeClient.decodeTurn(from: Data(json.utf8))) { error in
            guard case GPTError.malformedResponse = error else {
                return XCTFail("expected .malformedResponse, got \(error)")
            }
        }
    }

    // MARK: - tool result encoding

    func test_toolResult_encodesAsUserMessageWithToolResultBlock() throws {
        let encoded = ClaudeClient.encodeMessages([.tool(callId: "toolu_abc123", content: "72°F and sunny")])

        XCTAssertEqual(encoded.count, 1)
        let message = try XCTUnwrap(encoded.first)
        XCTAssertEqual(message["role"] as? String, "user")

        let blocks = try XCTUnwrap(message["content"] as? [[String: Any]])
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?["type"] as? String, "tool_result")
        XCTAssertEqual(blocks.first?["tool_use_id"] as? String, "toolu_abc123")
        XCTAssertEqual(blocks.first?["content"] as? String, "72°F and sunny")
    }

    /// Parallel tool calls produce one `.tool` per call, and this API wants
    /// every tool_result answering one assistant turn in a SINGLE user
    /// message. Splitting them doesn't 400 -- it quietly makes the model stop
    /// fanning out on later turns, which no error would ever reveal.
    func test_consecutiveToolResults_mergeIntoOneUserMessage() throws {
        let encoded = ClaudeClient.encodeMessages([
            .tool(callId: "toolu_a", content: "first"),
            .tool(callId: "toolu_b", content: "second"),
            .tool(callId: "toolu_c", content: "third"),
        ])

        XCTAssertEqual(encoded.count, 1, "three parallel results must not become three messages")
        let blocks = try XCTUnwrap(encoded.first?["content"] as? [[String: Any]])
        XCTAssertEqual(blocks.map { $0["tool_use_id"] as? String }, ["toolu_a", "toolu_b", "toolu_c"])
    }

    func test_toolResultsSeparatedByOtherMessages_staySeparate() throws {
        let encoded = ClaudeClient.encodeMessages([
            .tool(callId: "toolu_a", content: "first"),
            .assistant(text: "이어서 확인할게요", toolCalls: [], reasoning: nil),
            .tool(callId: "toolu_b", content: "second"),
        ])

        XCTAssertEqual(encoded.map { $0["role"] as? String }, ["user", "assistant", "user"])
    }

    // MARK: - stop_reason

    /// Both of these come back as HTTP 200 with empty/partial content, so
    /// without the check they decode to an empty turn and AgentRunner ends
    /// the run ok=true having shown the user nothing.
    func test_decodeTurn_onRefusal_throwsRatherThanReturningAnEmptyTurn() {
        let json = Data(#"{"stop_reason":"refusal","content":[]}"#.utf8)
        XCTAssertThrowsError(try ClaudeClient.decodeTurn(from: json))
    }

    func test_decodeTurn_onMaxTokensTruncation_throws() {
        let json = Data(#"{"stop_reason":"max_tokens","content":[{"type":"text","text":"부분 응"}]}"#.utf8)
        XCTAssertThrowsError(try ClaudeClient.decodeTurn(from: json))
    }

    func test_decodeTurn_onNormalStopReason_decodesNormally() throws {
        let json = Data(#"{"stop_reason":"end_turn","content":[{"type":"text","text":"완료"}]}"#.utf8)
        let turn = try ClaudeClient.decodeTurn(from: json)
        XCTAssertEqual(turn.text, "완료")
    }

    // MARK: - assistant encoding: text + tool_use blocks

    func test_assistantTurn_withTextAndToolCall_encodesBothBlockTypes() throws {
        let call = GPTToolCall(id: "toolu_1", name: "open_task_session", argumentsJSON: "{\"task\":\"fix bug\"}")
        let encoded = ClaudeClient.encodeMessages([.assistant(text: "On it.", toolCalls: [call], reasoning: nil)])

        let message = try XCTUnwrap(encoded.first)
        let blocks = try XCTUnwrap(message["content"] as? [[String: Any]])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["type"] as? String, "text")
        XCTAssertEqual(blocks[0]["text"] as? String, "On it.")
        XCTAssertEqual(blocks[1]["type"] as? String, "tool_use")
        XCTAssertEqual(blocks[1]["id"] as? String, "toolu_1")
        XCTAssertEqual(blocks[1]["name"] as? String, "open_task_session")
        let input = try XCTUnwrap(blocks[1]["input"] as? [String: Any])
        XCTAssertEqual(input["task"] as? String, "fix bug")
    }

    // MARK: - request body

    /// The three properties of the body that are invisible at every other
    /// layer and silently wrong if they regress: no `thinking` field (no value
    /// is valid across every model Settings accepts), a `system` block that
    /// carries the cache breakpoint, and `max_tokens` present at all.
    func test_requestBody_omitsThinking_andCachesTheSystemPrompt() throws {
        let body = ClaudeClient.requestBody(
            model: "claude-sonnet-5",
            messages: [.system("You are a pet."), .user("안녕")],
            tools: []
        )

        XCTAssertNil(body["thinking"], "no thinking value is valid on every model this app accepts")
        XCTAssertEqual(body["model"] as? String, "claude-sonnet-5")
        XCTAssertNotNil(body["max_tokens"], "the Messages API requires max_tokens on every request")

        let system = try XCTUnwrap(body["system"] as? [[String: Any]])
        XCTAssertEqual(system.count, 1)
        XCTAssertEqual(system[0]["text"] as? String, "You are a pet.")
        let cacheControl = try XCTUnwrap(system[0]["cache_control"] as? [String: Any])
        XCTAssertEqual(cacheControl["type"] as? String, "ephemeral")
    }

    func test_requestBody_withoutSystemMessage_omitsSystemEntirely() {
        let body = ClaudeClient.requestBody(model: "claude-sonnet-5", messages: [.user("안녕")], tools: [])

        XCTAssertNil(body["system"], "an empty system block is not the same as no system field")
    }

    // MARK: - thinking blocks round-trip

    /// The whole reason `GPTTurn.reasoning` exists: a turn that thought before
    /// calling a tool is rejected on the next request unless its thinking
    /// blocks come back unchanged, signature included.
    func test_thinkingBlocks_surviveDecodeThenEncode() throws {
        let json = Data("""
        {"stop_reason":"tool_use","content":[
          {"type":"thinking","thinking":"","signature":"sig_abc"},
          {"type":"text","text":"확인할게요"},
          {"type":"tool_use","id":"toolu_1","name":"list_files","input":{}}
        ]}
        """.utf8)

        let turn = try ClaudeClient.decodeTurn(from: json)
        XCTAssertNotNil(turn.reasoning)

        let encoded = ClaudeClient.encodeMessages([
            .assistant(text: turn.text, toolCalls: turn.toolCalls, reasoning: turn.reasoning),
        ])
        let blocks = try XCTUnwrap(encoded.first?["content"] as? [[String: Any]])

        XCTAssertEqual(blocks.map { $0["type"] as? String }, ["thinking", "text", "tool_use"],
                       "thinking has to lead the turn, ahead of narration and calls")
        XCTAssertEqual(blocks[0]["signature"] as? String, "sig_abc")
    }

    func test_turnWithoutThinking_encodesNoThinkingBlock() throws {
        let json = Data(#"{"content":[{"type":"text","text":"안녕하세요"}]}"#.utf8)

        let turn = try ClaudeClient.decodeTurn(from: json)
        XCTAssertNil(turn.reasoning)

        let encoded = ClaudeClient.encodeMessages([
            .assistant(text: turn.text, toolCalls: [], reasoning: turn.reasoning),
        ])
        let blocks = try XCTUnwrap(encoded.first?["content"] as? [[String: Any]])
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0]["type"] as? String, "text")
    }

    // MARK: - non-2xx surfaces the response body

    func test_send_onNonSuccessStatus_throwsWithResponseBody() async throws {
        let config = AgentConfiguration(
            apiKey: "test-key",
            model: "claude-sonnet-5",
            provider: .anthropic,
            keySource: nil
        )

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)

        let errorBody = "{\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"bad model\"}}"
        StubURLProtocol.stub(status: 400, body: errorBody)

        let client = ClaudeClient(configuration: { config }, session: session)

        do {
            _ = try await client.send(messages: [.user("hi")], tools: [])
            XCTFail("expected GPTError.http to be thrown")
        } catch GPTError.http(let status, let body) {
            XCTAssertEqual(status, 400)
            // The whole point: the debuggable reason lives in the body, not
            // just the status code.
            XCTAssertEqual(body, errorBody)
        }
    }
}

/// A minimal stub that returns a fixed status/body for every request,
/// scoped to this test file -- there's no shared network-mocking
/// infrastructure elsewhere in the test target yet.
private final class StubURLProtocol: URLProtocol {
    private static var status = 200
    private static var body = ""

    static func stub(status: Int, body: String) {
        self.status = status
        self.body = body
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
