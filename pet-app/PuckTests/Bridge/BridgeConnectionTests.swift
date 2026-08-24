//
//  BridgeConnectionTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  PuckClient wraps its own outbound NWConnection to bridge.sock in a
//  BridgeConnection (2026-07-30) -- it needs to know when that connection is
//  actually ready so it can send client_hello, which onMessage/onClose alone
//  don't tell it (BridgeServer's own stateUpdateHandler already claims those
//  two states internally).
//

import XCTest
import Network
@testable import Puck

final class BridgeConnectionTests: XCTestCase {
    func test_onReady_firesOnceTheWrappedConnectionIsUp() {
        let socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("bridge.sock")
        let server = BridgeServer(socketURL: socketURL)
        try! server.start()
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: socketURL.deletingLastPathComponent())
        }

        let ready = expectation(description: "client BridgeConnection became ready")
        let nwConnection = NWConnection(to: .unix(path: socketURL.path), using: .tcp)
        let bridgeConnection = BridgeConnection(connection: nwConnection)
        bridgeConnection.onReady = { ready.fulfill() }
        bridgeConnection.start(queue: .main)

        wait(for: [ready], timeout: 5)
        bridgeConnection.cancel()
    }
}
