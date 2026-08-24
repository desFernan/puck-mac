//
//  ChatTitlerTests.swift
//  Puck
//
//  What comes back from a model asked for a title is a title *most* of the
//  time. These are the rest of the time.
//

import XCTest
@testable import Puck

private final class StubTitleClient: AgentLLMClient {
    var reply: String?
    var error: Error?
    private(set) var sends = 0
    private(set) var lastTools: [GPTToolSpec] = []

    init(reply: String?) { self.reply = reply }
    init(error: Error) { self.error = error }

    func send(messages: [GPTMessage], tools: [GPTToolSpec]) async throws -> GPTTurn {
        sends += 1
        lastTools = tools
        if let error { throw error }
        return GPTTurn(text: reply, toolCalls: [])
    }
}

private struct StubError: Error {}

final class ChatTitlerTests: XCTestCase {
    func test_aPlainTitle_comesBackAsItIs() async {
        let titler = ChatTitler(client: StubTitleClient(reply: "로그인 버그 재현"))

        let title = await titler.title(user: "로그인이 안 돼", reply: "재현 순서를 알려주세요")

        XCTAssertEqual(title, "로그인 버그 재현")
    }

    /// Naming a chat must not offer the model tools -- it is one question, and
    /// a tool call here would be answered by nobody.
    func test_theTitleCall_offersNoTools() async {
        let client = StubTitleClient(reply: "제목")
        _ = await ChatTitler(client: client).title(user: "a", reply: "b")

        XCTAssertEqual(client.sends, 1)
        XCTAssertTrue(client.lastTools.isEmpty)
    }

    func test_quotesAndTrailingPunctuation_areStripped() {
        XCTAssertEqual(ChatTitler.sanitised("\"고양이 산책\""), "고양이 산책")
        XCTAssertEqual(ChatTitler.sanitised("고양이 산책."), "고양이 산책")
        XCTAssertEqual(ChatTitler.sanitised("“고양이 산책”"), "고양이 산책")
    }

    func test_aLabelPrefix_isStripped() {
        XCTAssertEqual(ChatTitler.sanitised("제목: 고양이 산책"), "고양이 산책")
    }

    /// A colon that is part of the title itself is not a prefix. Only a short
    /// leading label counts, which is what the distance check is for.
    func test_aColonDeepInTheTitle_isLeftAlone() {
        XCTAssertEqual(ChatTitler.sanitised("빌드 실패: 링커 오류"), "빌드 실패: 링커 오류")
    }

    func test_aChattyMultiLineAnswer_keepsOnlyTheFirstRealLine() {
        XCTAssertEqual(ChatTitler.sanitised("\n\n고양이 산책\n\n이 제목이 좋겠어요!"), "고양이 산책")
    }

    func test_nothingUsable_isNil() {
        XCTAssertNil(ChatTitler.sanitised(nil))
        XCTAssertNil(ChatTitler.sanitised("   "))
        XCTAssertNil(ChatTitler.sanitised("\"\""))
    }

    /// A chat that could not be renamed keeps the name it already has; that is
    /// an outcome, not an error to propagate.
    func test_aFailedCall_yieldsNoTitle() async {
        let title = await ChatTitler(client: StubTitleClient(error: StubError())).title(user: "a", reply: "b")

        XCTAssertNil(title)
    }
}
