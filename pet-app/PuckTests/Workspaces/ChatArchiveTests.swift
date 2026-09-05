//
//  ChatArchiveTests.swift
//  PuckTests
//
//  Chats survive being quit.
//
//  They did not, for as long as this app has existed: workspaces were written
//  to disk and the conversations inside them lived only as long as the
//  process, so every launch opened onto a sidebar of projects with nothing
//  said in any of them.
//

import XCTest
@testable import Puck

final class ChatArchiveTests: XCTestCase {
    private var storageURL: URL!

    override func setUpWithError() throws {
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("chats.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
    }

    private func archive() -> ChatArchive {
        ChatArchive(storageURL: storageURL)
    }

    private func session(
        id: String = "s1",
        workspaceId: String = "w1",
        title: String = "제목"
    ) -> ChatSession {
        ChatSession(id: id, workspaceId: workspaceId, title: title, origin: .user)
    }

    // MARK: - The round trip

    func test_aConversationComesBack() {
        let chat = session()
        chat.appendUserMessage("파일 좀 봐줘")
        chat.apply(.textChunk(text: "볼게요"))
        chat.apply(.toolCall(id: "t1", tool: "read_file", args: .object(["path": .string("a.swift")]), detail: nil))
        chat.apply(.toolResult(id: "t1", ok: true, data: .string("전체 파일 내용"), error: nil, detail: nil))
        chat.apply(.agentDone(ok: true, summary: "끝"))

        archive().save([chat], knownWorkspaceIds: ["w1"])
        let restored = archive().load()

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, "s1")
        XCTAssertEqual(restored.first?.workspaceId, "w1")
        XCTAssertEqual(restored.first?.timeline.count, chat.timeline.count)
        guard case .userMessage(_, let text)? = restored.first?.timeline.first else {
            return XCTFail("the first thing said is gone")
        }
        XCTAssertEqual(text, "파일 좀 봐줘")
    }

    /// The title a chat earned from its first message, and the fact that the
    /// app is the one that gave it. Re-deriving `isAutoTitled` from the title
    /// would say "no" for a chat that had been auto-named, which is how a
    /// restored chat would refuse the topic title it was still owed.
    func test_aRestoredChatKeepsHowItWasNamed() {
        let chat = session(title: ChatSession.placeholderTitle)
        chat.appendUserMessage("첫 질문")
        XCTAssertTrue(chat.isAutoTitled)

        archive().save([chat], knownWorkspaceIds: ["w1"])
        let restored = archive().load().first

        XCTAssertEqual(restored?.title, "첫 질문")
        XCTAssertEqual(restored?.isAutoTitled, true)
        XCTAssertEqual(restored?.hasTopicTitle, false)
    }

    /// A tool result's captured output is the only unbounded thing in a
    /// transcript and nothing draws it, so it is not written down. The row
    /// itself is -- what ran, and whether it worked.
    func test_theToolOutputIsNotKeptButTheCallIs() {
        let chat = session()
        chat.apply(.toolCall(id: "t1", tool: "run_shell", args: .object(["command": .string("ls")]), detail: nil))
        chat.apply(.toolResult(id: "t1", ok: false, data: .string(String(repeating: "x", count: 100_000)), error: .executionFailed, detail: "터졌어요"))

        archive().save([chat], knownWorkspaceIds: ["w1"])
        let restored = archive().load().first

        guard case .toolCall(let id, let tool, let args)? = restored?.timeline.first else {
            return XCTFail("the call is gone")
        }
        XCTAssertEqual(id, "t1")
        XCTAssertEqual(tool, "run_shell")
        XCTAssertEqual(args, .object(["command": .string("ls")]))
        guard case .toolResult(_, let ok, let data, let error, let detail)? = restored?.timeline.last else {
            return XCTFail("the result is gone")
        }
        XCTAssertFalse(ok)
        XCTAssertNil(data, "the captured output is deliberately dropped")
        XCTAssertEqual(error, .executionFailed)
        XCTAssertEqual(detail, "터졌어요")
        let size = (try? Data(contentsOf: storageURL))?.count ?? 0
        XCTAssertLessThan(size, 10_000, "the file must not carry a command's whole output")
    }

    /// A run and an approval belong to a process that has gone.
    func test_nothingComesBackStillRunningOrStillWaiting() {
        let chat = session()
        chat.apply(.awaitApproval(summary: "rm -rf 해도 될까요", approvalId: "a1"))
        chat.markWaitingForAgent()
        XCTAssertTrue(chat.isRunning)
        XCTAssertNotNil(chat.pendingApproval)

        archive().save([chat], knownWorkspaceIds: ["w1"])
        let restored = archive().load().first

        XCTAssertEqual(restored?.isRunning, false, "a restored spinner would never stop")
        XCTAssertNil(restored?.pendingApproval, "a restored banner has nothing left to answer it")
        XCTAssertEqual(restored?.approvalState(for: "a1"), .resolved)
        // The row itself stays: that the agent asked is part of the history.
        XCTAssertTrue(restored?.timeline.contains { entry in
            if case .approvalRequested = entry { return true }
            return false
        } ?? false)
    }

    /// The sidebar draws chats under their workspace, so one whose workspace
    /// has gone is unreachable -- keeping it would grow the file forever with
    /// rows nothing can show.
    func test_chatsUnderADeletedWorkspaceAreNotKept() {
        let kept = session(id: "s1", workspaceId: "w1")
        let orphan = session(id: "s2", workspaceId: "gone")

        archive().save([kept, orphan], knownWorkspaceIds: ["w1"])

        XCTAssertEqual(archive().load().map(\.id), ["s1"])
    }

    /// A transcript grows without limit and this file is read whole at
    /// launch, so the oldest rows go.
    func test_aVeryLongChatIsCappedFromTheOldestEnd() {
        let chat = session()
        for index in 0..<(ChatArchive.maximumEntriesPerSession + 50) {
            chat.appendUserMessage("\(index)")
        }

        archive().save([chat], knownWorkspaceIds: ["w1"])
        let restored = archive().load().first

        XCTAssertEqual(restored?.timeline.count, ChatArchive.maximumEntriesPerSession)
        guard case .userMessage(_, let first)? = restored?.timeline.first else {
            return XCTFail("nothing kept")
        }
        XCTAssertEqual(first, "50", "the newest end is the one worth keeping")
    }

    // MARK: - When the file is not what we expect

    func test_noFileYetIsNotAFailure() {
        XCTAssertEqual(archive().load().count, 0)
    }

    /// A store we merely failed to parse is the only copy of everything the
    /// user said, so it is moved aside rather than written over.
    func test_anUnreadableStoreIsKeptBesideTheNewOne() throws {
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("이건 JSON이 아니에요".utf8).write(to: storageURL)

        let store = archive()
        XCTAssertEqual(store.load().count, 0)
        store.save([session()], knownWorkspaceIds: ["w1"])

        let directory = storageURL.deletingLastPathComponent()
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(
            names.contains { $0.hasPrefix("chats.json.unreadable-") },
            "the store that could not be read was written over: \(names)"
        )
        XCTAssertEqual(archive().load().count, 1)
    }

    // MARK: - What the model is told afterwards

    /// A restored chat can be carried on: the model is handed what was said
    /// in it, so it is not answering in front of a transcript it has never
    /// seen.
    func test_whatTheModelIsToldAboutARestoredChat() {
        let chat = session()
        chat.appendUserMessage("무슨 파일이야")
        chat.apply(.toolCall(id: "t1", tool: "read_file", args: nil, detail: nil))
        chat.apply(.toolResult(id: "t1", ok: true, data: nil, error: nil, detail: nil))
        chat.apply(.textChunk(text: "설정 파일이에요"))

        let history = chat.spokenHistory

        XCTAssertEqual(history.count, 2, "tool calls are deliberately left out")
        XCTAssertTrue(history[0].isUser)
        XCTAssertEqual(history[0].text, "무슨 파일이야")
        XCTAssertFalse(history[1].isUser)
        XCTAssertEqual(history[1].text, "설정 파일이에요")
    }

    /// Only ever a seed. A chat this process has already talked in must not
    /// have a restored copy of itself pushed underneath what it just said.
    func test_theSeedOnlyLandsInAChatWithNoConversation() {
        let conversations = AgentConversations(systemPrompt: "시스템")

        XCTAssertTrue(conversations.seedIfEmpty([(true, "예전 질문")], to: "s1"))
        XCTAssertEqual(conversations.messages(in: "s1").count, 2)

        XCTAssertFalse(
            conversations.seedIfEmpty([(true, "또 예전 질문")], to: "s1"),
            "a chat that already has a conversation is not seeded again"
        )
        XCTAssertEqual(conversations.messages(in: "s1").count, 2)
    }
}
