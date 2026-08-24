//
//  AgentSession.swift
//  Puck
//
//  One past conversation with the coding CLI, as recorded under
//  ~/.claude/projects.
//
//  Read, never written. These are the CLI's own transcripts; Puck shows them
//  so a run can be found again, and so "which project was that in" has an
//  answer that does not involve opening a terminal.
//

import Foundation

struct AgentSession: Identifiable, Equatable {
    /// The CLI's own session id, which is also the transcript's file name.
    let id: String
    let transcriptPath: String
    /// The directory the session ran in, taken from the transcript rather
    /// than from its enclosing folder name: that folder is the path with
    /// every `/` and `.` turned into `-`, which cannot be turned back.
    let workingDirectory: String
    /// The first thing said in the session, trimmed to one line.
    let title: String
    let model: String?
    let modifiedAt: Date

    /// The last two path components, which is how people name a project out
    /// loud -- the full path is too long for a list and its head is the same
    /// for everything.
    var projectLabel: String {
        let parts = (workingDirectory as NSString).pathComponents.filter { $0 != "/" }
        return parts.suffix(2).joined(separator: "/")
    }
}
