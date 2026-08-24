//
//  SessionRegistry.swift
//  Puck
//
//  Port of workspace/src/main/session-registry.ts. Session metadata (title,
//  owning workspace, who created it) for the lifetime of the process.
//
//  Deliberately not persisted, same as the original: sessions are not restored
//  across restarts yet, and inventing that here would be a product decision
//  dressed up as a port. Workspace metadata *is* persisted -- see
//  WorkspaceRegistry -- so the asymmetry is intentional, not an oversight.
//
//  Main-thread only, like WorkspaceRegistry.
//

import Foundation

struct SessionRecord: Equatable {
    let id: String
    let workspaceId: String
    let title: String
    /// `.user` for the sidebar's "새 채팅", `.agent` for a task session the
    /// agent opened for itself.
    let origin: SessionOrigin
    let createdAt: Int64
}

final class SessionRegistry {
    private var order: [String] = []
    private var sessions: [String: SessionRecord] = [:]

    @discardableResult
    func record(
        workspaceId: String,
        title: String,
        origin: SessionOrigin,
        id: String = UUID().uuidString
    ) -> SessionRecord {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = SessionRecord(
            id: id,
            workspaceId: workspaceId,
            title: trimmed.isEmpty ? ChatSession.untitledTitle : trimmed,
            origin: origin,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        if sessions[id] == nil { order.append(id) }
        sessions[id] = record
        return record
    }

    func get(id: String) -> SessionRecord? {
        sessions[id]
    }

    func list(inWorkspace workspaceId: String) -> [SessionRecord] {
        order.compactMap { sessions[$0] }.filter { $0.workspaceId == workspaceId }
    }
}
