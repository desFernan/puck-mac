//
//  BridgeConnectionStateTests.swift
//  PuckTests
//
//  The state classification behind BridgeConnection's retry decision, tested
//  as a pure function -- the same shape as BridgeServerFailureMappingTests,
//  and for the same reason: reproducing these states against a real socket is
//  either impossible or slow.
//

import XCTest
import Network
@testable import Puck

final class BridgeConnectionStateTests: XCTestCase {
    func test_waitingEndsTheConnectionSoTheOwnerRetries() {
        // The one that mattered. NWConnection parks in .waiting when the peer
        // is not listening yet -- PuckClient connecting to bridge.sock before
        // pet-app has bound it. It does not leave .waiting when the socket
        // appears later, so anything short of treating it as a close left the
        // client connected at the fd level, never sending client_hello, and
        // counted by the server as no gui at all.
        XCTAssertTrue(BridgeConnection.endsTheConnection(.waiting(.posix(.ENOENT))))
        XCTAssertTrue(BridgeConnection.endsTheConnection(.waiting(.posix(.ECONNREFUSED))))
    }

    func test_failedAndCancelledEndTheConnection() {
        XCTAssertTrue(BridgeConnection.endsTheConnection(.failed(.posix(.ECONNRESET))))
        XCTAssertTrue(BridgeConnection.endsTheConnection(.cancelled))
    }

    func test_theStatesOnTheWayUpDoNot() {
        XCTAssertFalse(BridgeConnection.endsTheConnection(.setup))
        XCTAssertFalse(BridgeConnection.endsTheConnection(.preparing))
        XCTAssertFalse(BridgeConnection.endsTheConnection(.ready))
    }
}
