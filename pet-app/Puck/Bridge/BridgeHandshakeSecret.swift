//
//  BridgeHandshakeSecret.swift
//  Puck
//
//  The token a client has to present on bridge.sock before pet-app will run a
//  tool for it.
//
//  The socket is a filesystem object in a 0700 directory with 0600 on the
//  socket itself, which keeps out other accounts on the machine. It does not
//  keep out another process running as the same person -- and pet-app is the
//  side holding Accessibility and Automation, so a process that can send
//  `tool_dispatch` can run a shell command through Puck's own privileges
//  without ever meeting the approval prompt that lives in PuckClient.
//
//  A secret in a file the same user can also read is not a wall. What it is:
//  a lock that a *sandboxed* process cannot reach around (it cannot read this
//  container at all), and a step that anything else has to take deliberately
//  rather than by opening a socket whose path is public. The wall -- verifying
//  the peer's code signature, which needs the peer's pid and therefore a
//  socket layer that exposes one -- is its own piece of work.
//

import Foundation

enum BridgeHandshakeSecret {
    /// Beside the socket, in the same 0700 directory.
    static var fileURL: URL { fileURL(besideSocketAt: BridgeSocketPath.default) }

    /// The secret belonging to a particular socket. Derived rather than
    /// global so a second server -- a test's, on a temp path -- neither reads
    /// nor overwrites the running app's.
    static func fileURL(besideSocketAt socketURL: URL) -> URL {
        socketURL.deletingLastPathComponent().appendingPathComponent("bridge.secret")
    }

    /// Read by the client. nil when pet-app has not written one yet, which is
    /// the ordinary state before it has started.
    static func current(at url: URL = fileURL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    /// Written by pet-app on every start: a token that outlives one launch
    /// would let a client that read it once keep dispatching tools for as long
    /// as the file survived.
    @discardableResult
    static func rotate(at url: URL = fileURL) -> String {
        let token = randomToken()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data(token.utf8).write(to: url, options: .atomic)
        // After the write: an atomic write replaces the file, and with it any
        // permissions set on the old one.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return token
    }

    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Compared in constant time: a token checked with `==` leaks its prefix
    /// to anything that can time the answer, and this one is checked on a
    /// socket a caller controls the timing of.
    static func matches(_ presented: String?, expected: String?) -> Bool {
        guard let expected, !expected.isEmpty else { return false }
        guard let presented else { return false }
        let a = Array(expected.utf8)
        let b = Array(presented.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(a, b) { difference |= left ^ right }
        return difference == 0
    }
}
