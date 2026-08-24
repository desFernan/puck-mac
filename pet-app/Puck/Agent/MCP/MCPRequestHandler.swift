//
//  MCPRequestHandler.swift
//  Puck
//
//  The JSON-RPC half of Puck's MCP server: initialize / initialized /
//  tools/list / tools/call, and nothing else.
//
//  Transport-free on purpose. LoopbackHTTPServer owns sockets, auth and HTTP
//  framing; this owns the protocol, so the whole surface a coding CLI talks to
//  can be exercised in-process with no listener and no child process.
//
//  ## Why the host runs the tool and not this
//
//  `tools/call` does not execute anything itself -- it calls back into
//  `AgentRunner.invokeTool`, the same entry a tool call from OpenAI or
//  Anthropic goes through. So approval, the socket dispatch, the delegated
//  file routes and the tool_call/tool_result events that make the pet react
//  are one implementation, and a tool behaves identically no matter which
//  provider asked for it.
//

import Foundation

/// Runs one host tool end to end -- approval included -- and reports what
/// happened. `AgentRunner.invokeTool` is the implementation; the closure keeps
/// the MCP server from depending on the runner it is ultimately driven by.
typealias AgentToolInvocation = (_ name: String, _ arguments: JSONValue) async -> DispatchedToolResult

final class MCPRequestHandler {
    /// What we answer `initialize` with when the client asks for a version we
    /// do not recognise. The oldest version every current MCP client still
    /// accepts, and the tools surface used here has not changed across any of
    /// them.
    static let fallbackProtocolVersion = "2025-06-18"

    /// Versions we will echo back verbatim. Claude Code 2.1.x negotiates from
    /// this list (its own SUPPORTED_PROTOCOL_VERSIONS, newest first); anything
    /// outside it gets `fallbackProtocolVersion` instead of a version we have
    /// never seen.
    static let supportedProtocolVersions: Set<String> = [
        "2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05", "2024-10-07",
    ]

    private let toolDefinitions: [JSONValue]
    private let invoke: AgentToolInvocation

    /// Guards `callsInFlight`. A serial queue rather than an NSLock because
    /// both writers are in an async function (`callTool`), and NSLock's
    /// lock/unlock are unavailable from async contexts -- a warning today, an
    /// error in the Swift 6 language mode.
    private let stateQueue = DispatchQueue(label: "Puck.MCPRequestHandler.state")
    private var callsInFlight = 0

    init(toolDefinitions: [JSONValue], invoke: @escaping AgentToolInvocation) {
        self.toolDefinitions = toolDefinitions
        self.invoke = invoke
    }

    /// True while a `tools/call` is being served. The turn's own deadline is
    /// suspended while this holds: a call can legitimately sit for as long as
    /// the user takes to answer an approval prompt, and a chat that gave up on
    /// the CLI mid-approval would look like the pet ignoring the button the
    /// user just pressed.
    var isServingToolCall: Bool {
        stateQueue.sync { callsInFlight > 0 }
    }

    /// One JSON-RPC message in, its response out. nil means "nothing to
    /// answer" -- a notification, which the transport turns into an empty
    /// 202.
    func handle(_ message: JSONValue) async -> JSONValue? {
        guard let method = message["method"]?.stringValue else {
            // A response or a malformed frame. We never send requests to the
            // client, so there is nothing this could be an answer to.
            return nil
        }
        let id = message["id"]
        let params = message["params"] ?? .object([:])

        switch method {
        case "initialize":
            return result(id: id, initializeResult(params: params))
        case "notifications/initialized", "notifications/cancelled":
            return nil
        case "ping":
            return result(id: id, .object([:]))
        case "tools/list":
            return result(id: id, .object(["tools": .array(toolDefinitions)]))
        case "tools/call":
            return await callTool(id: id, params: params)
        default:
            // Notifications get no answer even when we don't know them; a
            // request does, or the client waits out its own timeout.
            guard id != nil else { return nil }
            return failure(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: - Methods

    private func initializeResult(params: JSONValue) -> JSONValue {
        let requested = params["protocolVersion"]?.stringValue
        let version = requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
            ?? Self.fallbackProtocolVersion
        return .object([
            "protocolVersion": .string(version),
            // Tools only. No resources, no prompts, no logging -- claiming a
            // capability we don't implement invites a call we answer with
            // "method not found".
            "capabilities": .object(["tools": .object([:])]),
            "serverInfo": .object([
                "name": .string(MCPToolCatalog.serverName),
                "version": .string("1.0.0"),
            ]),
        ])
    }

    private func callTool(id: JSONValue?, params: JSONValue) async -> JSONValue? {
        guard let name = params["name"]?.stringValue, !name.isEmpty else {
            return failure(id: id, code: -32602, message: "tools/call requires a tool name")
        }
        guard !MCPToolCatalog.excludedToolNames.contains(name), ToolRegistry.tool(named: name) != nil else {
            // Named, but not one of ours (or one we deliberately withhold).
            // A protocol error rather than a tool error: the model asked for
            // something that does not exist, which is not a failed action.
            return failure(id: id, code: -32602, message: "Unknown tool: \(name)")
        }
        let arguments = params["arguments"] ?? .object([:])

        stateQueue.sync { callsInFlight += 1 }
        let outcome = await invoke(name, arguments)
        stateQueue.sync { callsInFlight -= 1 }

        let text = AgentRunner.toolResultText(
            ok: outcome.ok,
            data: outcome.data,
            error: outcome.error,
            detail: outcome.detail
        )
        return result(id: id, .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            // A refused or failed tool is reported *as a tool result*, not as
            // a JSON-RPC error: the model has to read it and say something
            // useful, and a transport error would instead look to the CLI like
            // the server being broken.
            "isError": .bool(!outcome.ok),
        ]))
    }

    // MARK: - Envelopes

    private func result(id: JSONValue?, _ value: JSONValue) -> JSONValue? {
        guard let id else { return nil }
        return .object(["jsonrpc": .string("2.0"), "id": id, "result": value])
    }

    private func failure(id: JSONValue?, code: Int, message: String) -> JSONValue? {
        guard let id else { return nil }
        return .object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "error": .object(["code": .number(Double(code)), "message": .string(message)]),
        ])
    }
}
