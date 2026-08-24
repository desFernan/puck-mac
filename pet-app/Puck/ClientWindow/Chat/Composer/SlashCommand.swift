//
//  SlashCommand.swift
//  Puck
//
//  Settings you can change without leaving the conversation.
//
//  Typed into the same field as everything else and answered in the same
//  transcript, because that is where the question comes up: you notice a
//  turn was too shallow while reading it, not while looking at a settings
//  window. A command never reaches the agent -- it is handled here and
//  answered locally.
//

import Foundation

enum SlashCommand: Equatable {
    /// `/model` shows the current one; `/model gpt-5.5` sets it.
    case model(String?)
    /// `/effort`, or `/effort high`.
    case effort(AgentEffort?)
    /// `/permissions` shows what the coding CLI is allowed to do on its own;
    /// `/permissions all` changes it. The same setting Settings' picker
    /// writes, asked where the consequence shows up.
    case permissions(AgentPermissionMode?)
    /// `/skills` lists what is installed, project first. Read-only: adding
    /// one means putting a directory somewhere, which is not a thing to do
    /// from a chat line.
    case skills
    /// `/fast` -- the low end of `/effort` under the name people reach for.
    case fast
    case help
    /// Something starting with `/` that names no command. Reported rather
    /// than sent: a typo'd command should not silently become a question to
    /// the agent, which would answer it as if it were prose.
    case unknown(String)

    /// nil when `text` is not a command at all, so the caller sends it on.
    ///
    /// A lone `/` is not a command, and neither is a path like `/usr/bin` --
    /// a command's name is letters, and what follows the name is a space.
    static func parse(_ text: String) -> SlashCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let body = trimmed.dropFirst()
        let name = String(body.prefix { $0.isLetter }).lowercased()
        guard !name.isEmpty else { return nil }
        let rest = body.dropFirst(name.count)
        guard rest.isEmpty || rest.first == " " else { return nil }
        let argument = rest.trimmingCharacters(in: .whitespaces)
        let value = argument.isEmpty ? nil : argument

        switch name {
        case "model": return .model(value)
        case "effort":
            guard let value else { return .effort(nil) }
            guard let effort = AgentEffort(rawValue: value.lowercased()) else { return .unknown(trimmed) }
            return .effort(effort)
        case "fast": return .fast
        case "permissions":
            guard let value else { return .permissions(nil) }
            guard let mode = AgentPermissionMode(rawValue: value.lowercased()) else { return .unknown(trimmed) }
            return .permissions(mode)
        case "skills": return .skills
        case "help": return .help
        default: return .unknown(trimmed)
        }
    }

    /// Every command, for `/help` and for the test that keeps the two lists
    /// from drifting.
    static let names = ["model", "effort", "fast", "permissions", "skills", "help"]

    /// What to offer while someone is typing a command.
    ///
    /// Offered on the prefix alone -- `/` shows everything, `/e` narrows to
    /// `/effort` -- and withdrawn the moment the name is complete and a space
    /// follows it, because from there the argument is being typed and a list
    /// of command names is in the way.
    ///
    /// Nothing is suggested for ordinary prose, including a message that
    /// happens to contain a slash: the same rule `parse` uses, so the two
    /// cannot disagree about what looks like a command.
    static func suggestions(for text: String) -> [SlashSuggestion] {
        // Only the leading space is ignored. A *trailing* one is the moment
        // the name stopped being typed and the argument started, which is
        // exactly when this list has to get out of the way -- trimming both
        // ends made "/effort " look like "/effort" and kept it open.
        let leading = text.drop { $0.isWhitespace }
        guard leading.hasPrefix("/") else { return [] }
        let body = leading.dropFirst()
        let typed = String(body.prefix { $0.isLetter }).lowercased()
        // Past the name: the rest is an argument, and so is a trailing space.
        guard body.count == typed.count else { return [] }
        return names
            .filter { typed.isEmpty || $0.hasPrefix(typed) }
            .map { SlashSuggestion(name: $0) }
    }
}

/// One offered command: its name, and the single line that says what it does.
struct SlashSuggestion: Identifiable, Equatable {
    let name: String

    var id: String { name }
    /// What gets typed when this is taken. The trailing space is deliberate
    /// for the ones that take an argument -- it is the next thing anyone
    /// types -- and harmless for the ones that do not, which ignore it.
    var completion: String { "/\(name) " }

    var summary: String {
        switch name {
        case "model": return Strings.text(.slashSummaryModel)
        case "effort": return Strings.text(.slashSummaryEffort)
        case "fast": return Strings.text(.slashSummaryFast)
        case "permissions": return Strings.text(.slashSummaryPermissions)
        case "skills": return Strings.text(.slashSummarySkills)
        case "help": return Strings.text(.slashSummaryHelp)
        default: return ""
        }
    }
}
