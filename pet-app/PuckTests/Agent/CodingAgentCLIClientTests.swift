//
//  CodingAgentCLIClientTests.swift
//  PuckTests
//
//  The CLI-backed conversation provider: one ACP turn in, one text-only
//  GPTTurn out, with Puck's own tools handed to the agent as an MCP server on
//  the way. Driven against a scripted NDJSON stream, so none of this spawns
//  node or needs a vendor CLI installed.
//

import XCTest
@testable import Puck

/// An AcpAgentTransport over a scripted connection, tracking the teardown the
/// client is supposed to perform.
private final class FakeTransport: AcpAgentTransport {
    let connection: AcpConnection
    private(set) var terminateCount = 0
    private(set) var killCount = 0
    var isRunning = true
    var stderr = ""

    init(connection: AcpConnection) {
        self.connection = connection
    }

    func terminate() {
        terminateCount += 1
        isRunning = false
    }

    func kill() { killCount += 1 }

    func currentStderrTail() -> String { stderr }
}

private func agentTextChunk(_ text: String) -> JSONValue {
    .object([
        "jsonrpc": .string("2.0"),
        "method": .string("session/update"),
        "params": .object([
            "sessionId": .string("s-1"),
            "update": .object([
                "sessionUpdate": .string("agent_message_chunk"),
                "content": .object(["type": .string("text"), "text": .string(text)]),
            ]),
        ]),
    ])
}

/// The CLI provider as `AgentConfiguration` resolves it: no key, no model.
/// Which CLI is not part of this -- `codingAgent` reads `CODING_AGENT` from
/// the environment, deliberately the same setting `code_editor` reads -- and
/// these tests inject `startAgent` instead, so the kind never matters here.
private func cliConfiguration() -> AgentConfiguration {
    AgentConfiguration(apiKey: nil, model: "", provider: .cli, keySource: nil)
}

final class CodingAgentCLIClientTests: XCTestCase {

    func test_projectlessWorkingDirectoryIsScopedAwayFromTheUsersHome() {
        let directory = CodingAgentCLIClient.projectlessWorkingDirectory()

        XCTAssertNotEqual(directory, NSHomeDirectory())
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory))
    }

    // MARK: - The happy path

    func test_send_returnsTheAgentsTextAsATextOnlyTurn() async throws {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(agentTextChunk("안녕하세요!"))
            return .object(["stopReason": .string("end_turn")])
        }
        let transport = FakeTransport(connection: agent.connection)
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in transport }
        )

        let turn = try await client.send(messages: [.user("안녕")], tools: [])

        XCTAssertEqual(turn.text, "안녕하세요!")
        XCTAssertTrue(turn.toolCalls.isEmpty)
    }

    /// The host's tools are handed over on every send and cannot be honoured
    /// here -- ACP has no tool-call channel back to us. A turn that quietly
    /// claimed one would be the model narrating an action nothing performed.
    func test_send_neverReturnsToolCalls_evenWhenToolsAreOffered() async throws {
        let agent = ScriptedAgent()
        agent.stubHandshake()
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(agentTextChunk("네."))
            return .object(["stopReason": .string("end_turn")])
        }
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in FakeTransport(connection: agent.connection) }
        )

        let turn = try await client.send(
            messages: [.user("날씨 앱 켜줘")],
            tools: [GPTToolSpec(name: "launch_app", description: "launch", parameters: [])]
        )

        XCTAssertTrue(turn.toolCalls.isEmpty)
    }

    func test_send_opensTheSessionOnTheWorkingDirectory() async throws {
        let agent = ScriptedAgent()
        agent.stubHandshake()
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(agentTextChunk("확인했어요."))
            return .object(["stopReason": .string("end_turn")])
        }
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            workingDirectory: { "/tmp/some-project" },
            startAgent: { _, _ in FakeTransport(connection: agent.connection) }
        )

        _ = try await client.send(messages: [.user("여기 뭐 있어?")], tools: [])

        XCTAssertEqual(agent.params(forMethod: "session/new")?["cwd"]?.stringValue, "/tmp/some-project")
    }

    /// A child left behind is a node process plus the vendor's ~256MB binary
    /// with nothing on screen to point at it, and a chat turn happens far more
    /// often than a code edit does.
    func test_send_endsTheAgentProcessWhenTheTurnIsDone() async throws {
        let agent = ScriptedAgent()
        agent.stubHandshake()
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(agentTextChunk("끝."))
            return .object(["stopReason": .string("end_turn")])
        }
        let transport = FakeTransport(connection: agent.connection)
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in transport }
        )

        _ = try await client.send(messages: [.user("hi")], tools: [])
        // Teardown is detached so the answer does not wait on a child's exit.
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(transport.terminateCount, 1)
    }

    // MARK: - Failures

    /// codex is not installed on every machine (and is not installed on the
    /// one this was written on). Nothing was spawned, so there is nothing to
    /// wait on: it has to fail immediately, with the same sentence
    /// code_editor uses, rather than hang until a timeout.
    func test_send_reportsAMissingVendorCLIImmediately() async {
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in throw AcpAgentCommandError.vendorCLINotFound(.codex) }
        )

        do {
            _ = try await client.send(messages: [.user("hi")], tools: [])
            XCTFail("a missing CLI must fail the turn")
        } catch {
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                String(format: Strings.text(.acpCLINotFoundFormat), "codex")
            )
        }
    }

    func test_send_reportsAMissingNodeInTermsOfWhatTheUserWasDoing() async {
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in throw AcpAgentCommandError.nodeNotFound }
        )

        do {
            _ = try await client.send(messages: [.user("hi")], tools: [])
            XCTFail("a missing node must fail the turn")
        } catch {
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                String(format: Strings.text(.acpNeedsNodeFormat), Strings.text(.cliConversationPurpose))
            )
        }
    }

    /// The classic: the CLI is installed but not logged in. The ACP error
    /// names a symptom; the stderr tail is the part that says what to do, so
    /// both have to reach the transcript.
    func test_send_reportsAnAcpErrorWithTheStderrThatExplainsIt() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        agent.errorReplies["session/prompt"] = (code: -32000, message: "Authentication required")
        let transport = FakeTransport(connection: agent.connection)
        transport.stderr = "claude: Not logged in. Run `claude login`."
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in transport }
        )

        do {
            _ = try await client.send(messages: [.user("hi")], tools: [])
            XCTFail("an ACP error must fail the turn")
        } catch {
            let described = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(described.contains("Authentication required"), described)
            XCTAssertTrue(described.contains("claude login"), described)
        }
    }

    func test_send_reportsATurnThatSaidNothingRatherThanReturningAnEmptyReply() async {
        let agent = ScriptedAgent()
        agent.stubHandshake(stopReason: "max_tokens")
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in FakeTransport(connection: agent.connection) }
        )

        do {
            let turn = try await client.send(messages: [.user("hi")], tools: [])
            XCTFail("an empty turn must not become an empty assistant bubble: \(turn.text ?? "nil")")
        } catch {
            XCTAssertEqual(error as? CodingAgentCLIError, .emptyReply(stopReason: "max_tokens"))
        }
    }

    /// A child that is alive but wedged answers session/prompt never. Without
    /// a deadline the chat spins until the app is quit.
    func test_send_givesUpOnAnAgentThatNeverAnswers() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        // No reply to session/prompt at all.
        let transport = FakeTransport(connection: agent.connection)
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            timeoutSeconds: 0.2,
            startAgent: { _, _ in transport }
        )

        do {
            _ = try await client.send(messages: [.user("hi")], tools: [])
            XCTFail("a wedged agent must not hold the turn open")
        } catch {
            XCTAssertEqual(error as? CodingAgentCLIError, .timedOut(seconds: 0))
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(transport.terminateCount, 1, "the wedged child must be ended, not abandoned")
    }

    // MARK: - Prompt construction

    /// The whole point of the override: AgentRunner's system prompt names the
    /// tools by their bare names, and on this provider they only exist under
    /// `mcp__puck__`. Whatever else changes, this text has to be in the prompt.
    func test_prompt_carriesTheToolAvailabilityOverrideWhenTheToolsAreReachable() {
        let prompt = CodingAgentCLIClient.prompt(
            for: [.system("You are the brain of Puck."), .user("안녕")],
            toolsAreReachable: true
        )

        XCTAssertTrue(prompt.contains(CodingAgentCLIClient.toolAvailabilityOverride))
        XCTAssertFalse(prompt.contains(CodingAgentCLIClient.toolsUnavailableOverride))
    }

    /// The override has to name the tools the way the agent actually sees
    /// them. A model told to call `point_at` when the tool is registered as
    /// `mcp__puck__point_at` writes the action out in prose instead.
    func test_toolAvailabilityOverride_namesTheToolsUnderTheirMcpPrefix() {
        let override = CodingAgentCLIClient.toolAvailabilityOverride

        XCTAssertTrue(override.contains("mcp__puck__point_at"))
        XCTAssertTrue(override.contains("mcp__puck__run_shell"))
    }

    /// code_editor is the one tool deliberately withheld -- the CLI is the
    /// coding agent it would delegate to -- so the prompt has to say what to
    /// do instead rather than leaving the model to call a tool that isn't
    /// listed.
    func test_toolAvailabilityOverride_saysCodeEditorIsNotAvailableHere() {
        XCTAssertTrue(CodingAgentCLIClient.toolAvailabilityOverride.contains("code_editor"))
        XCTAssertFalse(CodingAgentCLIClient.toolAvailabilityOverride.contains("mcp__puck__code_editor"))
    }

    /// A server that could not be opened must not be advertised: the turn
    /// still runs, and the prompt has to be the honest one.
    func test_prompt_saysTheToolsAreUnavailableWhenTheyAre() {
        let prompt = CodingAgentCLIClient.prompt(
            for: [.system("You are the brain of Puck."), .user("안녕")],
            toolsAreReachable: false
        )

        XCTAssertTrue(prompt.contains(CodingAgentCLIClient.toolsUnavailableOverride))
        XCTAssertFalse(prompt.contains(CodingAgentCLIClient.toolAvailabilityOverride))
    }

    /// After the system prompt it contradicts, not before: the later
    /// instruction is the one a model follows.
    func test_prompt_putsTheOverrideAfterTheSystemPromptItCorrects() throws {
        let prompt = CodingAgentCLIClient.prompt(
            for: [.system("Use point_at to show the user."), .user("안녕")],
            toolsAreReachable: true
        )

        let system = try XCTUnwrap(prompt.range(of: "Use point_at to show the user."))
        let override = try XCTUnwrap(prompt.range(of: CodingAgentCLIClient.toolAvailabilityOverride))
        XCTAssertTrue(system.lowerBound < override.lowerBound)
    }

    func test_prompt_carriesEverySystemLine_includingTheWorkspaceContext() {
        let prompt = CodingAgentCLIClient.prompt(for: [
            .system("You are the brain of Puck."),
            .system("Current workspace: puck, bound to the project at /tmp/puck."),
            .user("여기 뭐 있어?"),
        ], toolsAreReachable: true)

        XCTAssertTrue(prompt.contains("You are the brain of Puck."))
        XCTAssertTrue(prompt.contains("bound to the project at /tmp/puck"))
    }

    /// One prompt per turn carries the whole conversation: there is no live
    /// ACP session between turns holding it (see the client's header).
    func test_prompt_rendersTheWholeTranscriptInOrder() {
        let prompt = CodingAgentCLIClient.prompt(for: [
            .system("system"),
            .user("첫 질문"),
            .assistant(text: "첫 답변", toolCalls: [], reasoning: nil),
            .user("둘째 질문"),
        ], toolsAreReachable: true)

        let first = prompt.range(of: "User: 첫 질문")
        let answer = prompt.range(of: "Assistant: 첫 답변")
        let second = prompt.range(of: "User: 둘째 질문")
        XCTAssertNotNil(first)
        XCTAssertNotNil(answer)
        XCTAssertNotNil(second)
        XCTAssertTrue(first!.lowerBound < answer!.lowerBound)
        XCTAssertTrue(answer!.lowerBound < second!.lowerBound)
    }

    /// A conversation can start on OpenAI, call launch_app, and then be
    /// continued here after a provider switch. Those turns are history, and
    /// dropping them would leave the CLI answering a question whose context
    /// it cannot see.
    func test_prompt_keepsToolCallsAndResultsFromTurnsTakenUnderAnotherProvider() {
        let prompt = CodingAgentCLIClient.prompt(for: [
            .system("system"),
            .user("날씨 앱 켜줘"),
            .assistant(text: nil, toolCalls: [
                GPTToolCall(id: "1", name: "launch_app", argumentsJSON: "{\"app_name\":\"Weather\"}"),
            ], reasoning: nil),
            .tool(callId: "1", content: "{\"pid\":42}"),
            .user("켜졌어?"),
        ], toolsAreReachable: true)

        XCTAssertTrue(prompt.contains("launch_app"))
        XCTAssertTrue(prompt.contains("{\"app_name\":\"Weather\"}"))
        XCTAssertTrue(prompt.contains("Tool result: {\"pid\":42}"))
    }

    func test_prompt_isSentAsTheAcpPromptText() async throws {
        let agent = ScriptedAgent()
        agent.stubHandshake()
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(agentTextChunk("네."))
            return .object(["stopReason": .string("end_turn")])
        }
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in FakeTransport(connection: agent.connection) }
        )

        _ = try await client.send(messages: [.system("system"), .user("고유한질문")], tools: [])

        let sent = agent.params(forMethod: "session/prompt")?["prompt"]?.arrayValue?.first?["text"]?.stringValue
        XCTAssertNotNil(sent)
        XCTAssertTrue(sent!.contains("User: 고유한질문"))
        // No invokeTool was supplied, so no MCP server was started and the
        // prompt must say the tools are unreachable rather than name them.
        XCTAssertTrue(sent!.contains(CodingAgentCLIClient.toolsUnavailableOverride))
    }

    // MARK: - The MCP server the agent is handed

    private func toolSpecs() -> [GPTToolSpec] {
        [
            GPTToolSpec(
                name: "run_shell",
                description: "Run a shell command.",
                parameters: ToolRegistry.tool(named: "run_shell")?.parameters ?? []
            ),
            GPTToolSpec(
                name: "code_editor",
                description: "Delegate a coding task.",
                parameters: ToolRegistry.tool(named: "code_editor")?.parameters ?? []
            ),
        ]
    }

    /// The gap this closes: `session/new` used to send an empty mcpServers
    /// array, which is why the CLI had no way to reach Puck's tools at all.
    func test_send_handsTheAgentAnHttpMcpServerOnSessionNew() async throws {
        let agent = ScriptedAgent()
        agent.stubHandshake()
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(agentTextChunk("네."))
            return .object(["stopReason": .string("end_turn")])
        }
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            invokeTool: { _, _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) },
            startAgent: { _, _ in FakeTransport(connection: agent.connection) }
        )

        _ = try await client.send(messages: [.user("hi")], tools: toolSpecs())

        let servers = try XCTUnwrap(agent.params(forMethod: "session/new")?["mcpServers"]?.arrayValue)
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers.first?["type"]?.stringValue, "http")
        XCTAssertEqual(servers.first?["name"]?.stringValue, "puck")
        XCTAssertTrue(try XCTUnwrap(servers.first?["url"]?.stringValue).hasPrefix("http://127.0.0.1:"))
        let header = try XCTUnwrap(servers.first?["headers"]?.arrayValue?.first)
        XCTAssertEqual(header["name"]?.stringValue, "Authorization")
    }

    /// The address is only worth sending if something answers it. This calls
    /// the server the way the CLI would, from inside the turn.
    func test_send_theAdvertisedServerAnswersToolsListWhileTheTurnRuns() async throws {
        let agent = ScriptedAgent()
        agent.stubHandshake()
        let listed = UncheckedBox<[String]>([])
        agent.replies["session/prompt"] = { [weak agent] _ in
            let descriptor = agent?.params(forMethod: "session/new")?["mcpServers"]?.arrayValue?.first
            if let descriptor {
                let names = (try? Self.toolNames(from: descriptor)) ?? []
                listed.value = names
            }
            agent?.push(agentTextChunk("네."))
            return .object(["stopReason": .string("end_turn")])
        }
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            invokeTool: { _, _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) },
            startAgent: { _, _ in FakeTransport(connection: agent.connection) }
        )

        _ = try await client.send(messages: [.user("hi")], tools: toolSpecs())

        XCTAssertEqual(listed.value, ["run_shell"], "code_editor is withheld; everything else is offered")
    }

    /// Synchronous on purpose: it is called from inside ScriptedAgent's reply
    /// closure, which is where the turn actually is.
    private static func toolNames(from descriptor: JSONValue) throws -> [String] {
        guard
            let url = descriptor["url"]?.stringValue.flatMap(URL.init(string:)),
            let header = descriptor["headers"]?.arrayValue?.first,
            let headerName = header["name"]?.stringValue,
            let headerValue = header["value"]?.stringValue
        else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(headerValue, forHTTPHeaderField: headerName)
        request.httpBody = try JSONEncoder().encode(JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": .number(1),
            "method": .string("tools/list"),
            "params": .object([:]),
        ]))
        request.timeoutInterval = 5

        let semaphore = DispatchSemaphore(value: 0)
        let body = UncheckedBox<Data?>(nil)
        URLSession(configuration: .ephemeral).dataTask(with: request) { data, _, _ in
            body.value = data
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 5)

        guard
            let data = body.value,
            let decoded = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return [] }
        return (decoded["result"]?["tools"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue }
    }

    /// The listener's lifetime is the turn's. A port left open between turns
    /// is a local service nobody knows is running.
    func test_send_closesTheMcpPortWhenTheTurnEnds() async throws {
        let agent = ScriptedAgent()
        agent.stubHandshake()
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(agentTextChunk("끝."))
            return .object(["stopReason": .string("end_turn")])
        }
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            invokeTool: { _, _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) },
            startAgent: { _, _ in FakeTransport(connection: agent.connection) }
        )

        _ = try await client.send(messages: [.user("hi")], tools: toolSpecs())

        let descriptor = try XCTUnwrap(agent.params(forMethod: "session/new")?["mcpServers"]?.arrayValue?.first)
        var request = URLRequest(url: try XCTUnwrap(URL(string: try XCTUnwrap(descriptor["url"]?.stringValue))))
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 3
        do {
            _ = try await URLSession(configuration: .ephemeral).data(for: request)
            XCTFail("the MCP port must not outlive the turn")
        } catch {
            // Connection refused.
        }
    }

    /// A turn that failed still has to close it -- this is the path a wedged
    /// or unauthenticated CLI takes.
    func test_send_closesTheMcpPortWhenTheTurnFails() async throws {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        agent.errorReplies["session/prompt"] = (code: -32000, message: "Authentication required")
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            invokeTool: { _, _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) },
            startAgent: { _, _ in FakeTransport(connection: agent.connection) }
        )

        do {
            _ = try await client.send(messages: [.user("hi")], tools: toolSpecs())
            XCTFail("the turn was supposed to fail")
        } catch {
            // Expected.
        }

        let descriptor = try XCTUnwrap(agent.params(forMethod: "session/new")?["mcpServers"]?.arrayValue?.first)
        var request = URLRequest(url: try XCTUnwrap(URL(string: try XCTUnwrap(descriptor["url"]?.stringValue))))
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 3
        do {
            _ = try await URLSession(configuration: .ephemeral).data(for: request)
            XCTFail("a failed turn must still close its port")
        } catch {
            // Connection refused.
        }
    }

    /// The MCP server now starts before the agent does, so the fast-fail for
    /// a CLI that is not installed has to survive it: still immediate, still
    /// the same sentence, and with nothing left listening.
    func test_send_stillFailsFastForAMissingCLI_andLeavesNoPortOpen() async {
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            invokeTool: { _, _, _ in DispatchedToolResult(ok: true, data: nil, error: nil, detail: nil) },
            startAgent: { _, _ in throw AcpAgentCommandError.vendorCLINotFound(.codex) }
        )

        let before = Date()
        do {
            _ = try await client.send(messages: [.user("hi")], tools: toolSpecs())
            XCTFail("a missing CLI must fail the turn")
        } catch {
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                String(format: Strings.text(.acpCLINotFoundFormat), "codex")
            )
        }
        XCTAssertLessThan(Date().timeIntervalSince(before), 5, "it must fail, not hang")
    }

    /// No host to run tools means no server to advertise -- and the prompt
    /// (asserted elsewhere) says so rather than naming tools that aren't there.
    func test_send_advertisesNoMcpServerWhenThereIsNoHostToRunTools() async throws {
        let agent = ScriptedAgent()
        agent.stubHandshake()
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(agentTextChunk("네."))
            return .object(["stopReason": .string("end_turn")])
        }
        let client = CodingAgentCLIClient(
            configuration: { cliConfiguration() },
            startAgent: { _, _ in FakeTransport(connection: agent.connection) }
        )

        _ = try await client.send(messages: [.user("hi")], tools: toolSpecs())

        XCTAssertEqual(agent.params(forMethod: "session/new")?["mcpServers"]?.arrayValue, [])
    }

    // MARK: - Permission

    /// Refusing this would deny the tool before it ever reached the host: the
    /// user would see no prompt at all and the model would be told it was
    /// refused. The real gate is one step further in, inside
    /// AgentRunner.invokeTool.
    func test_resolvePermission_allowsPucksOwnMcpTools() async {
        let request = AcpPermissionRequest(raw: .object([
            "toolCall": .object([
                "title": .string("mcp__puck__run_shell"),
                "rawInput": .object(["command": .string("ls")]),
            ]),
            "options": .array([
                .object(["optionId": .string("a"), "name": .string("Allow"), "kind": .string("allow_once")]),
                .object(["optionId": .string("r"), "name": .string("Reject"), "kind": .string("reject_once")]),
            ]),
        ]))

        let allowed = await CodingAgentCLIClient.resolvePermission(request)

        XCTAssertTrue(allowed)
    }

    /// The CLI's own tools keep the conservative refusal a chat turn has
    /// always given them -- nothing here approves a coding agent's shell.
    func test_resolvePermission_stillRefusesTheCLIsOwnTools() async {
        let request = AcpPermissionRequest(raw: .object([
            "toolCall": .object([
                "title": .string("Bash"),
                "rawInput": .object(["command": .string("rm -rf /")]),
            ]),
            "options": .array([
                .object(["optionId": .string("a"), "name": .string("Allow"), "kind": .string("allow_once")]),
            ]),
        ]))

        let allowed = await CodingAgentCLIClient.resolvePermission(request)

        XCTAssertFalse(allowed)
    }
}
