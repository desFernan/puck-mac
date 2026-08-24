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
