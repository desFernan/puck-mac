//
//  AgentSettingsView.swift
//  PuckClient
//
//  owner: 박해영 (Haeyoung Park)
//  Everything the agent needs configured: which provider it talks to, the
//  API key for the providers that take one, the model where the model is ours
//  to choose, and which coding CLI backs the CLI provider.
//
//  It lives in this app rather than in Puck's own SettingsView because the
//  agent that reads any of it (AgentHost) runs in this process. Puck's panel
//  only ever showed the key field because PuckClient had no Settings surface
//  of its own yet. Opened via the App menu's "설정…" (Cmd+,), same convention
//  every other Mac app uses.
//
//  Everything here persists to the same `.env`
//  (`AgentConfiguration.writableEnvFile`) rather than to UserDefaults: Puck
//  and PuckClient are separate processes with no change notification between
//  them, and the key field already solved that by writing a file both of them
//  re-read on every access. A second mechanism would mean the two could
//  disagree. Every control below therefore reads its value back out of
//  `agentConfiguration` after writing, instead of trusting what it just wrote
//  -- an environment variable or a nearer `.env` can outrank this file, and
//  saying "saved" while something else keeps winning is exactly the confusion
//  `keySource` exists to prevent.
//

import SwiftUI

struct AgentSettingsView: View {
    /// Only for the project path the skills list needs. Observed, so
    /// switching workspaces re-reads that project's own `.claude/skills`
    /// rather than showing the one the window happened to open on.
    @ObservedObject var clientWindowStore: ClientWindowStore

    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    /// Repainted when the theme changes, wherever it was changed from. The
    /// window is kept alive after closing, so a value read once would show
    /// the theme it was built under for the rest of the session.
    @State private var theme = ClientThemeStyle.resolved(
        fromDefaultsValue: ClientThemeStyle.sharedDefaults?.string(forKey: ClientThemeStyle.defaultsKey)
    )

    /// What's typed into the key/model fields before they're saved, and the
    /// resolved configuration every status line reports on.
    @State private var apiKeyDraft = ""
    @State private var apiKeyMessage: String?
    @State private var modelDraft = ""
    @State private var agentConfiguration = AgentConfiguration.load()

    /// Written into Puck's domain and announced, the same path the language
    /// picker beside it takes.
    private func select(_ style: ClientThemeStyle) {
        ClientThemeStyle.sharedDefaults?.set(style.rawValue, forKey: ClientThemeStyle.defaultsKey)
        theme = style
        // No direct poke at the window's store: this process already listens
        // for the broadcast, and a distributed notification is delivered to
        // its own sender too. Setting both would be two paths to keep in step.
        style.broadcast()
    }

    /// Unlike everything else on this window, the language is a UserDefaults
    /// setting rather than a `.env` one, so it is written into Puck's domain
    /// -- the one place it lives -- and then announced. Puck listens for that
    /// announcement, which is what relabels the pet's own menus and bubbles.
    private func select(_ language: AppLanguage) {
        AppLanguage.sharedDefaults?.set(language.rawValue, forKey: AppLanguage.defaultsKey)
        Localization.shared.apply(language)
        language.broadcast()
    }

    private func text(_ key: L10nKey) -> String {
        Strings.text(key, language: localization.language)
    }

    /// Reuses Puck's own SettingsSection/SettingsStackedRow rather than
    /// hand-approximating their padding/typography, which drifted visibly
    /// when it was tried: the section title lost SettingsSection's
    /// `.secondary` tint, a row label was dropped entirely, and the outer
    /// spacing didn't match SettingsStackedRow's tighter label-to-control
    /// rhythm. Sharing the component instead of the constants means this
    /// can't drift again.
    var body: some View {
        // A container, not two sections one after another in a ViewBuilder:
        // the modifiers below bind to the last expression, so without this
        // the padding and the width reached the agent section alone and the
        // one above it sat flush against the window edge.
        VStack(alignment: .leading, spacing: ClientTheme.Metrics.sectionSpacing) {
            // The language belongs on this window as much as on Puck's panel:
            // this is where nearly all of the app's text is, and the toolbar
            // button that opens it is labelled the same way. It is the one
            // setting here that is not the agent's, hence its own section.
            SettingsSection(title: text(.tabGeneral)) {
                SettingsStackedRow(label: text(.clientThemeLabel)) {
                    Picker("", selection: Binding(
                        get: { theme },
                        set: { select($0) }
                    )) {
                        ForEach(ClientThemeStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                SettingsStackedRow(label: text(.languageLabel)) {
                    Picker("", selection: Binding(
                        get: { localization.language },
                        set: { select($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

            }

            skillsSection

            SettingsSection(title: text(.agentHeader)) {
                // Same segmented-Picker-over-CaseIterable-plus-displayName
                // shape as SettingsView's theme picker, and the same
                // read-current-value/write-and-reload round trip every field
                // below it does.
                SettingsStackedRow(label: text(.providerLabel)) {
                    Picker("", selection: providerBinding) {
                        ForEach(AgentProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    // Keyed on the language. A segmented picker is an
                    // NSSegmentedControl underneath and keeps the titles it
                    // was built with while the rows' identities are unchanged,
                    // so switching to English left "코딩 CLI" sitting between
                    // two English labels. Same trick as the settings window's
                    // own `.id(appearance)`.
                    .id(localization.language)
                }

                if agentConfiguration.provider == .cli {
                    codingAgentRows
                }
                if agentConfiguration.acceptsCredential { apiKeyRows }

                if agentConfiguration.provider.supportsModelSelection {
                    modelRows
                }
            }
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
        .padding(.vertical, ClientTheme.Metrics.windowEdgePadding)
        .frame(width: 420)
        // The settings window is where the theme is chosen, so showing it in
        // the system's colours instead of the chosen one made the picker the
        // one control whose effect you could not see.
        .background(theme.palette.background)
        .environment(\.clientPalette, theme.palette)
        .preferredColorScheme(theme.colorScheme)
        .onReceive(
            DistributedNotificationCenter.default().publisher(for: ClientThemeStyle.crossProcessChangeNotification)
        ) { notification in
            guard let style = ClientThemeStyle.resolved(fromCrossProcessUserInfo: notification.userInfo) else { return }
            theme = style
        }
    }

    // MARK: - Skills

    /// What the CLI will load, and where each came from. Read every time the
    /// window draws rather than cached: skills are directories a person adds
    /// with an editor, and a list that needed a relaunch to notice would be
    /// wrong exactly when someone is adding one.
    private var skills: [Skill] {
        SkillCatalog.discover(projectPath: clientWindowStore.workspaces
            .first { $0.id == clientWindowStore.activeWorkspaceId }?
            .projectPath)
    }

    @ViewBuilder
    private var skillsSection: some View {
        let installed = skills
        SettingsSection(title: text(.skillsHeader)) {
            if installed.isEmpty {
                Text(text(.skillsEmpty))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
            } else {
                ForEach(installed) { skill in
                    skillRow(skill)
                }
            }

            Text(text(.skillsExplanation))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
        }
    }

    private func skillRow(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: ClientTheme.Metrics.spacingMedium) {
                Text(skill.name)
                    .font(ClientTheme.Typography.toolLabel)
                Text(skill.source.displayName)
                    .font(ClientTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                // Finder rather than the editor pane: a personal skill lives
                // outside the project, which is the only thing the editor can
                // open.
                Button(text(.skillReveal)) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: skill.path)])
                }
                .controlSize(.small)
            }
            if !skill.description.isEmpty {
                Text(skill.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
    }

    // MARK: - Rows

    @ViewBuilder
    private var apiKeyRows: some View {
        SettingsStackedRow(label: credentialFieldLabel) {
            HStack {
                // SecureField, so a key isn't left legible on a screen
                // that gets shared or recorded.
                SecureField("sk-…", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                Button(text(.apiKeySave)) { saveAPIKey(apiKeyDraft) }
                    .controlSize(.small)
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                // Offered when there is something to clear, which is no
                // longer the same as "configured" -- a CLI is configured with
                // no key of ours at all.
                if agentConfiguration.keySource != nil {
                    Button(text(.apiKeyClear)) { saveAPIKey(nil) }
                        .controlSize(.small)
                }
            }
            // A row with more than one control in it: as a container the
            // row's label names the group, and 저장/지우기 keep their own
            // names instead of all three answering to "API 키".
            .accessibilityElement(children: .contain)
        }

        Text(apiKeyStatus)
            .font(.footnote)
            .foregroundStyle(agentConfiguration.isConfigured ? .secondary : Color.orange)
            // Wrap rather than truncate. Without this the row is as wide as
            // the widest control above it and a sentence loses its tail --
            // the same modifier SettingsStackedRow puts on its own label.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ClientTheme.Metrics.spacingSmall)

        Text(String(
            format: text(.apiKeyExplanationFormat),
            agentConfiguration.credentialEnvironmentVariables.joined(separator: text(.listOrJoiner))
        ))
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
    }

    private var credentialFieldLabel: String {
        if agentConfiguration.provider == .cli {
            return String(format: text(.cliCredentialLabelFormat), agentConfiguration.codingAgent.displayName)
        }
        return String(format: text(.apiKeyLabelFormat), agentConfiguration.provider.displayName)
    }

    /// Shown only for the CLI provider. The picker writes the *same*
    /// `CODING_AGENT` the `code_editor` tool already reads, rather than a
    /// parallel setting: the pet thinking with a CLI and editing with a
    /// different one would be a distinction nobody asked for.
    @ViewBuilder
    private var codingAgentRows: some View {
        SettingsStackedRow(label: text(.codingAgentLabel)) {
            Picker("", selection: codingAgentBinding) {
                ForEach(CodingAgentKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        SettingsStackedRow(label: text(.permissionsLabel)) {
            Picker("", selection: permissionModeBinding) {
                ForEach(AgentPermissionMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // Localized titles, so the same keying as the provider picker
            // above -- see the note there.
            .id(localization.language)
        }

        Text(text(.permissionsExplanation))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ClientTheme.Metrics.spacingSmall)

        // Stated here rather than discovered when the pet fails to move: this
        // provider genuinely cannot call the pet's tools, and the prompt the
        // CLI receives says the same thing (CodingAgentCLIClient).
        Text(text(.cliProviderExplanation))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
    }

    /// Free text rather than a picker: a hardcoded list of model names goes
    /// stale every time a provider ships one, and being unable to type the
    /// model you have access to is worse than having to know its name. The
    /// row's trailing value shows what is actually in effect, so the default
    /// is visible without being typed.
    @ViewBuilder
    private var modelRows: some View {
        SettingsStackedRow(label: text(.modelLabel), value: agentConfiguration.model) {
            HStack {
                TextField(agentConfiguration.provider.defaultModel, text: $modelDraft)
                    .textFieldStyle(.roundedBorder)
                Button(text(.apiKeySave)) { saveModel(modelDraft) }
                    .controlSize(.small)
                    .disabled(modelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(text(.modelReset)) { saveModel(nil) }
                    .controlSize(.small)
            }
            // Three controls under one label -- see the API key row above.
            .accessibilityElement(children: .contain)
        }

        Text(String(
            format: text(.modelExplanationFormat),
            agentConfiguration.provider.defaultModel,
            agentConfiguration.provider.modelEnvironmentVariable ?? ""
        ))
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
    }

    // MARK: - Bindings

    /// Reads/writes `AGENT_PROVIDER` in the same `.env` the key field itself
    /// writes to. A plain `@State` can't own this the way it owns
    /// `apiKeyDraft`: the value has to come back out of `agentConfiguration`
    /// (the single source of truth both apps re-read) rather than drift from
    /// it.
    private var providerBinding: Binding<AgentProvider> {
        Binding(
            get: { agentConfiguration.provider },
            set: { newProvider in
                guard newProvider != agentConfiguration.provider else { return }
                DotEnv.write(key: "AGENT_PROVIDER", value: newProvider.rawValue, to: AgentConfiguration.writableEnvFile)
                // Both drafts are provider-specific (an OpenAI key or model
                // typed before switching to Anthropic belongs to neither field
                // once the switch happens), so they're cleared the same way a
                // successful save clears them.
                apiKeyDraft = ""
                modelDraft = ""
                apiKeyMessage = nil
                agentConfiguration = .load()
            }
        )
    }

    /// `CODING_AGENT`, the variable `code_editor` has always read.
    /// Same write-and-reload round trip as the pickers above: an environment
    /// variable or a nearer `.env` can outrank what was just written, and the
    /// picker should show what actually resolved.
    private var permissionModeBinding: Binding<AgentPermissionMode> {
        Binding(
            get: { AgentConfiguration.permissionMode() },
            set: { mode in
                DotEnv.write(
                    key: AgentPermissionMode.environmentVariable,
                    value: mode.rawValue,
                    to: AgentConfiguration.writableEnvFile
                )
                agentConfiguration = AgentConfiguration.load()
            }
        )
    }

    private var codingAgentBinding: Binding<CodingAgentKind> {
        Binding(
            get: { agentConfiguration.codingAgent },
            set: { newKind in
                guard newKind != agentConfiguration.codingAgent else { return }
                DotEnv.write(key: "CODING_AGENT", value: newKind.rawValue, to: AgentConfiguration.writableEnvFile)
                agentConfiguration = .load()
            }
        )
    }

    private var apiKeyStatus: String {
        if let message = apiKeyMessage { return message }
        guard let source = agentConfiguration.keySource else {
            // Missing is only a problem where a turn needs one. For a CLI it
            // is the ordinary case: the program is already logged in.
            return text(agentConfiguration.requiresCredential ? .apiKeyMissing : .apiKeyOptionalForCLI)
        }
        return String(format: text(.apiKeySourceFormat), source.displayName)
    }

    /// Passing nil removes the assignment, which is how the Remove button
    /// falls back to whatever other source (an env var, the project's .env)
    /// was being shadowed. Writes the *selected* provider's key variable, so
    /// saving while Anthropic is selected can never clobber an OpenAI key
    /// sitting in the same file.
    private func saveAPIKey(_ key: String?) {
        guard let keyVariable = agentConfiguration.writableCredentialEnvironmentVariable else { return }
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = AgentConfiguration.writableEnvFile
        guard DotEnv.write(key: keyVariable, value: trimmed?.isEmpty == false ? trimmed : nil, to: target) else {
            apiKeyMessage = text(.apiKeySaveFailed)
            return
        }
        apiKeyDraft = ""
        // Re-read rather than assumed: the field only wins if nothing with
        // higher precedence is already supplying a key, and saying "saved"
        // while a stale env var keeps winning is the confusion keySource
        // exists to prevent.
        agentConfiguration = .load()
        apiKeyMessage = trimmed?.isEmpty == false
            ? String(format: text(.apiKeySavedFormat), target.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
            : nil
    }

    /// Same shape as `saveAPIKey`, against the provider-specific model
    /// variable. nil clears the assignment, which is what the 기본값 button
    /// does -- the resolved value then falls back to `AGENT_MODEL` or the
    /// provider's default, and the row's trailing value shows which it landed
    /// on.
    private func saveModel(_ model: String?) {
        guard let modelVariable = agentConfiguration.provider.modelEnvironmentVariable else { return }
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        DotEnv.write(
            key: modelVariable,
            value: trimmed?.isEmpty == false ? trimmed : nil,
            to: AgentConfiguration.writableEnvFile
        )
        modelDraft = ""
        agentConfiguration = .load()
    }
}
