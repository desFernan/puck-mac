//
//  SessionList.swift
//  Puck
//
//  Every chat the window knows about, keyed by the workspace it belongs to
//  and ordered by when it arrived.
//
//  The key is a pair, not a session id: every workspace gets its own
//  "default" casual session (protocol 3.4 keeps one under each), so a session
//  id is only unique within a workspace. A dictionary keyed on the id alone
//  would have every workspace's casual chat overwriting the last one's.
//
//  Insert and remove are the only two ways the list changes, and both
//  announce -- the collection is not `@Published`, because the sidebar reads
//  it through `sessions(in:)` rather than binding to it, so a mutation that
//  forgets to announce leaves a sidebar drawn from a stale snapshot: rows
//  that exist go missing and the selection sits under the wrong header.
//  Funnelling both through here is what stops a fourth call site added later
//  from forgetting.
//
//  Lifted out of ClientWindowStore, where it was two private properties, a
//  private key type and five methods among forty. Nothing here needs the rest
//  of that store, and none of it could be tested without one.
//

import Foundation

struct SessionList {
    /// Sessions are keyed on (workspaceId, sessionId) -- see the header.
    private struct Key: Hashable {
        let workspaceId: String
        let sessionId: String
    }

    private var byKey: [Key: ChatSession] = [:]
    private var order: [Key] = []

    var isEmpty: Bool { order.isEmpty }

    /// Adds a session, or does nothing if that workspace already has one
    /// under that id.
    ///
    /// Idempotent because every caller wanted it to be: pet-app replays its
    /// registry on connect, and the agent announces a task session on the
    /// socket *and* opens it locally, so the same session legitimately
    /// arrives twice. Re-creating would wipe the messages already in it and
    /// duplicate the sidebar row.
    ///
    /// - Returns: whether the list changed, so the caller knows to announce.
    @discardableResult
    mutating func insert(_ session: ChatSession) -> Bool {
        let key = Key(workspaceId: session.workspaceId, sessionId: session.id)
        guard byKey[key] == nil else { return false }
        byKey[key] = session
        order.append(key)
        return true
    }

    /// The mirror of `insert`.
    ///
    /// - Returns: whether the list changed.
    @discardableResult
    mutating func remove(workspaceId: String, sessionId: String) -> Bool {
        let key = Key(workspaceId: workspaceId, sessionId: sessionId)
        guard byKey[key] != nil else { return false }
        byKey.removeValue(forKey: key)
        order.removeAll { $0 == key }
        return true
    }

    /// Every session there is, oldest first. For whoever has to write them
    /// all down -- see ChatArchive.
    func all() -> [ChatSession] {
        order.compactMap { byKey[$0] }
    }

    /// Every session in a workspace, oldest first.
    func sessions(in workspaceId: String) -> [ChatSession] {
        order.compactMap { $0.workspaceId == workspaceId ? byKey[$0] : nil }
    }

    func session(workspaceId: String, sessionId: String) -> ChatSession? {
        byKey[Key(workspaceId: workspaceId, sessionId: sessionId)]
    }

    /// Drops every session belonging to a workspace that has gone away.
    ///
    /// - Returns: whether the list changed.
    @discardableResult
    mutating func removeAll(inWorkspace workspaceId: String) -> Bool {
        let doomed = order.filter { $0.workspaceId == workspaceId }
        guard !doomed.isEmpty else { return false }
        for key in doomed { byKey.removeValue(forKey: key) }
        order.removeAll { $0.workspaceId == workspaceId }
        return true
    }
}
