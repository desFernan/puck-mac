//
//  ClientRelayTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//
//  Rewritten 2026-08-15: with workspace deleted, `gui` is the only role left
//  and the interesting question flipped. It used to be "which of the two roles
//  does this go to"; it is now "does this leave the process at all, or is it
//  answered where it lands".
//

import XCTest
@testable import Puck

final class ClientRelayTests: XCTestCase {
    func test_messagesTheAgentHostConsumes_targetGUI() {
        // user_input joined this list when workspace went away: it carries what
        // the user typed into the pet's bubble or spoke over push-to-talk, and
        // its consumer is whoever runs the agent -- PuckClient now. Left
        // pointing at workspace it would be relayed to nobody at all.
        XCTAssertEqual(ClientRelay.targetRole(for: .userInput(UserInput(text: "hi", source: .text))), .gui)
        XCTAssertEqual(ClientRelay.targetRole(for: .event(.agentThinking, workspaceId: "w1", sessionId: "s1")), .gui)
        XCTAssertEqual(
            ClientRelay.targetRole(for: .workspaceCreate(workspaceId: "w1", name: "cat house", projectPath: nil)),
            .gui
        )
        XCTAssertEqual(
            ClientRelay.targetRole(for: .sessionCreate(workspaceId: "w1", sessionId: "s1", title: "new chat", origin: .user)),
            .gui
        )
    }

    func test_locallyHandledMessages_haveNoTargetRole() {
        // Answered from the in-process WorkspaceRegistry (BridgeMessageRouter);
        // relaying them as well would mint a competing workspace id per click.
        XCTAssertNil(ClientRelay.targetRole(for: .workspaceCreateRequest(name: "cat house", projectPath: nil)))
        XCTAssertNil(ClientRelay.targetRole(for: .sessionCreateRequest(workspaceId: "w1", title: "new chat")))
        // Connection lifecycle and tool dispatch, as before.
        XCTAssertNil(ClientRelay.targetRole(for: .clientHello(role: .gui, token: BridgeHandshakeSecret.current())))
        XCTAssertNil(ClientRelay.targetRole(for: .toolDispatch(ToolDispatch(id: "t1", tool: "launch_app", args: .object([:])))))
        XCTAssertNil(ClientRelay.targetRole(for: .toolCancel(id: "t1")))
        XCTAssertNil(ClientRelay.targetRole(for: .toolResult(ToolResult(id: "t1", ok: true, data: nil, error: nil))))
    }
}

/// Every message the socket can carry, classified exactly once.
///
/// The point of the exhaustive switch below is that it does not compile when
/// a case is added to `BridgeMessage`: whoever adds one has to say here what
/// becomes of it, and `ClientRelay.disposition(for:)` has to agree. That was
/// the drift this file could not catch before -- three switches over one enum,
/// kept in step by comments.
final class ClientRelayDispositionTests: XCTestCase {
    /// One of every case. The switch is what keeps this list honest.
    private static func sample(_ message: BridgeMessage) -> BridgeMessage { message }

    private let everyCase: [BridgeMessage] = [
        .clientHello(role: .gui, token: "t"),
        .toolDispatch(ToolDispatch(id: "t1", tool: "launch_app", args: .object([:]))),
        .toolCancel(id: "t1"),
        .toolResult(ToolResult(id: "t1", ok: true, data: nil, error: nil)),
        .event(.agentThinking, workspaceId: "w1", sessionId: "s1"),
        .userInput(UserInput(text: "hi", source: .text)),
        .petHome(rect: nil, visible: false),
        .petIslandHeight(72),
        .voiceListen(true),
        .voiceListening(true),
        .workspaceCreateRequest(name: "w", projectPath: nil),
        .workspaceCreate(workspaceId: "w1", name: "w", projectPath: nil),
        .workspaceDeleteRequest(workspaceId: "w1"),
        .workspaceDelete(workspaceId: "w1"),
        .sessionCreateRequest(workspaceId: "w1", title: "t"),
        .sessionCreate(workspaceId: "w1", sessionId: "s1", title: "t", origin: .user),
    ]

    /// Fails to compile when a case is added, which is the whole point: the
    /// list above then has to grow with it.
    func test_theSampleListCoversEveryCase() {
        for message in everyCase {
            switch message {
            case .clientHello, .toolDispatch, .toolCancel, .toolResult, .event, .userInput,
                 .petHome, .petIslandHeight, .voiceListen, .voiceListening,
                 .workspaceCreateRequest, .workspaceCreate, .workspaceDeleteRequest,
                 .workspaceDelete, .sessionCreateRequest, .sessionCreate:
                continue
            }
        }
        XCTAssertEqual(everyCase.count, 16, "a new case needs a sample above")
    }

    /// Relayed or answered here, never both and never neither.
    func test_everyCaseIsRelayedOrAnsweredHereButNotBoth() {
        for message in everyCase {
            let disposition = ClientRelay.disposition(for: message)
            let role = ClientRelay.targetRole(for: message)
            switch disposition {
            case .relay(let expected):
                XCTAssertEqual(role, expected, "\(message) is relayed, so it has a role")
            case .handledInProcess, .noReader:
                XCTAssertNil(role, "\(message) is answered here, so nothing forwards it")
            }
        }
    }

    /// The two halves of the tool exchange stay in this process: pet-app is
    /// one end of each itself, so a relay would be a message to nobody.
    func test_theToolExchangeNeverLeavesTheProcess() {
        XCTAssertEqual(
            ClientRelay.disposition(for: .toolDispatch(ToolDispatch(id: "t", tool: "launch_app", args: .object([:])))),
            .handledInProcess
        )
        XCTAssertEqual(ClientRelay.disposition(for: .toolCancel(id: "t")), .handledInProcess)
    }
}
