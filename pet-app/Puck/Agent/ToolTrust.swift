//
//  ToolTrust.swift
//  Puck
//
//  The tools somebody has said yes to often enough to stop being asked.
//
//  An agent working through anything real runs the same handful of dangerous
//  tools over and over -- the build, the tests, the formatter -- and every one
//  of them stopped the run and put a card on screen. A ten-minute task spent
//  most of it waiting for somebody to press 허용 for the fourth time, which is
//  not a safety mechanism: it is a prompt people learn to click through
//  without reading, which is strictly worse than no prompt at all.
//
//  ## What is remembered, and what deliberately is not
//
//  A tool name, in one workspace. Not the arguments: an allow-list of shell
//  commands reads like the safer choice and is not -- `run_shell` with an
//  argument nobody checks against a list that nobody can read is a rule that
//  gives the *appearance* of a limit. Saying "this project may run shell
//  commands without asking" is a decision somebody can actually understand,
//  and this is a project they already handed a coding agent.
//
//  Per workspace, because that is the unit of trust here: letting an agent
//  run the build in a project you own says nothing about the next project.
//
//  Revocable and visible -- AgentSettingsView lists everything in here with a
//  way to take it back, so a decision made in the middle of a long run in
//  order to get on with it is not a decision that quietly outlives it.
//

import Foundation

/// Read from anywhere, written from the main thread.
///
/// The reading side is a run asking "do I have to stop and ask about this",
/// which happens on whatever executor the turn is on; the writing side is
/// somebody pressing a button. A lock rather than an actor because the read
/// has to answer *now* -- an `await` there would mean the approval gate
/// suspends to consult a dictionary, and the gate is what decides whether the
/// run stops at all.
final class ToolTrustStore: ObservableObject {
    private let lock = NSLock()
    private var storage: [String: Set<String>] = [:]

    /// What is trusted, keyed by workspace.
    var trusted: [String: Set<String>] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    private let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        load()
    }

    /// Beside the chats and the schedules, for the same reason.
    static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Puck/trusted-tools.json")
    }

    // MARK: - Asking

    func isTrusted(tool: String, workspaceId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage[workspaceId]?.contains(tool) ?? false
    }

    /// Every trusted tool, as a flat list for the UI: one row per decision,
    /// newest workspaces no more important than old ones, so it is sorted
    /// rather than left in dictionary order -- a list that reorders itself
    /// between reads is one nobody can scan twice.
    var entries: [(workspaceId: String, tool: String)] {
        trusted
            .flatMap { workspace, tools in tools.map { (workspaceId: workspace, tool: $0) } }
            .sorted { ($0.workspaceId, $0.tool) < ($1.workspaceId, $1.tool) }
    }

    // MARK: - Changing

    @MainActor
    func trust(tool: String, workspaceId: String) {
        change { storage in
            guard storage[workspaceId]?.contains(tool) != true else { return false }
            storage[workspaceId, default: []].insert(tool)
            return true
        }
    }

    @MainActor
    func revoke(tool: String, workspaceId: String) {
        change { storage in
            guard storage[workspaceId]?.contains(tool) == true else { return false }
            storage[workspaceId]?.remove(tool)
            // An empty set is not a workspace that trusts nothing in
            // particular; it is a workspace with no decisions left in it, and
            // leaving one behind would keep a row in the file for every
            // project ever opened.
            if storage[workspaceId]?.isEmpty == true { storage.removeValue(forKey: workspaceId) }
            return true
        }
    }

    /// Everything, for the "전부 다시 묻기" button.
    @MainActor
    func revokeAll() {
        change { storage in
            guard !storage.isEmpty else { return false }
            storage = [:]
            return true
        }
    }

    /// Drops what belonged to a workspace that has gone -- the same sweep
    /// schedules get, and for the same reason: it names a project that no
    /// longer exists.
    @MainActor
    func revokeAll(inWorkspace workspaceId: String) {
        change { storage in
            guard storage[workspaceId] != nil else { return false }
            storage.removeValue(forKey: workspaceId)
            return true
        }
    }

    /// Applies a change, tells SwiftUI before it lands, and writes the file
    /// after. `mutate` returns whether anything actually changed, so a
    /// revoke of something already gone does not redraw a list or rewrite a
    /// file for nothing.
    @MainActor
    private func change(_ mutate: (inout [String: Set<String>]) -> Bool) {
        lock.lock()
        var updated = storage
        let changed = mutate(&updated)
        lock.unlock()
        guard changed else { return }
        objectWillChange.send()
        lock.lock()
        storage = updated
        lock.unlock()
        save()
    }

    // MARK: - The file

    private struct Persisted: Codable {
        let version: Int
        let trusted: [String: [String]]
    }

    private static let storeVersion = 1

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let parsed = try? JSONDecoder().decode(Persisted.self, from: data),
              parsed.version == Self.storeVersion
        else {
            // Starting empty means being asked again, which is the safe
            // direction for this particular file to fail in.
            return
        }
        storage = parsed.trusted.mapValues(Set.init)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Persisted(
                version: Self.storeVersion,
                trusted: trusted.mapValues { $0.sorted() }
            ))
            try data.write(to: storageURL, options: .atomic)
        } catch {
            AppLogger.shared.log(.error, "could not save trusted tools: \(error)")
        }
    }
}
