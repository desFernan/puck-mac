//
//  AgentHostTests.swift
//  PuckClientTests
//
//  The agent loop as this app wires it.
//
//  What is pinned here is what happens around a turn rather than inside one:
//  which chat a run's events are addressed to, that a run always ends, and
//  that the things a window does on its way out leave nothing behind. The
//  turn itself belongs to AgentRunner, which has its own tests and does not
//  need a second set through this.
//

import XCTest
@testable import PuckClient

final class AgentHostTests: XCTestCase {
    /// Everything the host puts on the socket, in order.
    ///
    /// A class rather than a captured array: `broadcast` is called from the
    /// run's own task as well as from main.
    private final class Wire: @unchecked Sendable {
        private let lock = NSLock()
        private var sent: [BridgeMessage] = []

        func broadcast(_ message: BridgeMessage) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            sent.append(message)
            return true
        }

        var messages: [BridgeMessage] {
            lock.lock()
            defer { lock.unlock() }
            return sent
        }

        var events: [(event: BridgeEvent, workspace: String?, session: String?)] {
            messages.compactMap { message in
                guard case .event(let event, let workspace, let session) = message else { return nil }
                return (event, workspace, session)
            }
        }

        var endings: [(event: BridgeEvent, workspace: String?, session: String?)] {
            events.filter {
                if case .agentDone = $0.event { return true }
                return false
            }
        }
    }

    /// A configuration with no credential in it, whatever is in the .env of
    /// the machine running this.
    private var unconfigured: AgentConfiguration {
        AgentConfiguration(apiKey: nil, model: "gpt-4o", provider: .openai, keySource: nil)
    }

    private func host(_ wire: Wire, configuration: AgentConfiguration? = nil) -> AgentHost {
        let resolved = configuration ?? unconfigured
        return AgentHost(
            broadcast: { wire.broadcast($0) },
            resolveProjectPath: { _ in nil },
            loadConfiguration: { resolved }
        )
    }

    /// A turn that cannot start still has to end. `agent_done` is the only
    /// thing that stops the transcript's spinner, so a run that returns
    /// without one leaves that chat running for the life of the app.
    @MainActor
    func test_aTurnWithNoCredentialEndsRatherThanHanging() {
        let wire = Wire()

        host(wire).run(command: "hello", workspaceId: "ws-1", sessionId: "chat-a")

        XCTAssertEqual(wire.endings.count, 1, "one ending, no more and no less")
        guard case .agentDone(let ok, _)? = wire.endings.first?.event else {
            return XCTFail("no agent_done")
        }
        XCTAssertFalse(ok)
    }

    /// Addressed to the chat that asked, not to whichever chat is active when
    /// the answer happens. Reading the active one is the guess that filed a
    /// superseded run's events under the wrong chat -- and an event nobody
    /// can route is an event that chat never hears, so its spinner stays.
    @MainActor
    func test_theEndingIsAddressedToTheChatThatAsked() {
        let wire = Wire()

        host(wire).run(command: "hello", workspaceId: "ws-1", sessionId: "chat-a")

        XCTAssertEqual(wire.endings.first?.workspace, "ws-1")
        XCTAssertEqual(wire.endings.first?.session, "chat-a")
    }

    /// The message is the whole of the help there is: an alert saying "check
    /// your configuration" would not say which file, and there are several
    /// it could be. It names the variable to set and every path searched.
    @MainActor
    func test_theMissingCredentialSaysWhichFileAndWhichVariable() {
        let wire = Wire()

        host(wire).run(command: "hello", workspaceId: "ws-1", sessionId: "chat-a")

        guard case .agentDone(_, let summary)? = wire.endings.first?.event else {
            return XCTFail("no agent_done")
        }
        XCTAssertTrue(summary.contains("OPENAI_API_KEY"), "got: \(summary)")
        for path in AgentConfiguration.defaultSearchPaths {
            XCTAssertTrue(
                summary.contains(path.appendingPathComponent(".env").path),
                "the search order is the answer to the question this message provokes"
            )
        }
    }

    /// One text chunk *and* a done event would print the same words twice --
    /// the transcript renders a failed run's summary itself.
    @MainActor
    func test_aFailedTurnSaysItOnceRatherThanTwice() {
        let wire = Wire()

        host(wire).run(command: "hello", workspaceId: "ws-1", sessionId: "chat-a")

        let chunks = wire.events.filter {
            if case .textChunk = $0.event { return true }
            return false
        }
        XCTAssertTrue(chunks.isEmpty, "the done row already renders the summary")
    }

    /// A provider that authenticates itself is configured with no credential
    /// of ours -- refusing to start it turns a working `claude` into an
    /// error message.
    @MainActor
    func test_aSelfAuthenticatingProviderIsNotRefused() {
        let wire = Wire()
        let cli = AgentConfiguration(apiKey: nil, model: "claude", provider: .cli, keySource: nil)

        host(wire, configuration: cli).run(command: "hello", workspaceId: "ws-1", sessionId: "chat-a")

        XCTAssertTrue(
            wire.endings.isEmpty,
            "a CLI turn starts; it does not end before it has begun"
        )
    }

    /// Answering an approval nobody is waiting on is what a window that has
    /// moved on does. It must be a no-op rather than a crash.
    @MainActor
    func test_answeringAnApprovalNobodyIsWaitingOnIsHarmless() {
        let wire = Wire()
        let host = host(wire)

        host.resolveApproval(id: "never-asked", approved: true)
        host.cancelPendingApprovals()
        host.forgetSession("chat-a")
        host.socketDisconnected()

        XCTAssertTrue(wire.messages.isEmpty, "none of this is news for the socket")
    }
}
