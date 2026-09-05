//
//  ChatArchive.swift
//  Puck
//
//  Every chat and everything said in it, kept on disk.
//
//  Workspace metadata has been persisted since the registries moved here
//  (WorkspaceRegistry), and the chats inside those workspaces were not: both
//  SessionRegistry and ChatSession lived for the length of a process, so
//  quitting the app -- or a rebuild, or a restart -- left the projects on
//  disk and threw away every conversation held in them. From the outside
//  that is the app deleting your work, and it happened every single launch.
//
//  Owned by the window rather than by pet-app, unlike workspaces. The window
//  is what folds the event stream into a transcript and what draws the
//  sidebar; pet-app's SessionRegistry only mints ids for new chats and never
//  sees a word of what is said in one. So the side that has the data is the
//  side that stores it, and a restored chat needs nothing from the socket.
//
//  Deliberately not kept: whether a run was in flight, and any approval it
//  was waiting on. Both belong to a process that is gone -- a restored
//  spinner would never stop, and a restored approval banner would offer two
//  buttons whose answer nothing is left to receive.
//

import Foundation

/// One chat as it is written down. A DTO rather than `Codable` on
/// `ChatSession` and `ChatTimelineEntry` themselves: those two are shaped for
/// rendering, this one is a file format, and the whole reason for a stored
/// `version` is that the two are allowed to move apart.
struct StoredChatSession: Codable, Equatable {
    let id: String
    let workspaceId: String
    let title: String
    let origin: SessionOrigin
    /// Whether the name is still one the app gave it -- see
    /// `ChatSession.isAutoTitled`. Stored rather than re-derived from the
    /// title, because a chat auto-named after its first message no longer
    /// looks auto-named, and re-deriving would let a restored chat be
    /// renamed out from under a name it had already earned.
    let isAutoTitled: Bool
    let hasTopicTitle: Bool
    /// Milliseconds since the epoch, like every other timestamp this app
    /// writes down (see WorkspaceRecord).
    let lastActivityAt: Int64?
    let entries: [StoredChatEntry]
}

/// One row of a transcript, flattened.
///
/// One struct with optional fields rather than a Codable enum: the enum has
/// seven cases whose payloads overlap almost entirely, and a hand-written
/// `init(from:)` for it is the same class of thing BridgeMessages' own header
/// warns about -- three places to edit for one new field, none of them
/// checked by the compiler.
struct StoredChatEntry: Codable, Equatable {
    enum Kind: String, Codable {
        case userMessage
        case assistantText
        case notice
        case toolCall
        case toolResult
        case approvalRequested
        case done
    }

    let kind: Kind
    /// The row's own id: a UUID string for the rows that mint one, the
    /// protocol's tool_use id for the two that do not.
    let id: String
    var text: String?
    var tool: String?
    var args: JSONValue?
    var ok: Bool?
    var error: ToolErrorCode?
    var detail: String?
    var approvalId: String?
    var summary: String?
}

/// Reads and writes the window's chats.
///
/// A file per store rather than a file per chat: the whole thing is read once
/// at launch and written on a timer, so one atomic write cannot leave the
/// sidebar half restored, and there is no directory to garbage-collect when a
/// chat is deleted.
final class ChatArchive {
    /// How many rows of one chat are kept.
    ///
    /// A cap, because a transcript grows without limit and this file is read
    /// whole at launch. Four hundred rows is far past what anyone scrolls
    /// back through, and the oldest go first -- the same end `AgentConversations`
    /// trims from, and for the same reason.
    static let maximumEntriesPerSession = 400

    private let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
    }

    /// Beside `workspaces.json`, which is the other half of the same picture.
    static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Puck/chats.json")
    }

    // MARK: - Reading

    /// Every chat that was written down, rebuilt.
    ///
    /// Returns nothing at all when the file is missing, unreadable, or from a
    /// version this build does not know: an empty sidebar is the state the app
    /// was always in before this existed, and it is survivable. What must not
    /// happen is the next save writing over a store we merely failed to parse,
    /// which `save` guards separately.
    func load() -> [ChatSession] {
        stored().map(Self.session(from:))
    }

    private func stored() -> [StoredChatSession] {
        guard let data = try? Data(contentsOf: storageURL) else { return [] }
        guard let parsed = try? JSONDecoder().decode(PersistedChats.self, from: data),
              parsed.version == Self.storeVersion
        else {
            unreadableStoreNeedsBackup = true
            return []
        }
        return parsed.sessions
    }

    static func session(from stored: StoredChatSession) -> ChatSession {
        ChatSession(
            id: stored.id,
            workspaceId: stored.workspaceId,
            title: stored.title,
            origin: stored.origin,
            isAutoTitled: stored.isAutoTitled,
            hasTopicTitle: stored.hasTopicTitle,
            lastActivityAt: stored.lastActivityAt.map { Date(timeIntervalSince1970: Double($0) / 1000) },
            timeline: stored.entries.compactMap(Self.entry(from:))
        )
    }

    /// A row this build cannot make sense of is dropped rather than faked --
    /// one unknown row must not cost the chat around it.
    static func entry(from stored: StoredChatEntry) -> ChatTimelineEntry? {
        switch stored.kind {
        case .userMessage:
            guard let text = stored.text, let id = UUID(uuidString: stored.id) else { return nil }
            return .userMessage(id: id, text: text)
        case .assistantText:
            guard let text = stored.text, let id = UUID(uuidString: stored.id) else { return nil }
            return .assistantText(id: id, text: text)
        case .notice:
            guard let text = stored.text, let id = UUID(uuidString: stored.id) else { return nil }
            return .notice(id: id, text: text)
        case .toolCall:
            guard let tool = stored.tool else { return nil }
            return .toolCall(id: stored.id, tool: tool, args: stored.args)
        case .toolResult:
            guard let ok = stored.ok else { return nil }
            // `data` is deliberately absent -- see `entry(from:)`'s mirror below.
            return .toolResult(id: stored.id, ok: ok, data: nil, error: stored.error, detail: stored.detail)
        case .approvalRequested:
            guard let approvalId = stored.approvalId, let summary = stored.summary,
                  let id = UUID(uuidString: stored.id)
            else { return nil }
            return .approvalRequested(id: id, approvalId: approvalId, summary: summary)
        case .done:
            guard let ok = stored.ok, let id = UUID(uuidString: stored.id) else { return nil }
            return .done(id: id, ok: ok, summary: stored.summary ?? "")
        }
    }

    // MARK: - Writing

    /// Writes the chats worth keeping.
    ///
    /// - Parameter knownWorkspaceIds: the workspaces that still exist. A chat
    ///   under a workspace that has gone is unreachable -- the sidebar draws
    ///   chats per workspace -- so keeping it would grow the file forever with
    ///   rows nothing can show.
    func save(_ sessions: [ChatSession], knownWorkspaceIds: Set<String>) {
        let keep = sessions
            .filter { knownWorkspaceIds.contains($0.workspaceId) }
            .map(Self.stored(from:))
        do {
            try write(keep)
        } catch {
            AppLogger.shared.log(.error, "ChatArchive: could not save chats: \(error)")
        }
    }

    static func stored(from session: ChatSession) -> StoredChatSession {
        StoredChatSession(
            id: session.id,
            workspaceId: session.workspaceId,
            title: session.title,
            origin: session.origin,
            isAutoTitled: session.isAutoTitled,
            hasTopicTitle: session.hasTopicTitle,
            lastActivityAt: session.lastActivityAt.map { Int64($0.timeIntervalSince1970 * 1000) },
            entries: session.timeline.suffix(maximumEntriesPerSession).map(Self.stored(from:))
        )
    }

    /// One row, flattened.
    ///
    /// A tool result's `data` is dropped on purpose. It is the only unbounded
    /// field in a transcript -- a `run_shell` result carries up to 128KB of
    /// captured output -- and nothing draws it: the row shows the arguments
    /// and, on a failure, the error and its detail. Keeping it would multiply
    /// the file by the size of every command anyone has ever run, to restore
    /// something no one can see.
    static func stored(from entry: ChatTimelineEntry) -> StoredChatEntry {
        switch entry {
        case .userMessage(let id, let text):
            return StoredChatEntry(kind: .userMessage, id: id.uuidString, text: text)
        case .assistantText(let id, let text):
            return StoredChatEntry(kind: .assistantText, id: id.uuidString, text: text)
        case .notice(let id, let text):
            return StoredChatEntry(kind: .notice, id: id.uuidString, text: text)
        case .toolCall(let id, let tool, let args):
            return StoredChatEntry(kind: .toolCall, id: id, tool: tool, args: args)
        case .toolResult(let id, let ok, _, let error, let detail):
            return StoredChatEntry(kind: .toolResult, id: id, ok: ok, error: error, detail: detail)
        case .approvalRequested(let id, let approvalId, let summary):
            return StoredChatEntry(
                kind: .approvalRequested,
                id: id.uuidString,
                approvalId: approvalId,
                summary: summary
            )
        case .done(let id, let ok, let summary):
            return StoredChatEntry(kind: .done, id: id.uuidString, ok: ok, summary: summary)
        }
    }

    // MARK: - The file itself

    private struct PersistedChats: Codable {
        let version: Int
        let sessions: [StoredChatSession]
    }

    private static let storeVersion = 1

    /// Set when a store was there and could not be read -- see
    /// WorkspaceRegistry, which does the same thing for the same reason: a
    /// fresh file written over one we merely failed to parse destroys the only
    /// copy of everything the user said.
    private var unreadableStoreNeedsBackup = false

    private func write(_ sessions: [StoredChatSession]) throws {
        backUpUnreadableStoreIfNeeded()
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(PersistedChats(version: Self.storeVersion, sessions: sessions))
        // Atomic, like the workspace store: a half-written file would strand
        // every chat at once, and this one is written far more often.
        try data.write(to: storageURL, options: .atomic)
    }

    private func backUpUnreadableStoreIfNeeded() {
        guard unreadableStoreNeedsBackup else { return }
        unreadableStoreNeedsBackup = false
        let stamp = Int(Date().timeIntervalSince1970)
        try? FileManager.default.moveItem(
            at: storageURL,
            to: storageURL.appendingPathExtension("unreadable-\(stamp)")
        )
    }
}
