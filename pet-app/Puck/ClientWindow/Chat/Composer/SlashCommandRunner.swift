//
//  SlashCommandRunner.swift
//  Puck
//
//  Carries out a SlashCommand and says what happened, in one line the chat
//  can show. Settings are read back after writing rather than assumed: an
//  environment variable or a nearer `.env` can outrank the file this writes,
//  and reporting a change that did not take is the confusion `keySource`
//  exists to prevent everywhere else.
//

import Foundation

struct SlashCommandRunner {
    var configuration: () -> AgentConfiguration = { AgentConfiguration.load() }
    var currentEffort: () -> AgentEffort = { AgentConfiguration.effort() }
    var write: (_ key: String, _ value: String?) -> Bool = { key, value in
        DotEnv.write(key: key, value: value, to: AgentConfiguration.writableEnvFile)
    }
    var currentPermissions: () -> AgentPermissionMode = { AgentConfiguration.permissionMode() }
    /// The project the active workspace points at, or nil for a chat-only
    /// one. `/skills` lists the project's own skills first, and there are
    /// none to list without it.
    var projectPath: () -> String? = { nil }
    var installedSkills: (_ projectPath: String?) -> [Skill] = { path in
        SkillCatalog.discover(projectPath: path)
    }

    func run(_ command: SlashCommand) -> String {
        switch command {
        case .help:
            return Strings.text(.slashHelp)

        case .unknown(let text):
            return String(format: Strings.text(.slashUnknownFormat), text)

        case .model(nil):
            let current = configuration()
            guard current.provider.supportsModelSelection else {
                return String(format: Strings.text(.slashModelUnsupportedFormat), current.provider.displayName)
            }
            return String(format: Strings.text(.slashModelCurrentFormat), current.model)

        case .model(.some(let name)):
            let current = configuration()
            guard current.provider.supportsModelSelection else {
                return String(format: Strings.text(.slashModelUnsupportedFormat), current.provider.displayName)
            }
            guard write("AGENT_MODEL", name) else { return Strings.text(.slashWriteFailed) }
            return String(format: Strings.text(.slashModelSetFormat), configuration().model)

        case .effort(nil):
            return String(format: Strings.text(.slashEffortCurrentFormat), currentEffort().displayName)

        case .effort(.some(let effort)):
            return set(effort)

        case .fast:
            return set(.low)

        case .permissions(nil):
            return String(format: Strings.text(.slashPermissionsCurrentFormat), currentPermissions().displayName)

        case .permissions(.some(let mode)):
            guard write(AgentPermissionMode.environmentVariable, mode.rawValue) else {
                return Strings.text(.slashWriteFailed)
            }
            return String(format: Strings.text(.slashPermissionsSetFormat), currentPermissions().displayName)

        case .skills:
            return skillList()
        }
    }

    /// One line per skill: its name, where it came from, and the one-line
    /// description its manifest carries. Long descriptions are left whole --
    /// a truncated description is a description nobody can act on.
    private func skillList() -> String {
        let skills = installedSkills(projectPath())
        guard !skills.isEmpty else { return Strings.text(.slashSkillsEmpty) }
        let lines = skills.map { skill in
            let description = skill.description.isEmpty ? "" : " — \(skill.description)"
            return "- `\(skill.name)` (\(skill.source.displayName))\(description)"
        }
        return ([Strings.text(.slashSkillsHeader)] + lines).joined(separator: "\n")
    }

    private func set(_ effort: AgentEffort) -> String {
        guard write(AgentEffort.environmentVariable, effort.rawValue) else {
            return Strings.text(.slashWriteFailed)
        }
        return String(format: Strings.text(.slashEffortSetFormat), currentEffort().displayName)
    }
}
