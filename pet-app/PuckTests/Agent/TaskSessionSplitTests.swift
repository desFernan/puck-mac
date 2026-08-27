//
//  TaskSessionSplitTests.swift
//  PuckTests
//
//  open_task_session moves the rest of a run into a new chat. What the chat
//  it branched out of is left holding.
//
//  A conversation whose assistant message asks for tools is only valid once
//  every one of those calls has a reply. Neither provider tolerates a gap --
//  OpenAI answers "must be followed by tool messages", Anthropic "tool_use
//  ids found without tool_result" -- and they reject the whole conversation
//  rather than that one turn, so a chat left in that shape rejects every
//  message typed in it from then on.
//

import XCTest
@testable import Puck

final class TaskSessionSplitTests: XCTestCase {
    /// Answers one turn with the given calls, then finishes.
    private final class ScriptedClient: AgentLLMClient, @unchecked Sendable {
        var turns: [GPTTurn]
        /// Every message stack it was asked to send, per session.
        private(set) var stacks: [(session: String?, messages: [GPTMessage])] = []

        init(turns: [GPTTurn]) { self.turns = turns }

        func send(messages: [GPTMessage], tools: [GPTToolSpec], sessionId: String?) async throws -> GPTTurn {
            stacks.append((sessionId, messages))
            return turns.isEmpty ? GPTTurn(text: "done", toolCalls: []) : turns.removeFirst()
        }
    }

    private func call(_ id: String, _ name: String, _ json: String) -> GPTToolCall {
        GPTToolCall(id: id, name: name, argumentsJSON: json)
    }

    /// The model can ask for several tools in one turn, and open_task_session
    /// can be one of them. The rest of the run then belongs to the new chat --
    /// but the calls it was asked for alongside were asked for in the chat it
    /// left, and that chat is deliberately kept (the casual session is what
    /// this tool is documented to branch out of).
    func test_theChatItBranchedOutOfIsLeftWithNoUnansweredCall() async {
        let client = ScriptedClient(turns: [
            GPTTurn(
                text: nil,
                toolCalls: [
                    call("c-1", "open_task_session", #"{"title":"the task","brief":"b"}"#),
                    call("c-2", "launch_app", #"{"app_name":"Weather"}"#),
                ]
            )
        ])
        let runner = AgentRunner(
            client: client,
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, _ in true },
            permissions: { .toolsOnly },
            emit: { _, _ in },
            // Stated because the runner drops the opener without it: the tool
            // is offered only alongside code_editor, since with nowhere to
            // delegate to there is no long-running work to branch out.
            delegateCodeEditor: { _ in .succeeded(detail: nil) },
            openTaskSession: { _, _ in "task-session" }
        )

        await runner.run(command: "do the thing", session: "casual")
        // A second turn in the chat it left, which is what a person typing
        // there next does. Its stack is what the provider would be sent.
        await runner.run(command: "and another thing", session: "casual")

        let sent = client.stacks.compactMap { $0.session == "casual" ? $0.messages : nil }.last ?? []
        assertEveryToolCallIsAnswered(in: sent)
    }

    /// The same question asked of the chat the run moved into.
    func test_theChatItMovedIntoIsAlsoComplete() async {
        let client = ScriptedClient(turns: [
            GPTTurn(
                text: nil,
                toolCalls: [
                    call("c-1", "open_task_session", #"{"title":"the task","brief":"b"}"#),
                    call("c-2", "launch_app", #"{"app_name":"Weather"}"#),
                ]
            )
        ])
        let runner = AgentRunner(
            client: client,
            dispatcher: PetToolDispatcher(send: { _ in false }),
            approve: { _, _ in true },
            permissions: { .toolsOnly },
            emit: { _, _ in },
            // Stated because the runner drops the opener without it: the tool
            // is offered only alongside code_editor, since with nowhere to
            // delegate to there is no long-running work to branch out.
            delegateCodeEditor: { _ in .succeeded(detail: nil) },
            openTaskSession: { _, _ in "task-session" }
        )

        await runner.run(command: "do the thing", session: "casual")

        let sent = client.stacks.compactMap { $0.session == "task-session" ? $0.messages : nil }.last ?? []
        assertEveryToolCallIsAnswered(in: sent)
    }

    /// Every id an assistant message asked for has a tool message answering
    /// it, and no tool message answers an id nobody asked for.
    private func assertEveryToolCallIsAnswered(
        in messages: [GPTMessage],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var asked: Set<String> = []
        var answered: Set<String> = []
        for message in messages {
            switch message {
            case .assistant(_, let calls, _): asked.formUnion(calls.map(\.id))
            case .tool(let callId, _): answered.insert(callId)
            default: break
            }
        }
        XCTAssertFalse(asked.isEmpty, "the stack under test has to actually contain a tool call", file: file, line: line)
        XCTAssertEqual(
            asked.subtracting(answered), [],
            "a tool_use with no result: every future message in this chat is rejected",
            file: file, line: line
        )
        XCTAssertEqual(
            answered.subtracting(asked), [],
            "a tool result answering nothing is rejected the same way",
            file: file, line: line
        )
    }
}
