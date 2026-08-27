//
//  AgentCredentialStatusTests.swift
//  PuckTests
//
//  Whether a missing credential is a problem depends on who is being asked
//  to talk. Telling somebody their key is missing when the program they
//  selected has been logged in for months is telling them to fix something
//  that is not broken.
//

import XCTest
@testable import Puck

final class AgentCredentialStatusTests: XCTestCase {
    private func configuration(
        provider: AgentProvider,
        apiKey: String? = nil,
        keySource: AgentConfiguration.KeySource? = nil,
        codingAgent: CodingAgentKind = .claude
    ) -> AgentConfiguration {
        AgentConfiguration(
            apiKey: apiKey,
            model: "m",
            provider: provider,
            keySource: keySource,
            codingAgent: codingAgent
        )
    }

    func test_aFoundCredentialSaysWhereItCameFrom() {
        let source = AgentConfiguration.KeySource.environment(variable: "OPENAI_API_KEY")

        XCTAssertEqual(
            AgentCredentialStatus.resolved(for: configuration(provider: .openai, apiKey: "k", keySource: source)),
            .supplied(source)
        )
    }

    /// An API provider with no key cannot start a turn, and the panel has to
    /// say so.
    func test_anApiProviderWithNoKeyIsMissing() {
        XCTAssertEqual(AgentCredentialStatus.resolved(for: configuration(provider: .openai)), .missing)
        XCTAssertEqual(AgentCredentialStatus.resolved(for: configuration(provider: .anthropic)), .missing)
    }

    /// A coding CLI is a program the user has already logged into -- that is
    /// the whole reason to offer it as a provider. Refusing to start it
    /// because this app holds no token turns a working `claude` into an
    /// error message.
    func test_aCliWithNoTokenIsNotMissingAnything() {
        XCTAssertEqual(AgentCredentialStatus.resolved(for: configuration(provider: .cli)), .notNeeded)
    }

    /// A CLI *can* be handed a token, and then the panel says where it came
    /// from like any other.
    func test_aCliWithATokenSaysWhereItCameFrom() {
        let source = AgentConfiguration.KeySource.file(URL(fileURLWithPath: "/tmp/.env"))

        XCTAssertEqual(
            AgentCredentialStatus.resolved(for: configuration(provider: .cli, apiKey: "t", keySource: source)),
            .supplied(source)
        )
    }

    /// The two credentials are not the same thing and must not be labelled
    /// the same: one is this app's key for an API it calls, the other a token
    /// handed to a program that does its own talking.
    func test_theFieldIsNamedAfterWhatItIsFor() {
        XCTAssertEqual(
            AgentCredentialField.resolved(for: configuration(provider: .openai)),
            .apiKey(provider: .openai)
        )
        XCTAssertEqual(
            AgentCredentialField.resolved(for: configuration(provider: .cli, codingAgent: .codex)),
            .cliToken(agent: .codex)
        )
    }
}
