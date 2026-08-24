//
//  AgentPermissionMode.swift
//  Puck
//
//  How much a coding CLI is allowed to do on its own during a chat turn.
//
//  The CLI asks before acting (`session/request_permission`), and something
//  has to answer. Until now the answer was fixed: yes to Puck's own MCP
//  tools, no to everything else -- which meant the CLI could never write a
//  file, so asking it to change code ended in "파일 수정 권한이 거부돼서".
//  Safe, and useless for the thing the CLI is there to do.
//
//  A setting rather than a new fixed answer, because the right one depends on
//  what the user is doing: reading code back needs nothing, editing needs
//  writes, and a task that runs a build needs a shell.
//

import Foundation

enum AgentPermissionMode: String, CaseIterable, Identifiable {
    /// Puck's own tools only. Anything the CLI wants to do itself is refused.
    case toolsOnly = "tools"
    /// ...and the CLI may edit files. The sandbox still decides *which* files:
    /// writes are confined to the project and the CLI's own state directory,
    /// so "edits" cannot reach the rest of the disk however this is set.
    case edits
    /// ...and the CLI may run commands too.
    case everything = "all"

    var id: String { rawValue }

    /// Shown in Settings' picker.
    var displayName: String {
        switch self {
        case .toolsOnly: return Strings.text(.permissionsToolsOnly)
        case .edits: return Strings.text(.permissionsEdits)
        case .everything: return Strings.text(.permissionsEverything)
        }
    }

    /// The environment variable and `.env` key this is read from, alongside
    /// AGENT_PROVIDER and CODING_AGENT.
    static let environmentVariable = "AGENT_PERMISSIONS"

    /// `.toolsOnly` -- the behaviour that shipped, kept as the default so
    /// turning a CLI loose on a filesystem stays something a person chose.
    static let fallback: AgentPermissionMode = .toolsOnly

    static func resolved(fromRawValue raw: String?) -> AgentPermissionMode {
        raw.flatMap { AgentPermissionMode(rawValue: $0.lowercased()) } ?? fallback
    }

    /// Whether this mode answers yes to a permission the CLI asked for.
    /// Puck's own MCP tools are always allowed: they carry their own approval
    /// gate, so asking twice would mean two prompts for one action.
    func allows(_ request: AcpPermissionRequest, ownMCPServer server: String) -> Bool {
        if request.namesMCPServer(server) { return true }
        switch self {
        case .toolsOnly: return false
        case .edits: return request.isFileEdit
        case .everything: return true
        }
    }
}
