//
//  PuckMCPServer.swift
//  Puck
//
//  Puck's tools, offered to the coding CLI as an MCP server for the length of
//  one chat turn.
//
//  ## Why this exists at all
//
//  ACP has no channel for the agent to call back into the host, so the CLI
//  provider used to be text-only and had to tell the model so. But `session/new`
//  takes an `mcpServers` array, and MCP *is* that channel: the tools reach the
//  model as `mcp__puck__*`, the CLI calls them, and they land on exactly the
//  code path a tool call from OpenAI or Anthropic lands on.
//
//  ## Why http, and why in-process
//
//  Of the four transports the ACP shim accepts (http, sse, stdio, acp), stdio
//  would mean bundling a second executable which then has to reach back into
//  PuckClient for every tool -- the implementations are all in-process or
//  behind bridge.sock -- so it is a second hop that buys nothing. An in-process
//  HTTP listener has the dispatcher and the runner right there.
//
//  ## Lifetime
//
//  One server per turn, torn down on every exit path. Nothing listens between
//  turns, and a token from one turn is worthless in the next.
//

import Foundation

final class PuckMCPServer {
    private let http: LoopbackHTTPServer
    private let requests: MCPRequestHandler
    private var endpoint: LoopbackHTTPServer.Endpoint?

    init(toolSpecs: [GPTToolSpec], sessionId: String? = nil, invoke: @escaping AgentToolInvocation) {
        let requests = MCPRequestHandler(
            toolDefinitions: MCPToolCatalog.definitions(for: toolSpecs),
            sessionId: sessionId,
            invoke: invoke
        )
        self.requests = requests
        self.http = LoopbackHTTPServer(handler: { body in
            await PuckMCPServer.answer(body: body, with: requests)
        })
    }

    /// See MCPRequestHandler.isServingToolCall -- the turn's deadline is
    /// suspended while this holds.
    var isServingToolCall: Bool { requests.isServingToolCall }

    /// Starts listening and returns the `session/new` entry describing it.
    /// Throws if the listener could not be opened, which the caller answers by
    /// running the turn without tools rather than failing it.
    func start() async throws -> JSONValue {
        let endpoint = try await http.start()
        self.endpoint = endpoint
        return Self.descriptor(for: endpoint)
    }

    func stop() { http.stop() }

    /// `zMcpServerHttp` as the ACP shim defines it: name, url, and headers as
    /// a list of {name, value} pairs -- which is exactly what carries the
    /// bearer token, and the reason the http transport is usable here at all.
    static func descriptor(for endpoint: LoopbackHTTPServer.Endpoint) -> JSONValue {
        .object([
            "type": .string("http"),
            "name": .string(MCPToolCatalog.serverName),
            "url": .string(endpoint.url),
            "headers": .array([
                .object([
                    "name": .string("Authorization"),
                    "value": .string(endpoint.authorizationHeaderValue),
                ]),
            ]),
        ])
    }

    /// One HTTP body in, one out. Handles a JSON-RPC batch as well as a single
    /// message: MCP 2025-03-26 allows one, and a batch of notifications
    /// correctly produces no response at all.
    static func answer(body: Data, with requests: MCPRequestHandler) async -> Data? {
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: body) else {
            return try? JSONEncoder().encode(JSONValue.object([
                "jsonrpc": .string("2.0"),
                "id": .null,
                "error": .object([
                    "code": .number(-32700),
                    "message": .string("Parse error"),
                ]),
            ]))
        }
        if let batch = message.arrayValue {
            var answers: [JSONValue] = []
            for entry in batch {
                if let answer = await requests.handle(entry) { answers.append(answer) }
            }
            guard !answers.isEmpty else { return nil }
            return try? JSONEncoder().encode(JSONValue.array(answers))
        }
        guard let answer = await requests.handle(message) else { return nil }
        return try? JSONEncoder().encode(answer)
    }
}
