//
//  Skill.swift
//  Puck
//
//  A skill the coding CLI can load: one directory holding a SKILL.md whose
//  frontmatter names and describes it.
//
//  Read rather than owned. The CLI decides what to do with these; Puck's part
//  is to show what is installed and where each came from, because "why did
//  the agent do that" is usually answered by a skill nobody remembered
//  having.
//

import Foundation

struct Skill: Identifiable, Equatable {
    /// Where a skill was found, which is also what decides who else sees it.
    enum Source: Equatable {
        /// `~/.claude/skills` -- every project on this machine.
        case personal
        /// `<project>/.claude/skills` -- checked in, so the team has it too.
        case project

        var displayName: String {
            switch self {
            case .personal: return Strings.text(.skillSourcePersonal)
            case .project: return Strings.text(.skillSourceProject)
            }
        }
    }

    let name: String
    let description: String
    /// The SKILL.md itself, so a reader can be pointed straight at it.
    let path: String
    let source: Source

    var id: String { path }

    /// The directory that holds the skill, which is what a person means when
    /// they say where it lives.
    var directory: String { (path as NSString).deletingLastPathComponent }
}
