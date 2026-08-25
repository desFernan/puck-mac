//
//  ClaudeClient.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  A thin Anthropic Messages API client with tool calling -- the second
//  `AgentLLMClient`, sitting next to GPTClient.swift.
//
//  No SDK, same reasoning as GPTClient.swift's header gives: a tool-use loop
//  needs three request fields and reads two response fields, and a
//  dependency for that is a dependency to keep updated. There is also no
//  official Anthropic Swift SDK to reach for.
//
//  The wire format is not Chat Completions with different field names -- four
//  differences that would silently misbehave if copy-pasted from GPTClient:
//
//   1. Auth is `x-api-key` + `anthropic-version`, not `Authorization: Bearer`.
//   2. `system` is a top-level request field, not a `role: "system"` message
//      -- GPTMessage.system is hoisted out of the array during encoding.
//   3. Tool use arrives as content blocks: an assistant reply's `content` is
//      an array mixing text and tool_use blocks. A tool result goes back
//      inside a *user* message as a tool_result block keyed by the
//      original id -- there is no `role: "tool"`.
//   4. `max_tokens` is required (Chat Completions does not require it).
//

import Foundation

final class ClaudeClient: AgentLLMClient {
    /// Read per request, not captured once -- same reasoning as GPTClient:
    /// a key typed into Settings has to take effect without quitting the app.
    private let configuration: () -> AgentConfiguration
    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// From `curl/examples.md`'s Required Headers table in the claude-api
    /// skill: `anthropic-version: 2023-06-01` is the one header every request
    /// needs, versioned independently of the model.
    private static let anthropicVersion = "2023-06-01"

    /// The Messages API requires `max_tokens` on every request (Chat
    /// Completions does not). AgentRunner's turns are short tool-call
    /// exchanges, not long-form generation, so a fixed mid-size cap is
    /// simpler than plumbing a per-call value through `AgentLLMClient` for a
    /// need that hasn't come up yet.
    ///
    /// This has to be read together with the missing `thinking` field below:
    /// `max_tokens` caps thinking *plus* visible output, and current models
    /// think by default, so a budget sized only for the answer gets spent on
    /// reasoning and the turn comes back truncated. 16000 is the skill's
    /// non-streaming default -- high enough to leave room for both, low enough
    /// to stay under URLSession's timeout without streaming.
    private static let maxTokens = 16000

    init(configuration: @escaping () -> AgentConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func send(messages: [GPTMessage], tools: [GPTToolSpec], sessionId: String?) async throws -> GPTTurn {
        let configuration = configuration()
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else { throw GPTError.notConfigured }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60

        request.httpBody = try JSONSerialization.data(
            withJSONObject: Self.requestBody(model: configuration.model, messages: messages, tools: tools)
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GPTError.malformedResponse("not an HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            // The body is where Anthropic puts the actual reason (bad key,
            // unknown model, rate limit) -- a bare status code sends whoever
            // is debugging this to the wrong place. Same reasoning as
            // GPTClient.
            throw GPTError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.decodeTurn(from: data)
    }

    // MARK: - Wire encoding

    /// Split out of `send` so the request shape can be asserted on without a
    /// network stub: everything `send` still does around it is auth, headers
    /// and error mapping, which need a real request.
    ///
    /// There is deliberately no `thinking` field. No single value is valid
    /// across the models someone can name in Settings: `{"type": "disabled"}`
    /// is a 400 on Fable/Mythos 5 (thinking is always on there), `"adaptive"`
    /// is a 400 on 4.5-era models, and `output_config.effort` errors on those
    /// too. Omitting it is accepted everywhere -- current models run adaptive
    /// thinking, older ones run none -- so the request stays valid whatever
    /// `model` holds. Disabling it used to be the choice here, on the grounds
    /// that a tool-dispatch loop is not a reasoning workload; that stopped
    /// being safe on Opus 5, where a thinking-disabled turn can write its tool
    /// call into the *visible text* instead of a tool_use block. No error, no
    /// call, and `decodeTurn` hands back a text-only turn that AgentRunner
    /// reports as a finished run -- silent, and exactly this loop's shape.
    /// The cost of letting thinking run is `reasoning` having to round-trip;
    /// see `encodeAssistantContent`.
    static func requestBody(model: String, messages: [GPTMessage], tools: [GPTToolSpec]) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": encodeMessages(messages),
            "tools": tools.map(encode),
        ]
        if let system = system(from: messages) {
            // A string would do, but the block form takes a `cache_control`
            // breakpoint and a string does not. The cached prefix is rendered
            // `tools` -> `system`, so this one breakpoint covers both -- and
            // both are resent verbatim on every turn of a tool loop, which is
            // the case caching exists for. Nothing volatile precedes it.
            body["system"] = [[
                "type": "text",
                "text": system,
                "cache_control": ["type": "ephemeral"],
            ]]
        }
        return body
    }

    /// `system` is a top-level request field on the Messages API, not a
    /// message with `role: "system"`. Concatenates every `.system` case
    /// found (in order) rather than requiring exactly one, since nothing
    /// upstream guarantees AgentRunner sends only one.
    static func system(from messages: [GPTMessage]) -> String? {
        let systemTexts = messages.compactMap { message -> String? in
            if case .system(let text) = message { return text }
            return nil
        }
        return systemTexts.isEmpty ? nil : systemTexts.joined(separator: "\n\n")
    }

    /// Everything except `.system` cases (hoisted separately into the
    /// top-level `system` field) becomes a `messages` entry.
    ///
    /// Consecutive `.tool` results are merged into ONE user message rather
    /// than one message each. When the model makes parallel tool calls,
    /// `AgentRunner` appends a `.tool` per call, and this API expects every
    /// `tool_result` answering a single assistant turn to come back in the
    /// same user message. Splitting them is accepted (consecutive same-role
    /// messages don't 400) but degrades the model's willingness to fan out
    /// on later turns -- a silent behavioral regression no test would catch.
    static func encodeMessages(_ messages: [GPTMessage]) -> [[String: Any]] {
        var encoded: [[String: Any]] = []
        var pendingToolResults: [[String: Any]] = []

        func flushToolResults() {
            guard !pendingToolResults.isEmpty else { return }
            encoded.append(["role": "user", "content": pendingToolResults])
            pendingToolResults = []
        }

        for message in messages {
            switch message {
            case .system:
                continue
            case .tool(let callId, let content):
                // No `role: "tool"` on this API -- a tool result goes back
                // inside a *user* message as a tool_result block keyed by
                // the tool_use id it answers.
                pendingToolResults.append([
                    "type": "tool_result",
                    "tool_use_id": callId,
                    "content": content,
                ])
            case .user(let text):
                flushToolResults()
                encoded.append(["role": "user", "content": text])
            case .assistant(let text, let toolCalls, let reasoning):
                flushToolResults()
                encoded.append([
                    "role": "assistant",
                    "content": encodeAssistantContent(text: text, toolCalls: toolCalls, reasoning: reasoning),
                ])
            }
        }
        flushToolResults()
        return encoded
    }

    /// An assistant turn's `content` is an array mixing thinking blocks, a
    /// text block (if the model narrated) and one `tool_use` block per call.
    /// At least one block is required, so a turn with none of them becomes an
    /// empty string -- matches GPTClient's `content ?? NSNull()` in spirit:
    /// present but empty, not an absent turn.
    ///
    /// Thinking blocks go back first and byte-identical to what came down.
    /// They carry a signature the server verifies against the turn they
    /// belong to, and a turn that thought before calling a tool is rejected
    /// when they are missing -- which is every turn of this loop once thinking
    /// is left on (see `requestBody`). Their text is usually empty (current
    /// models omit the summary by default); the signature is the part that
    /// matters, so nothing here reads inside a block.
    private static func encodeAssistantContent(
        text: String?,
        toolCalls: [GPTToolCall],
        reasoning: String?
    ) -> [[String: Any]] {
        var blocks: [[String: Any]] = decodeReasoning(reasoning)
        if let text, !text.isEmpty {
            blocks.append(["type": "text", "text": text])
        }
        for call in toolCalls {
            blocks.append([
                "type": "tool_use",
                "id": call.id,
                "name": call.name,
                // Anthropic wants the parsed object, not the raw JSON string
                // Chat Completions uses for `arguments` -- decode once here
                // so the wire body carries a real object.
                "input": (try? JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8))) ?? [:],
            ])
        }
        if blocks.isEmpty {
            blocks.append(["type": "text", "text": ""])
        }
        return blocks
    }

    /// The inverse of `encodeReasoning`. A payload that no longer parses into
    /// blocks is dropped rather than thrown on: it can only have come from
    /// this file, so the realistic cause is a turn taken under a provider that
    /// never wrote one, and refusing to send the turn at all would be a worse
    /// failure than letting the server object to what it gets.
    private static func decodeReasoning(_ reasoning: String?) -> [[String: Any]] {
        guard
            let reasoning,
            let blocks = try? JSONSerialization.jsonObject(with: Data(reasoning.utf8)) as? [[String: Any]]
        else { return [] }
        return blocks
    }

    /// Reasoning blocks are stored on `GPTTurn`/`GPTMessage` as JSON text so
    /// the shared, provider-neutral types don't have to carry an untyped
    /// `[String: Any]` this is the only file to understand.
    private static func encodeReasoning(_ blocks: [[String: Any]]) -> String? {
        guard
            !blocks.isEmpty,
            let data = try? JSONSerialization.data(withJSONObject: blocks)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func encode(_ tool: GPTToolSpec) -> [String: Any] {
        [
            "name": tool.name,
            "description": tool.description,
            "input_schema": tool.jsonSchema,
        ]
    }

    // MARK: - Wire decoding

    /// An assistant reply's `content` is an array of blocks -- `text` and
    /// `tool_use` may both appear, same as GPTClient's turn can carry both
    /// narration and calls. `thinking` and `redacted_thinking` are kept
    /// verbatim so the next turn can send them back (see
    /// `encodeAssistantContent`); any other block type is ignored.
    static func decodeTurn(from data: Data) throws -> GPTTurn {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = root["content"] as? [[String: Any]]
        else {
            throw GPTError.malformedResponse("no content array")
        }

        // Both of these arrive as HTTP 200 with an empty or partial content
        // array, so without this check they decode to a turn with no text and
        // no calls -- which AgentRunner reads as "the model said nothing" and
        // finishes the run ok=true, showing the user nothing at all. Surface
        // them as errors instead so the failure is visible.
        if let stopReason = root["stop_reason"] as? String {
            switch stopReason {
            case "refusal":
                throw GPTError.malformedResponse(Strings.text(.providerRefusedResponse))
            case "max_tokens":
                throw GPTError.malformedResponse(
                    String(format: Strings.text(.providerTruncatedFormat), "\(Self.maxTokens)")
                )
            default:
                break
            }
        }

        var texts: [String] = []
        var calls: [GPTToolCall] = []
        var reasoning: [[String: Any]] = []
        for block in content {
            guard let type = block["type"] as? String else { continue }
            switch type {
            case "text":
                if let text = block["text"] as? String { texts.append(text) }
            case "tool_use":
                guard
                    let id = block["id"] as? String,
                    let name = block["name"] as? String
                else { continue }
                // Round-trips the model's parsed `input` back to a JSON
                // string, matching `GPTToolCall.argumentsJSON`'s contract:
                // raw JSON text the caller parses. Absent `input` is a
                // no-parameter tool call -- an empty object, not a failure.
                let input = block["input"] ?? [:]
                let argumentsJSON: String
                if JSONSerialization.isValidJSONObject(input),
                   let encoded = try? JSONSerialization.data(withJSONObject: input) {
                    argumentsJSON = String(data: encoded, encoding: .utf8) ?? "{}"
                } else {
                    argumentsJSON = "{}"
                }
                calls.append(GPTToolCall(id: id, name: name, argumentsJSON: argumentsJSON))
            case "thinking", "redacted_thinking":
                reasoning.append(block)
            default:
                continue
            }
        }
        return GPTTurn(
            text: texts.isEmpty ? nil : texts.joined(separator: "\n"),
            toolCalls: calls,
            reasoning: encodeReasoning(reasoning)
        )
    }
}
