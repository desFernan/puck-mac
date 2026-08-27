//
//  AgentCredentialStatus.swift
//  Puck
//
//  What the settings panel has to say about the credential it found, and
//  which field it offers to change.
//
//  Both were written inline in the settings view, which is a SwiftUI form in
//  the app no test could reach -- so the one decision in them had none. That
//  decision is that a missing credential is only a problem where a turn needs
//  one: a coding CLI is a program the user has already logged into, and
//  telling them a key is missing there is telling them to fix something that
//  is not broken.
//
//  Language-free on purpose. The panel turns these into sentences; keeping
//  the choice and the wording apart is what lets the choice be asserted.
//

import Foundation

/// Where a turn's credential is coming from, or why there is not one.
enum AgentCredentialStatus: Equatable {
    /// Found, and where.
    case supplied(AgentConfiguration.KeySource)
    /// Not found, and a turn cannot start without it.
    case missing
    /// Not found, and that is the ordinary case -- the provider
    /// authenticates itself.
    case notNeeded

    static func resolved(for configuration: AgentConfiguration) -> AgentCredentialStatus {
        if let source = configuration.keySource { return .supplied(source) }
        return configuration.requiresCredential ? .missing : .notNeeded
    }
}

/// Which credential the field in front of the user is for.
///
/// The two are not the same thing and the panel must not call them the same
/// thing: one is this app's key for an API it calls, the other is a token
/// handed to a program that does its own talking.
enum AgentCredentialField: Equatable {
    case apiKey(provider: AgentProvider)
    case cliToken(agent: CodingAgentKind)

    static func resolved(for configuration: AgentConfiguration) -> AgentCredentialField {
        configuration.provider == .cli
            ? .cliToken(agent: configuration.codingAgent)
            : .apiKey(provider: configuration.provider)
    }
}
