//
//  BridgeSocketPath.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Where bridge.sock lives -- Puck (which hosts it, BridgeServer) and
//  PuckClient (which connects to it as a client, 2026-07-30) both need
//  this same path.
//

import Foundation

enum BridgeSocketPath {
    static let `default`: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(AppIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("bridge.sock")
    }()
}
