//
//  SidebarFilter.swift
//  Puck
//
//  Narrowing the sidebar to what was typed.
//
//  The list grows one section per workspace and one row per chat, and it only
//  ever grows: nothing is archived and nothing falls off. Past a couple of
//  projects the way to reach a conversation you remember by name is to scroll
//  and read, which is what a filter field is for.
//

import Foundation

enum SidebarFilter {
    /// Whether `query` says anything worth filtering by.
    static func isActive(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Whether a workspace's own name or project answers `query`. A matching
    /// workspace keeps all of its chats: someone typing a project's name is
    /// asking for that project, not for the chats that repeat its name.
    static func matchesWorkspace(_ query: String, name: String, projectPath: String?) -> Bool {
        guard isActive(query) else { return true }
        let needle = normalise(query)
        return normalise(name).contains(needle) || normalise(projectPath ?? "").contains(needle)
    }

    /// Whether one chat's title answers `query`.
    static func matchesSession(_ query: String, title: String) -> Bool {
        guard isActive(query) else { return true }
        return normalise(title).contains(normalise(query))
    }

    /// Case- and diacritic-insensitive, which is what a person typing into a
    /// filter field expects of it -- and what Korean input needs, where a
    /// title may be typed with a different composition than it is stored in.
    private static func normalise(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
