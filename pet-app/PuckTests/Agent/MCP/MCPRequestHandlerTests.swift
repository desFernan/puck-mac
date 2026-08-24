//
//  MCPRequestHandlerTests.swift
//  PuckTests
//
//  The JSON-RPC surface the coding CLI talks to. No listener and no child
//  process: the handler is transport-free precisely so the protocol can be
//  driven directly.
//

import XCTest
@testable import Puck

final class MCPRequestHandlerTests: XCTestCase {

    /// What the runner hands every provider, trimmed to three tools.
    private let specs: [GPTToolSpec] = [
        GPTToolSpec(
            name: "launch_app",
            description: "Launch a macOS app.",
            parameters: ToolRegistry.tool(named: "launch_app")?.parameters ?? []
        ),
        GPTToolSpec(
            name: "run_shell",
            description: "Run a shell command.",
            parameters: ToolRegistry.tool(named: "run_shell")?.parameters ?? []
        ),
        GPTToolSpec(
            name: "code_editor",
            description: "Hand a coding task to the editor agent.",
            parameters: ToolRegistry.tool(named: "code_editor")?.parameters ?? []
        ),
    ]

    private func makeHandler(
        invoke: @escaping AgentToolInvocation = { _, _, _ in
            DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil)
        }
    ) -> MCPRequestHandler {
        MCPRequestHandler(toolDefinitions: MCPToolCatalog.definitions(for: specs), invoke: invoke)
    }

    /// XCTUnwrap takes an autoclosure, which cannot contain an `await`. This
    /// takes a plain value instead, so the handler call can be awaited inline.
    private func require(
        _ value: JSONValue?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> JSONValue {
        try XCTUnwrap(value, file: file, line: line)
    }

    private func request(_ method: String, id: Int = 1, params: JSONValue = .object([:])) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": .number(Double(id)),
            "method": .string(method),
            "params": params,
        ])
    }

    // MARK: - initialize

    func test_initialize_advertisesToolsAndNamesTheServerPuck() async throws {
        let answer = try require(await makeHandler().handle(request("initialize")))

        XCTAssertEqual(answer["id"]?.numberValue, 1)
        let result = try XCTUnwrap(answer["result"])
        XCTAssertNotNil(result["capabilities"]?["tools"])
        XCTAssertNil(result["capabilities"]?["resources"], "a capability we don't implement must not be claimed")
        XCTAssertEqual(result["serverInfo"]?["name"]?.stringValue, "puck")
    }

    /// Version negotiation: a client asking for one we know gets it back, so
    /// the CLI does not have to downgrade.
    func test_initialize_echoesAProtocolVersionItSupports() async throws {
        let answer = try require(await makeHandler().handle(
            request("initialize", params: .object(["protocolVersion": .string("2025-11-25")]))
        ))

        XCTAssertEqual(answer["result"]?["protocolVersion"]?.stringValue, "2025-11-25")
    }

    /// And one we have never seen gets an answer we can stand behind rather
    /// than an echo of a version we have never implemented.
    func test_initialize_fallsBackForAnUnknownProtocolVersion() async throws {
        let answer = try require(await makeHandler().handle(
            request("initialize", params: .object(["protocolVersion": .string("2099-01-01")]))
        ))

        XCTAssertEqual(
            answer["result"]?["protocolVersion"]?.stringValue,
            MCPRequestHandler.fallbackProtocolVersion
        )
    }

    /// A notification is not a request: answering it would put a response with
    /// no id on the wire.
    func test_initializedNotification_isAnswered_withNothing() async {
        let notification = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "method": .string("notifications/initialized"),
        ])

        let answer = await makeHandler().handle(notification)

        XCTAssertNil(answer)
    }

    // MARK: - tools/list

    func test_toolsList_returnsTheHostToolsWithTheirSchemas() async throws {
        let answer = try require(await makeHandler().handle(request("tools/list", id: 7)))

        let tools = try XCTUnwrap(answer["result"]?["tools"]?.arrayValue)
        let names = tools.compactMap { $0["name"]?.stringValue }
        XCTAssertEqual(names, ["launch_app", "run_shell"])
        let runShell = try XCTUnwrap(tools.first { $0["name"]?.stringValue == "run_shell" })
        XCTAssertEqual(runShell["description"]?.stringValue, "Run a shell command.")
        XCTAssertEqual(runShell["inputSchema"]?["type"]?.stringValue, "object")
        XCTAssertEqual(runShell["inputSchema"]?["properties"]?["command"]?["type"]?.stringValue, "string")
        XCTAssertEqual(runShell["inputSchema"]?["required"]?.arrayValue, [.string("command")])
    }

    /// The CLI *is* the coding agent code_editor would delegate to, so handing
    /// it back would spawn a second vendor process inside the first one's turn.
    func test_toolsList_neverOffersCodeEditor() async throws {
        let answer = try require(await makeHandler().handle(request("tools/list")))

        let names = (answer["result"]?["tools"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue }
        XCTAssertFalse(names.contains("code_editor"))
    }

    // MARK: - tools/call

    func test_toolsCall_runsTheToolThroughTheHostAndReturnsItsResult() async throws {
        let seen = UncheckedBox<[(String, JSONValue)]>([])
        let handler = makeHandler(invoke: { name, arguments, _ in
            seen.value.append((name, arguments))
            return DispatchedToolResult(ok: true, data: .object(["pid": .number(42)]), error: nil, detail: nil)
        })

        let answer = try require(await handler.handle(request("tools/call", params: .object([
            "name": .string("launch_app"),
            "arguments": .object(["app_name": .string("Weather")]),
        ]))))

        XCTAssertEqual(seen.value.count, 1)
        XCTAssertEqual(seen.value.first?.0, "launch_app")
        XCTAssertEqual(seen.value.first?.1, .object(["app_name": .string("Weather")]))
        let content = try XCTUnwrap(answer["result"]?["content"]?.arrayValue?.first)
        XCTAssertEqual(content["type"]?.stringValue, "text")
        XCTAssertEqual(content["text"]?.stringValue, "{\"pid\":42}")
        XCTAssertEqual(answer["result"]?["isError"]?.boolValue, false)
    }

    /// A refused tool comes back as a *tool* error, not a transport one: the
    /// model has to read "denied_by_user" and say something about it, and a
    /// JSON-RPC error would look to the CLI like the server being broken.
    func test_toolsCall_reportsARefusalAsAToolErrorTheModelCanRead() async throws {
        let handler = makeHandler(invoke: { _, _, _ in
            DispatchedToolResult(ok: false, data: nil, error: "denied_by_user", detail: nil)
        })

        let answer = try require(await handler.handle(request("tools/call", params: .object([
            "name": .string("run_shell"),
            "arguments": .object(["command": .string("ls")]),
        ]))))

        XCTAssertNil(answer["error"])
        XCTAssertEqual(answer["result"]?["isError"]?.boolValue, true)
        XCTAssertEqual(
            answer["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue,
            "error: denied_by_user"
        )
    }

    func test_toolsCall_refusesANameThatIsNotInTheRegistry() async throws {
        let ran = UncheckedBox(false)
        let handler = makeHandler(invoke: { _, _, _ in
            ran.value = true
            return DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil)
        })

        let answer = try require(await handler.handle(request("tools/call", params: .object([
            "name": .string("rm_rf_everything"),
        ]))))

        XCTAssertEqual(answer["error"]?["code"]?.numberValue, -32602)
        XCTAssertFalse(ran.value, "a tool that isn't ours must never reach the host")
    }

    /// Withheld is withheld: leaving it out of tools/list but honouring a call
    /// for it would be a list the server does not enforce.
    func test_toolsCall_refusesCodeEditorEvenThoughItIsInTheRegistry() async throws {
        let ran = UncheckedBox(false)
        let handler = makeHandler(invoke: { _, _, _ in
            ran.value = true
            return DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil)
        })

        let answer = try require(await handler.handle(request("tools/call", params: .object([
            "name": .string("code_editor"),
            "arguments": .object(["task": .string("아무거나")]),
        ]))))

        XCTAssertEqual(answer["error"]?["code"]?.numberValue, -32602)
        XCTAssertFalse(ran.value)
    }

    func test_unknownMethod_answersMethodNotFoundRatherThanStalling() async throws {
        let answer = try require(await makeHandler().handle(request("resources/list")))

        XCTAssertEqual(answer["error"]?["code"]?.numberValue, -32601)
    }

    // MARK: - Deadline suspension

    /// The turn's deadline is paused while this holds, so a tool sitting on an
    /// approval prompt does not spend the CLI's budget.
    func test_isServingToolCall_holdsForTheLengthOfACall() async {
        let handler = makeHandler(invoke: { _, _, _ in
            try? await Task.sleep(nanoseconds: 300_000_000)
            return DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil)
        })
        XCTAssertFalse(handler.isServingToolCall)

        let call = Task { [message = request("tools/call", params: .object([
            "name": .string("launch_app"),
            "arguments": .object([:]),
        ]))] in
            await handler.handle(message)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(handler.isServingToolCall, "a call in flight has to suspend the turn's deadline")

        _ = await call.value
        XCTAssertFalse(handler.isServingToolCall)
    }
}
