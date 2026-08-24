//
//  GPTClient.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  A thin OpenAI Chat Completions client with tool calling.
//
//  The pet needs to drive the screen -- launching apps, reacting to what's
//  open -- via a chat brain with tool calling. plan/04_ai-module.md specifies
//  this brain as a TypeScript module against the Claude API, hosted by workspace -- but
//  workspace and ai-module are both still empty repos, the chat client is
//  Swift now, and the key the team has is an OpenAI one. So the loop lives
//  here for the moment; see AgentRunner's header for what that costs.
//
//  No SDK, same reasoning as plan/04_ai-module.md section 4 gives for the
//  Claude client: a tool-use loop needs three request fields and reads two
//  response fields, and a dependency for that is a dependency to keep
//  updated. Non-streaming for a first pass -- the pet reacts to tool calls,
//  not to tokens, so streaming buys nothing until the chat view wants a
//  typing effect.
//

import Foundation

/// One entry of the conversation as the API models it.
enum GPTMessage {
    case system(String)
    case user(String)
    /// What the model said, plus any tool calls it asked for. Both can be
    /// present: a model may narrate and then call.
    ///
    /// `reasoning` carries the provider's own reasoning blocks for that turn,
    /// verbatim as JSON text rather than parsed. On the Messages API a turn
    /// that thought *and* called a tool has to be sent back with those blocks
    /// unchanged -- they carry a signature the server checks -- so this has to
    /// survive the round trip byte for byte, and nothing here needs to read
    /// inside it. nil for every provider that produces none, which today is
    /// everyone except ClaudeClient.
    case assistant(text: String?, toolCalls: [GPTToolCall], reasoning: String?)
    /// The reply to one tool call, keyed by the id the model gave it.
    case tool(callId: String, content: String)
}

struct GPTToolCall: Equatable {
    let id: String
    let name: String
    /// Raw JSON text, exactly as the model emitted it -- parsed by the caller,
    /// which is the only place that knows what shape the tool wants.
    let argumentsJSON: String
}

/// What one turn produced: text to show, and calls to run. An empty
/// `toolCalls` means the model is done.
struct GPTTurn {
    let text: String?
    let toolCalls: [GPTToolCall]
    /// See `GPTMessage.assistant`. Defaulted in the initializer so the
    /// providers that never produce one keep constructing turns unchanged.
    let reasoning: String?

    init(text: String?, toolCalls: [GPTToolCall], reasoning: String? = nil) {
        self.text = text
        self.toolCalls = toolCalls
        self.reasoning = reasoning
    }
}

/// A tool as offered to the model: the registry's shape plus the description
/// text, which the registry deliberately does not carry (see ToolRegistry).
struct GPTToolSpec {
    let name: String
    let description: String
    let parameters: [ToolRegistry.Parameter]
}

enum GPTError: LocalizedError {
    case notConfigured
    case http(status: Int, body: String)
    case malformedResponse(String)

    /// Both clients throw these, so the text can't name a provider -- an
    /// Anthropic user with a bad key was being told "OpenAI API 401", which
    /// is exactly the confusion AgentHost's provider-aware "no key" message
    /// was added to prevent. Whoever is showing this already knows which
    /// provider is selected (`AgentConfiguration.provider`); the error only
    /// needs to say what went wrong.
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return Strings.text(.providerNoAPIKey)
        case .http(let status, let body):
            return String(format: Strings.text(.providerAPIErrorFormat), "\(status)", body)
        case .malformedResponse(let what):
            return String(format: Strings.text(.providerUndecodableFormat), what)
        }
    }
}

/// What `AgentRunner` needs from an LLM: one tool-use turn in, one turn out.
///
/// The `GPT*` payload types keep their names even though they now cross
/// provider lines -- renaming them would touch every call site for no
/// behavioral gain, and the shapes really are the same three request fields
/// and two response fields regardless of who serves them.
protocol AgentLLMClient {
    /// - Parameter sessionId: the chat this turn belongs to, so anything the
    ///   turn does out of band -- the CLI provider calling Puck's tools over
    ///   MCP -- is addressed to it rather than to whichever chat happens to be
    ///   running when the call arrives. Runs overlap: cancelling is a request,
    ///   and a superseded CLI turn goes on working until it notices.
    func send(messages: [GPTMessage], tools: [GPTToolSpec], sessionId: String?) async throws -> GPTTurn
}

extension AgentLLMClient {
    /// For callers with no chat of their own -- the chat titler, and tests.
    func send(messages: [GPTMessage], tools: [GPTToolSpec]) async throws -> GPTTurn {
        try await send(messages: messages, tools: tools, sessionId: nil)
    }
}

/// Routes each `send` to the underlying client matching `configuration()`'s
/// `provider` *at the time of that call* -- not at construction. Both
/// `GPTClient` and `ClaudeClient` already re-read `configuration()` per
/// request so a key typed into Settings works without a relaunch; picking
/// the provider itself only once (at `AgentHost.init`, which both apps call
/// exactly once) contradicted that and left a provider switch in Settings
/// stuck until the app restarted. Constructing both underlying clients is
/// cheap -- they hold only a closure and a `URLSession` -- so there is no
/// real cost to keeping both around and asking on every turn which one to
/// use. A third provider only ever means adding one more case here.
final class RoutingAgentLLMClient: AgentLLMClient {
    private let configuration: () -> AgentConfiguration
    private let openAIClient: any AgentLLMClient
    private let anthropicClient: any AgentLLMClient
    /// The vendor coding-agent CLI, over ACP. Constructing it is as cheap as
    /// the other two -- it holds closures, and spawns nothing until a turn
    /// actually routes to it.
    private let cliClient: any AgentLLMClient

    init(
        configuration: @escaping () -> AgentConfiguration,
        openAIClient: any AgentLLMClient,
        anthropicClient: any AgentLLMClient,
        cliClient: any AgentLLMClient
    ) {
        self.configuration = configuration
        self.openAIClient = openAIClient
        self.anthropicClient = anthropicClient
        self.cliClient = cliClient
    }

    func send(messages: [GPTMessage], tools: [GPTToolSpec], sessionId: String?) async throws -> GPTTurn {
        switch configuration().provider {
        case .openai:
            return try await openAIClient.send(messages: messages, tools: tools, sessionId: sessionId)
        case .anthropic:
            return try await anthropicClient.send(messages: messages, tools: tools, sessionId: sessionId)
        case .cli:
            return try await cliClient.send(messages: messages, tools: tools, sessionId: sessionId)
        }
    }
}

/// `AgentHost` (both apps only ever construct one of these, at
/// `AgentHost.init`) gets a client that re-decides the provider on every
/// `send` -- see `RoutingAgentLLMClient`.
///
/// `workingDirectory` only matters to the CLI provider, which opens its ACP
/// session there: the active workspace's project folder when it has one, so a
/// CLI asked about "this file" can actually look at it.
///
/// `invokeTool` only matters to the CLI provider too. It cannot answer with
/// tool calls the way the other two do (ACP has no channel for it), so it
/// hands Puck's tools to the CLI as an MCP server instead and runs each call
/// through this -- which is `AgentRunner.invokeTool`, the same entry the other
/// providers' tool calls reach. Left nil, the CLI turn is text-only.
func makeAgentLLMClient(
    _ configuration: @escaping () -> AgentConfiguration,
    workingDirectory: @escaping () -> String = CodingAgentCLIClient.projectlessWorkingDirectory,
    invokeTool: AgentToolInvocation? = nil
) -> any AgentLLMClient {
    RoutingAgentLLMClient(
        configuration: configuration,
        openAIClient: GPTClient(configuration: configuration),
        anthropicClient: ClaudeClient(configuration: configuration),
        cliClient: CodingAgentCLIClient(
            configuration: configuration,
            workingDirectory: workingDirectory,
            invokeTool: invokeTool
        )
    )
}

final class GPTClient: AgentLLMClient {
    /// Read per request, not captured once: a key typed into Settings has to
    /// take effect without quitting the app, and this is a file read.
    private let configuration: () -> AgentConfiguration
    private let session: URLSession
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.model,
            "messages": messages.map(Self.encode),
            "tools": tools.map(Self.encode),
            // One call per turn. AgentRunner performs a turn's calls
            // sequentially anyway, and asking for a *sequence* (2026-08-12:
            // open_task_session then code_editor) is what made the model
            // write the whole plan out as a python snippet instead of calling
            // anything -- with batching off it makes the first call, sees its
            // result, and then makes the next.
            "parallel_tool_calls": false,
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GPTError.malformedResponse("not an HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            // The body is where OpenAI puts the actual reason (bad key,
            // unknown model, rate limit) -- a bare status code sends whoever
            // is debugging this to the wrong place.
            throw GPTError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.decodeTurn(from: data)
    }

    // MARK: - Wire encoding

    private static func encode(_ message: GPTMessage) -> [String: Any] {
        switch message {
        case .system(let text):
            return ["role": "system", "content": text]
        case .user(let text):
            return ["role": "user", "content": text]
        case .assistant(let text, let toolCalls, _):
            var payload: [String: Any] = ["role": "assistant"]
            // Must be present even when nil, and must be null rather than ""
            // -- an assistant turn that only called tools has no content, and
            // the API rejects the message if the key is missing entirely.
            payload["content"] = text ?? NSNull()
            if !toolCalls.isEmpty {
                payload["tool_calls"] = toolCalls.map { call in
                    [
                        "id": call.id,
                        "type": "function",
                        "function": ["name": call.name, "arguments": call.argumentsJSON],
                    ]
                }
            }
            return payload
        case .tool(let callId, let content):
            return ["role": "tool", "tool_call_id": callId, "content": content]
        }
    }

    private static func encode(_ tool: GPTToolSpec) -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []
        for parameter in tool.parameters {
            properties[parameter.name] = ["type": parameter.type.rawValue]
            if parameter.isRequired { required.append(parameter.name) }
        }
        return [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                ],
            ],
        ]
    }

    // MARK: - Wire decoding

    private static func decodeTurn(from data: Data) throws -> GPTTurn {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any]
        else {
            throw GPTError.malformedResponse("no choices[0].message")
        }

        let text = message["content"] as? String
        let calls = (message["tool_calls"] as? [[String: Any]] ?? []).compactMap { call -> GPTToolCall? in
            guard
                let id = call["id"] as? String,
                let function = call["function"] as? [String: Any],
                let name = function["name"] as? String
            else {
                return nil
            }
            // Absent arguments is the model calling a no-parameter tool; that
            // is an empty object, not a failure to decode.
            return GPTToolCall(id: id, name: name, argumentsJSON: function["arguments"] as? String ?? "{}")
        }
        return GPTTurn(text: text, toolCalls: calls)
    }
}
