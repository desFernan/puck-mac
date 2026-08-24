//
//  RoutingAgentLLMClientTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Proves a provider switch in Settings takes effect on the very next `send`
//  without reconstructing `AgentRunner`/`AgentHost` -- the property
//  `makeAgentLLMClient`'s doc comment promises now that provider selection
//  happens per request instead of once at `AgentHost.init`.
//

import XCTest
@testable import Puck

final class RoutingAgentLLMClientTests: XCTestCase {

    func test_send_routesToOpenAI_thenToAnthropic_afterProviderChanges_withoutRebuildingClient() async throws {
        let openAI = SpyAgentLLMClient(name: "openai")
        let anthropic = SpyAgentLLMClient(name: "anthropic")
        let cli = SpyAgentLLMClient(name: "cli")
        var provider = AgentProvider.openai

        let router = RoutingAgentLLMClient(
            configuration: {
                AgentConfiguration(apiKey: "key", model: "m", provider: provider, keySource: nil)
            },
            openAIClient: openAI,
            anthropicClient: anthropic,
            cliClient: cli
        )

        _ = try await router.send(messages: [.user("first")], tools: [])
        XCTAssertEqual(openAI.receivedMessageCounts, [1])
        XCTAssertEqual(anthropic.receivedMessageCounts, [])

        // Flip the provider the same way Settings does -- through the
        // closure's next read, not a new AgentConfiguration captured once.
        provider = .anthropic
        _ = try await router.send(messages: [.user("second")], tools: [])

        XCTAssertEqual(openAI.receivedMessageCounts, [1], "the OpenAI client must not see the post-switch turn")
        XCTAssertEqual(anthropic.receivedMessageCounts, [1], "the switch must take effect on the very next send")
    }

    /// The CLI provider is reached the same way, and only when selected --
    /// routing a turn there by accident would spawn a node process and a
    /// ~256MB vendor binary for a request that should have been an HTTP call.
    func test_send_routesToTheCliClient_onlyWhileTheCliProviderIsSelected() async throws {
        let openAI = SpyAgentLLMClient(name: "openai")
        let anthropic = SpyAgentLLMClient(name: "anthropic")
        let cli = SpyAgentLLMClient(name: "cli")
        var provider = AgentProvider.cli

        let router = RoutingAgentLLMClient(
            configuration: {
                AgentConfiguration(apiKey: nil, model: "", provider: provider, keySource: nil)
            },
            openAIClient: openAI,
            anthropicClient: anthropic,
            cliClient: cli
        )

        let turn = try await router.send(messages: [.user("안녕")], tools: [])
        XCTAssertEqual(turn.text, "cli")
        XCTAssertEqual(cli.receivedMessageCounts, [1])
        XCTAssertEqual(openAI.receivedMessageCounts, [])
        XCTAssertEqual(anthropic.receivedMessageCounts, [])

        provider = .openai
        _ = try await router.send(messages: [.user("그 다음")], tools: [])

        XCTAssertEqual(cli.receivedMessageCounts, [1], "no CLI process may be spawned for another provider's turn")
        XCTAssertEqual(openAI.receivedMessageCounts, [1])
    }
}

private final class SpyAgentLLMClient: AgentLLMClient {
    let name: String
    private(set) var receivedMessageCounts: [Int] = []

    init(name: String) {
        self.name = name
    }

    func send(messages: [GPTMessage], tools: [GPTToolSpec]) async throws -> GPTTurn {
        receivedMessageCounts.append(messages.count)
        return GPTTurn(text: name, toolCalls: [])
    }
}
