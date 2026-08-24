//
//  AcpTurnSessionTests.swift
//  PuckTests
//
//  The handshake both callers share, tested on its own now that there are two
//  of them. AcpCodeEditorSessionTests covers the same ground through the
//  code_editor result mapping; these assert the outcomes the CLI-backed chat
//  client reads directly, which that mapping flattens away.
//

import XCTest
@testable import Puck

final class AcpTurnSessionTests: XCTestCase {

    func test_run_completesWithTheAccumulatedTextAndStopReason() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        agent.replies["session/prompt"] = { [weak agent] _ in
            agent?.push(chunk("안녕"))
            agent?.push(chunk("하세요"))
            return .object(["stopReason": .string("end_turn")])
        }
        let session = AcpTurnSession(connection: agent.connection, cwd: "/tmp/x")

        let outcome = await session.run(prompt: "hi")

        XCTAssertEqual(outcome, .completed(.init(stopReason: "end_turn", text: "안녕하세요")))
        XCTAssertEqual(agent.methodsWritten(), ["initialize", "session/new", "session/prompt"])
    }

    /// `cwd` is the caller's, not a fixed one: code_editor opens on the
    /// project, a chat turn on whatever workspace is active.
    func test_run_opensTheSessionOnTheGivenDirectory() async {
        let agent = ScriptedAgent()
        agent.stubHandshake()
        let session = AcpTurnSession(connection: agent.connection, cwd: "/tmp/elsewhere")

        _ = await session.run(prompt: "hi")

        XCTAssertEqual(agent.params(forMethod: "session/new")?["cwd"]?.stringValue, "/tmp/elsewhere")
    }

    /// An empty turn is a *completion* here, not a failure -- each caller
    /// decides what "the agent said nothing" means for it. code_editor falls
    /// back to the stop reason; the chat client refuses to show an empty
    /// bubble.
    func test_run_completesWithEmptyTextWhenTheAgentSaidNothing() async {
        let agent = ScriptedAgent()
        agent.stubHandshake(stopReason: "max_tokens")
        let session = AcpTurnSession(connection: agent.connection, cwd: "/tmp/x")

        let outcome = await session.run(prompt: "hi")

        XCTAssertEqual(outcome, .completed(.init(stopReason: "max_tokens", text: "")))
    }

    func test_run_reportsASessionNewThatAnsweredWithoutASessionId() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object([:]) }
        let session = AcpTurnSession(connection: agent.connection, cwd: "/tmp/x")

        let outcome = await session.run(prompt: "hi")

        XCTAssertEqual(outcome, .failed(.noSessionID))
    }

    func test_run_reportsCancellationRatherThanAFailure() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        var session: AcpTurnSession?
        agent.replies["session/prompt"] = { _ in
            session?.cancel()
            return .object(["stopReason": .string("cancelled")])
        }
        session = AcpTurnSession(connection: agent.connection, cwd: "/tmp/x")

        let outcome = await session!.run(prompt: "hi")

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(agent.params(forMethod: "session/cancel")?["sessionId"]?.stringValue, "s-1")
    }

    /// The failure text is built here, once, because the stderr tail that
    /// explains an ACP error is held here -- a caller cannot reconstruct it.
    func test_run_buildsTheFailureTextFromTheAcpErrorAndTheStderrTail() async {
        let agent = ScriptedAgent()
        agent.replies["initialize"] = { _ in .object(["protocolVersion": .number(1)]) }
        agent.replies["session/new"] = { _ in .object(["sessionId": .string("s-1")]) }
        agent.errorReplies["session/prompt"] = (code: -32000, message: "Authentication required")
        let session = AcpTurnSession(
            connection: agent.connection,
            cwd: "/tmp/x",
            stderrTail: { "claude: Not logged in." }
        )

        let outcome = await session.run(prompt: "hi")

        XCTAssertEqual(
            outcome,
            .failed(.detail("ACP error -32000: Authentication required\nclaude: Not logged in."))
        )
    }
}

private func chunk(_ text: String) -> JSONValue {
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
