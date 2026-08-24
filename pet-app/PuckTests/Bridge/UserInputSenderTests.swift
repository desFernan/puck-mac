//
//  UserInputSenderTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  AppDelegate cached the last BridgeConnection it saw and never cleared it,
//  so after workspace disconnected the app still believed it was connected,
//  sent user_input into a dead socket, and silently dropped it — the
//  "워크스페이스 꺼져있음" bubble F6 calls for could never appear. Delivery is
//  now decided against live connection state and reported back to the caller.
//

import XCTest
@testable import Puck

private final class StubTransport: UserInputTransport {
    var hasConnectedClients: Bool
    /// Simulates a client disconnecting between the hasConnectedClients check
    /// and the broadcast() call actually reaching a live connection.
    var broadcastSucceeds = true
    private(set) var broadcasted: [BridgeMessage] = []

    init(hasConnectedClients: Bool) {
        self.hasConnectedClients = hasConnectedClients
    }

    @discardableResult
    func broadcast(_ message: BridgeMessage) -> Bool {
        broadcasted.append(message)
        return broadcastSucceeds
    }
}

final class UserInputSenderTests: XCTestCase {
    func test_withConnectedClient_broadcastsUserInputAndReportsSent() {
        let transport = StubTransport(hasConnectedClients: true)
        let sender = UserInputSender { transport }

        let delivery = sender.send(text: "테스트 돌려줘", source: .voice)

        XCTAssertEqual(delivery, .sent)
        XCTAssertEqual(
            transport.broadcasted,
            [.userInput(UserInput(text: "테스트 돌려줘", source: .voice))]
        )
    }

    func test_withNoConnectedClient_reportsDisconnectedAndSendsNothing() {
        let transport = StubTransport(hasConnectedClients: false)
        let sender = UserInputSender { transport }

        let delivery = sender.send(text: "README 열어줘", source: .text)

        XCTAssertEqual(delivery, .notDelivered)
        XCTAssertTrue(transport.broadcasted.isEmpty, "must not write into a socket with no client")
    }

    /// BridgeServer is nil when it failed to start at all (independence
    /// principle: pet-app still runs as a pure pet). That is the same
    /// user-visible situation as no client being connected.
    func test_withNoTransportAtAll_reportsDisconnected() {
        let sender = UserInputSender { nil }

        XCTAssertEqual(sender.send(text: "안녕", source: .text), .notDelivered)
    }

    /// TOCTOU: hasConnectedClients can be true at the check but the client
    /// can vanish (BridgeConnection.onClose racing in on BridgeServer's own
    /// queue) before broadcast() actually reaches it. Delivery must reflect
    /// what broadcast() itself reports, not the earlier snapshot.
    func test_whenClientDisconnectsBetweenCheckAndBroadcast_reportsDisconnected() {
        let transport = StubTransport(hasConnectedClients: true)
        transport.broadcastSucceeds = false
        let sender = UserInputSender { transport }

        let delivery = sender.send(text: "테스트 돌려줘", source: .voice)

        XCTAssertEqual(delivery, .notDelivered)
    }

    /// The transport is consulted per send, not captured once — a client that
    /// disconnects between two sends must flip the result.
    func test_transportStateIsReReadOnEverySend() {
        let transport = StubTransport(hasConnectedClients: true)
        let sender = UserInputSender { transport }

        XCTAssertEqual(sender.send(text: "first", source: .text), .sent)

        transport.hasConnectedClients = false
        XCTAssertEqual(sender.send(text: "second", source: .text), .notDelivered)
        XCTAssertEqual(transport.broadcasted.count, 1, "the second send must not have gone out")
    }

    // MARK: - F13 (2026-07-29): workspace_id/session_id on user_input, and the
    // new session/workspace/approval/cancel messages -- same delivery
    // semantics as plain user_input, reusing the same transport check.

    func test_send_withWorkspaceAndSessionIds_includesThemOnUserInput() {
        let transport = StubTransport(hasConnectedClients: true)
        let sender = UserInputSender { transport }

        let delivery = sender.send(text: "look at this", source: .text, workspaceId: "w1", sessionId: "s2")

        XCTAssertEqual(delivery, .sent)
        XCTAssertEqual(
            transport.broadcasted,
            [.userInput(UserInput(text: "look at this", source: .text, workspaceId: "w1", sessionId: "s2"))]
        )
    }

    func test_createWorkspace_broadcastsWorkspaceCreateRequest() {
        let transport = StubTransport(hasConnectedClients: true)
        let sender = UserInputSender { transport }

        XCTAssertEqual(sender.createWorkspace(name: "cat house", projectPath: "/tmp/cat-house"), .sent)
        XCTAssertEqual(transport.broadcasted, [.workspaceCreateRequest(name: "cat house", projectPath: "/tmp/cat-house")])
    }

    func test_createSession_broadcastsSessionCreateRequest() {
        let transport = StubTransport(hasConnectedClients: true)
        let sender = UserInputSender { transport }

        XCTAssertEqual(sender.createSession(workspaceId: "w1", title: "new chat"), .sent)
        XCTAssertEqual(transport.broadcasted, [.sessionCreateRequest(workspaceId: "w1", title: "new chat")])
    }

    func test_createWorkspace_withNoConnectedClient_reportsDisconnected() {
        let transport = StubTransport(hasConnectedClients: false)
        let sender = UserInputSender { transport }

        XCTAssertEqual(sender.createWorkspace(name: "x", projectPath: nil), .notDelivered)
        XCTAssertTrue(transport.broadcasted.isEmpty)
    }
}
