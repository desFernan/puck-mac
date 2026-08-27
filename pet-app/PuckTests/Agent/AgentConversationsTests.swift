//
//  AgentConversationsTests.swift
//  PuckTests
//
//  What the model has been told, per chat -- and what trimming is allowed to
//  throw away.
//
//  The trimming rules are the reason this is worth its own test. Both were
//  written against failures that reach the user as an unexplained API error
//  partway through a conversation that had been working, and neither could be
//  reached through a runner without driving sixty turns to get there.
//

import XCTest
@testable import Puck

final class AgentConversationsTests: XCTestCase {
    private func store() -> AgentConversations {
        AgentConversations(systemPrompt: "the prompt")
    }

    /// A chat that has said nothing is the system prompt and nothing else.
    func test_aNewChatStartsWithThePromptAlone() {
        let conversations = store()

        let messages = conversations.messages(in: "chat")

        XCTAssertEqual(messages.count, 1)
        guard case .system(let text) = messages[0] else { return XCTFail("not a system line") }
        XCTAssertEqual(text, "the prompt")
    }

    /// One runner serves every chat. Without keeping them apart they would
    /// share one context and the model would answer a question from the chat
    /// next door.
    func test_chatsDoNotSeeEachOther() {
        let conversations = store()

        conversations.append(.user("in chat a"), to: "a")

        XCTAssertEqual(conversations.messages(in: "a").count, 2)
        XCTAssertEqual(conversations.messages(in: "b").count, 1)
    }

    /// Under the cap, nothing is thrown away.
    func test_aShortChatIsLeftAlone() {
        let conversations = store()
        for index in 0..<10 { conversations.append(.user("\(index)"), to: "chat") }

        conversations.trim("chat")

        XCTAssertEqual(conversations.messages(in: "chat").count, 11)
    }

    /// System lines are kept whatever their age: there are a handful of them
    /// -- the prompt, and one per workspace the chat has seen -- and losing
    /// one silently un-tells the model something it was told once.
    func test_trimmingKeepsEverySystemLineHoweverOld() {
        let conversations = store()
        conversations.append(.system("workspace one"), to: "chat")
        for index in 0..<200 { conversations.append(.user("\(index)"), to: "chat") }
        conversations.append(.system("workspace two"), to: "chat")

        conversations.trim("chat")

        let systems = conversations.messages(in: "chat").compactMap { message -> String? in
            guard case .system(let text) = message else { return nil }
            return text
        }
        XCTAssertEqual(systems, ["the prompt", "workspace one", "workspace two"])
    }

    /// And it actually trims, to the cap.
    func test_trimmingCutsToTheCap() {
        let conversations = store()
        for index in 0..<200 { conversations.append(.user("\(index)"), to: "chat") }

        conversations.trim("chat")

        let kept = conversations.messages(in: "chat").filter {
            if case .system = $0 { return false }
            return true
        }
        XCTAssertEqual(kept.count, AgentConversations.maximumMessages)
    }

    /// The head of what is kept is never a tool result: the API rejects a
    /// conversation whose first tool result has no assistant tool_calls
    /// message above it, and it rejects the whole thing rather than that one
    /// turn -- so a chat that crosses the cap at the wrong moment stops
    /// working entirely.
    ///
    /// The cut has to be made to land on one. `trim` keeps the last
    /// `maximumMessages`, so the message at `count - maximumMessages` is the
    /// head, and this places a tool result exactly there: six messages before
    /// it and `maximumMessages - 1` after.
    func test_trimmingNeverLeavesAToolResultAtTheTop() {
        let conversations = store()
        for index in 0..<5 { conversations.append(.user("before \(index)"), to: "chat") }
        conversations.append(.assistant(text: nil, toolCalls: [], reasoning: nil), to: "chat")
        conversations.append(.tool(callId: "the-head", content: "result"), to: "chat")
        for index in 0..<(AgentConversations.maximumMessages - 1) {
            conversations.append(.user("after \(index)"), to: "chat")
        }

        conversations.trim("chat")

        let kept = conversations.messages(in: "chat").filter {
            if case .system = $0 { return false }
            return true
        }
        XCTAssertEqual(kept.count, AgentConversations.maximumMessages - 1, "the orphan is dropped, not kept")
        if case .tool = kept.first {
            XCTFail("a tool result with no call above it is a conversation the API rejects whole")
        }
    }

    /// The one case where a new chat is a continuation rather than a
    /// beginning: the agent branching its work into a task session.
    func test_aTaskSessionInheritsTheChatItBranchedFrom() {
        let conversations = store()
        conversations.append(.user("the question"), to: "source")

        conversations.carry(from: "source", to: "task")

        XCTAssertEqual(conversations.messages(in: "task").count, 2)
    }

    /// Carrying from a chat that has said nothing leaves the destination
    /// alone rather than blanking it.
    func test_carryingFromAnEmptyChatIsANoOp() {
        let conversations = store()
        conversations.append(.user("already here"), to: "task")

        conversations.carry(from: "never-spoke", to: "task")

        XCTAssertEqual(conversations.messages(in: "task").count, 2)
    }

    /// The user threw the chat away; the model should not still be holding it.
    func test_aForgottenChatIsGone() {
        let conversations = store()
        conversations.append(.user("something"), to: "chat")

        conversations.forget("chat")

        XCTAssertEqual(conversations.messages(in: "chat").count, 1)
    }

    /// A workspace is announced once per chat, or a ten-turn conversation
    /// accumulates ten identical system lines.
    func test_aWorkspaceIsAnnouncedOncePerChat() {
        let conversations = store()
        let context = AgentRunner.WorkspaceContext(name: "ws", projectPath: nil)

        XCTAssertTrue(conversations.markAnnounced(context, to: "a"))
        XCTAssertFalse(conversations.markAnnounced(context, to: "a"))
        XCTAssertTrue(conversations.markAnnounced(context, to: "b"), "a different chat has not heard it")
    }

    /// A chat that moves to another workspace hears about that one -- which a
    /// single shared value did not do.
    func test_aChangedWorkspaceIsAnnouncedAgain() {
        let conversations = store()
        let first = AgentRunner.WorkspaceContext(name: "one", projectPath: nil)
        let second = AgentRunner.WorkspaceContext(name: "two", projectPath: nil)

        XCTAssertTrue(conversations.markAnnounced(first, to: "chat"))
        XCTAssertTrue(conversations.markAnnounced(second, to: "chat"))
    }

    /// Reached from a run's own executor, from the window on main, and from a
    /// run being replaced that has not noticed yet.
    func test_itSurvivesEveryThreadAtOnce() {
        let conversations = store()

        DispatchQueue.concurrentPerform(iterations: 64) { index in
            let key = "chat-\(index % 4)"
            conversations.append(.user("\(index)"), to: key)
            _ = conversations.messages(in: key)
            conversations.trim(key)
        }

        let total = (0..<4).reduce(0) { $0 + conversations.messages(in: "chat-\($1)").count }
        XCTAssertEqual(total, 64 + 4, "every message landed, in one chat or another")
    }
}
