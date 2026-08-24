//
//  PuckMCPServerTests.swift
//  PuckTests
//
//  The two halves joined: a real listener, spoken to the way the coding CLI's
//  MCP client speaks to it, ending in a tool that actually runs.
//

import XCTest
@testable import Puck

final class PuckMCPServerTests: XCTestCase {

    private var server: PuckMCPServer?

    override func tearDown() {
        server?.stop()
        server = nil
        super.tearDown()
    }

    private let specs = [
        GPTToolSpec(
            name: "run_shell",
            description: "Run a shell command.",
            parameters: ToolRegistry.tool(named: "run_shell")?.parameters ?? []
        ),
    ]

    private func start(
        invoke: @escaping AgentToolInvocation = { _, _, _ in
            DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil)
        }
    ) async throws -> JSONValue {
        let server = PuckMCPServer(toolSpecs: specs, invoke: invoke)
        self.server = server
        return try await server.start()
    }

    /// Speaks to the server the way the CLI does: bearer token from the
    /// descriptor, JSON-RPC in the body.
    private func call(_ descriptor: JSONValue, _ message: JSONValue) async throws -> JSONValue? {
        let url = try XCTUnwrap(descriptor["url"]?.stringValue)
        let header = try XCTUnwrap(descriptor["headers"]?.arrayValue?.first)
        var request = URLRequest(url: try XCTUnwrap(URL(string: url)))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            try XCTUnwrap(header["value"]?.stringValue),
            forHTTPHeaderField: try XCTUnwrap(header["name"]?.stringValue)
        )
        request.httpBody = try JSONEncoder().encode(message)
        request.timeoutInterval = 5
        let (data, _) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard !data.isEmpty else { return nil }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func request(_ method: String, params: JSONValue = .object([:])) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": .number(1),
            "method": .string(method),
            "params": params,
        ])
    }

    /// The `zMcpServerHttp` shape the ACP shim accepts. The headers array is
    /// the whole reason the http transport works here: it is what carries the
    /// bearer token.
    func test_start_describesItselfAsAnHttpMcpServerCarryingItsToken() async throws {
        let descriptor = try await start()

        XCTAssertEqual(descriptor["type"]?.stringValue, "http")
        XCTAssertEqual(descriptor["name"]?.stringValue, "puck")
        XCTAssertTrue(try XCTUnwrap(descriptor["url"]?.stringValue).hasPrefix("http://127.0.0.1:"))
        let header = try XCTUnwrap(descriptor["headers"]?.arrayValue?.first)
        XCTAssertEqual(header["name"]?.stringValue, "Authorization")
        XCTAssertTrue(try XCTUnwrap(header["value"]?.stringValue).hasPrefix("Bearer "))
    }

    func test_theWholeHandshake_endsInAToolThatRan() async throws {
        let ran = UncheckedBox<[(String, JSONValue)]>([])
        let descriptor = try await start(invoke: { name, arguments, _ in
            ran.value.append((name, arguments))
            return DispatchedToolResult(
                ok: true,
                data: .object(["stdout": .string("hello\n")]),
                error: nil,
                detail: nil
            )
        })

        let initialized = try await call(descriptor, request("initialize", params: .object([
            "protocolVersion": .string("2025-06-18"),
        ])))
        XCTAssertEqual(initialized?["result"]?["serverInfo"]?["name"]?.stringValue, "puck")

        let notified = try await call(descriptor, .object([
            "jsonrpc": .string("2.0"),
            "method": .string("notifications/initialized"),
        ]))
        XCTAssertNil(notified, "a notification gets an empty 202, not a body")

        let listed = try await call(descriptor, request("tools/list"))
        XCTAssertEqual(
            (listed?["result"]?["tools"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue },
            ["run_shell"]
        )

        let called = try await call(descriptor, request("tools/call", params: .object([
            "name": .string("run_shell"),
            "arguments": .object(["command": .string("echo hello")]),
        ])))

        XCTAssertEqual(ran.value.count, 1)
        XCTAssertEqual(ran.value.first?.0, "run_shell")
        XCTAssertEqual(ran.value.first?.1, .object(["command": .string("echo hello")]))
        XCTAssertEqual(
            called?["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue,
            "{\"stdout\":\"hello\\n\"}"
        )
    }

    func test_aRequestWithoutTheToken_isRefusedBeforeAnyToolRuns() async throws {
        let ran = UncheckedBox(false)
        let descriptor = try await start(invoke: { _, _, _ in
            ran.value = true
            return DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil)
        })

        var request = URLRequest(url: try XCTUnwrap(URL(string: try XCTUnwrap(descriptor["url"]?.stringValue))))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(self.request("tools/call", params: .object([
            "name": .string("run_shell"),
            "arguments": .object(["command": .string("rm -rf /")]),
        ])))
        request.timeoutInterval = 5
        let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 401)
        XCTAssertFalse(ran.value)
    }

    func test_stop_leavesNothingListening() async throws {
        let descriptor = try await start()
        _ = try await call(descriptor, request("tools/list"))

        server?.stop()

        do {
            _ = try await call(descriptor, request("tools/list"))
            XCTFail("the port must not outlive the turn")
        } catch {
            // Connection refused: the listener is gone.
        }
    }

    /// A body that isn't JSON is answered, not dropped: an unanswered request
    /// leaves the CLI waiting out its own timeout.
    func test_aMalformedBody_answersAParseError() async throws {
        let handler = MCPRequestHandler(toolDefinitions: [], invoke: { _, _, _ in
            DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil)
        })

        let answer = await PuckMCPServer.answer(body: Data("not json".utf8), with: handler)

        let decoded = try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(answer))
        XCTAssertEqual(decoded["error"]?["code"]?.numberValue, -32700)
    }
}
