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
    /// ...and the CLI may run commands too. Puck's own dangerous tools still
    /// stop and ask: this setting is about what the *CLI* may do on its own.
    case everything = "all"
    /// ...and nothing asks at all. On top of `.everything`, Puck's own
    /// approval-gated tools -- a shell command, an AppleScript, a click on
    /// somebody else's window -- run straight away instead of putting a 승인
    /// prompt in the chat, and the coding agent's own edit permissions are
    /// answered yes without one either.
    ///
    /// Claude Code's bypass mode, and the same trade: the agent stops waiting
    /// for a person, and the person stops seeing what it is about to do
    /// before it does it. Never the default (see `fallback`), and reachable
    /// only by choosing it -- `/permissions auto`, the composer's menu, or
    /// Settings.
    case auto

    var id: String { rawValue }

    /// Shown in Settings' picker.
    var displayName: String {
        switch self {
        case .toolsOnly: return Strings.text(.permissionsToolsOnly)
        case .edits: return Strings.text(.permissionsEdits)
        case .everything: return Strings.text(.permissionsEverything)
        case .auto: return Strings.text(.permissionsAuto)
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
        case .everything, .auto: return true
        }
    }

    /// Whether the gate this mode is *not* about -- Puck's own, the one
    /// `AgentRunner` opens for `.required`/`.requiredWithWhitelist` tools --
    /// is open too.
    ///
    /// The three careful modes leave it exactly where it was: they decide
    /// what the CLI may do by itself, and a shell command the *model* asked
    /// Puck to run is a different question with a different prompt. `.auto`
    /// is the one answer that means "stop asking me", so it is the one that
    /// has to reach both.
    var approvesWithoutAsking: Bool { self == .auto }
}
