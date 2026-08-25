//
//  ChatInputBar.swift
//  Puck
//
//  The composer: one box holding the message and everything sent with it.
//
//  Split out of ChatPaneView, which held the window's whole chat side in one
//  file: the conversation, the box you type into and a sheet for making a
//  workspace are three separate things.
//

import AppKit
import SwiftUI

/// The composer: one box holding the message and everything sent with it.
///
/// It used to be a field with a round arrow button floating beside it, and
/// the settings that shape a turn -- how much thinking, which model -- lived
/// only behind slash commands nobody discovers. They are on the box now, in
/// the corners where every chat app of this kind puts them: what to attach on
/// the left, what to answer with on the right.
///
/// `TextField(axis: .vertical)` grows with its content and keeps the stock
/// focus ring and text behaviours, which a custom NSTextView wrapper would
/// have to reproduce.
struct ChatInputBar: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    let isRunning: Bool
    let onSend: (String, [Attachment]) -> Void
    let onCancel: () -> Void
    /// Whether pet-app is holding its push-to-talk down for us -- as pet-app
    /// reports it, not as this view asked. A press with no speech-recognition
    /// permission is spent on the system prompt and records nothing, and a
    /// button lit on its own say-so was telling the user something untrue.
    var isListening = false
    /// Asks pet-app to hold its push-to-talk down or let it up. The chat
    /// window has no microphone; see BridgeMessage.voiceListen.
    var onVoiceListening: ((Bool) -> Void)?

    @State private var text = ""
    @State private var attachments: [Attachment] = []
    /// Read once and after every change rather than on each render: both come
    /// off disk (a `.env` and the environment), and `body` runs on every
    /// keystroke.
    @State private var effort = AgentConfiguration.effort()
    @State private var configuration = AgentConfiguration.load()
    /// How much the agent may do on its own this turn. The setting that
    /// changes most often and matters most per message, which is why it is
    /// what the control says rather than which CLI is answering.
    @State private var permissions = AgentConfiguration.permissionMode()
    @FocusState private var isFocused: Bool

    /// The height of the controls along the bottom of the box, and of the
    /// stop button. Everything here is a hit target at arm's length rather
    /// than a glyph to squint at.
    static let controlHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Above the field, not below it: the field is already at the
            // bottom of the window, and a list under it would open off
            // screen.
            if !suggestions.isEmpty {
                SlashSuggestionList(suggestions: suggestions) { suggestion in
                    text = suggestion.completion
                    isFocused = true
                }
            }
            composer
        }
        .frame(maxWidth: ClientTheme.Metrics.transcriptColumnWidth)
        .padding(.horizontal, ClientTheme.Metrics.transcriptHorizontalPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .onAppear {
            isFocused = true
            // Re-read on every appearance, not only when this view is first
            // built: the same three settings are on the settings window, and
            // a composer built this morning went on claiming whatever was set
            // then.
            refreshSettings()
        }
        // A hold that outlives the window is a microphone left open. The
        // window can close, or the workspace switch out from under this view,
        // while pet-app is still holding its push-to-talk down for us.
        .onDisappear {
            guard isListening else { return }
            onVoiceListening?(false)
        }
    }

    /// Offered while a command is being typed, and only then -- see
    /// SlashCommand.suggestions.
    private var suggestions: [SlashSuggestion] {
        SlashCommand.suggestions(for: text)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !attachments.isEmpty { attachmentRow }
            TextField(Strings.text(.chatComposerPlaceholder), text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(ClientTheme.Typography.transcriptBody)
                // Three lines' worth of room before anything is typed, so the
                // box has the presence the reference's does rather than
                // growing into it.
                .lineLimit(3...12)
                .focused($isFocused)
                // Return sends. There is no button to press instead, which is
                // the point: the arrow was a control the eye had to find for
                // something the hand was already doing.
                .onSubmit(send)
            controlRow
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 8)
        // Rounder and quieter than the old box: the reference's composer is a
        // soft-edged well the controls sit inside, not a bordered field with
        // a button beside it.
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(isFocused ? AnyShapeStyle(.tint.opacity(0.6)) : AnyShapeStyle(.separator), lineWidth: 1)
        )
    }

    /// What is going with the message, above the text it belongs to.
    private var attachmentRow: some View {
        HStack(spacing: 4) {
            ForEach(attachments, id: \.path) { attachment in
                HStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.system(size: 9))
                        // The word "photo" spoken before every file name adds
                        // nothing: the name is right there and says more.
                        .accessibilityHidden(true)
                    Text((attachment.path as NSString).lastPathComponent)
                        .font(ClientTheme.Typography.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        attachments.removeAll { $0.path == attachment.path }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Strings.text(.a11yRemoveAttachment))
                    .help(Strings.text(.a11yRemoveAttachment))
                }
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(palette.surface, in: .rect(cornerRadius: ClientTheme.Metrics.rowCornerRadius))
            }
            Spacer(minLength: 0)
        }
    }

    private var controlRow: some View {
        HStack(spacing: 6) {
            attachButton
            Spacer(minLength: 0)
            // Model and effort as one control, the way the reference has it:
            // they are one question -- what should answer this -- and two
            // adjacent menus of two words each read as clutter.
            settingsMenu
            micButton
            if isRunning { stopButton }
        }
        .font(ClientTheme.Typography.sessionTitle)
        .foregroundStyle(palette.textSecondary)
    }

    /// "파일 수정까지 · 보통 ∨" -- the mode the agent is running under and how
    /// much thinking it is doing, which are the two answers to "what happens
    /// when I press return". Which CLI is behind it changes once a month and
    /// lives in Settings; the mode changes several times an hour.
    private var settingsMenu: some View {
        Menu {
            Section(Strings.text(.permissionsLabel)) {
                ForEach(AgentPermissionMode.allCases) { mode in
                    Button(mode.displayName) { run("/permissions \(mode.rawValue)") }
                }
            }
            Section(Strings.text(.chatEffort)) {
                ForEach(AgentEffort.allCases) { level in
                    Button(level.displayName) { run("/effort \(level.rawValue)") }
                }
            }
            if configuration.provider.supportsModelSelection {
                Section(Strings.text(.chatModel)) {
                    ForEach(
                        AgentProvider.selectableModels(for: configuration.provider, configured: configuration.model),
                        id: \.self
                    ) { model in
                        Button(model) { run("/model \(model)") }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(modeLabel)
                    .foregroundStyle(palette.textPrimary)
                Text(effort.displayName)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .frame(height: Self.controlHeight)
            .contentShape(.rect)
        }
        // Two words and an arrow, which read as two unrelated labels. Named
        // for what the menu *is*, with what it currently says as its value --
        // which is also the one place the mode is stated out loud.
        .accessibilityLabel(Strings.text(.a11yAgentSettings))
        .accessibilityValue("\(modeLabel), \(effort.displayName)")
        // `.borderlessButton` throws the label away: it renders as an
        // NSPopUpButton, which takes a title and nothing else, so the two
        // words and the chevron here came out as one word with the system's
        // own arrow on the wrong side. `.button` draws what it was given.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// The permission mode, or the model where the model is the thing being
    /// chosen -- an API provider has no CLI to permit anything to.
    private var modeLabel: String {
        configuration.provider == .cli ? permissions.displayName : configuration.model
    }

    /// pet-app does the listening. Lit while it is, and drawn as a waveform
    /// then -- the same two glyphs the reference shows, one state each.
    private var micButton: some View {
        Button {
            onVoiceListening?(!isListening)
        } label: {
            Image(systemName: isListening ? "waveform" : "mic")
                .font(.system(size: 14, weight: .medium))
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .contentShape(.rect)
        }
        .foregroundStyle(isListening ? AnyShapeStyle(.tint) : AnyShapeStyle(palette.textSecondary))
        .disabled(onVoiceListening == nil)
        .accessibilityLabel(Strings.text(.chatVoice))
        // Listening or not is a waveform instead of a microphone and a tint,
        // and nothing else -- so pressed/unpressed is the whole state of the
        // button as far as a screen reader is concerned.
        .accessibilityAddTraits(isListening ? .isSelected : [])
        .help(Strings.text(.chatVoice))
    }

    /// Images only: an attachment travels as `type: "image"` on the wire, and
    /// offering a picker that accepts anything would promise more than the
    /// protocol carries.
    private var attachButton: some View {
        Button(action: chooseAttachment) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .contentShape(.rect)
        }
        .accessibilityLabel(Strings.text(.chatAttach))
        .help(Strings.text(.chatAttach))
    }

    private var stopButton: some View {
        Button(role: .cancel, action: onCancel) {
            Image(systemName: "stop.fill")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .background(palette.surface, in: .rect(cornerRadius: ClientTheme.Metrics.rowCornerRadius))
                .contentShape(.rect)
        }
        .accessibilityLabel(Strings.text(.chatStop))
        .help(Strings.text(.chatStop))
    }

    /// Sends a slash command as if it had been typed, then re-reads what it
    /// wrote -- the runner reports the value it read back, and so does this.
    private func run(_ command: String) {
        onSend(command, [])
        refreshSettings()
    }

    /// All three come off disk -- a `.env` and the environment -- so they are
    /// read at moments, never in `body`, which runs on every keystroke.
    private func refreshSettings() {
        effort = AgentConfiguration.effort()
        configuration = AgentConfiguration.load()
        permissions = AgentConfiguration.permissionMode()
    }

    private func chooseAttachment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        let chosen = panel.urls.map { Attachment(path: $0.path) }
        // No duplicates: picking the same file twice sends it twice.
        attachments += chosen.filter { candidate in !attachments.contains { $0.path == candidate.path } }
        isFocused = true
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func send() {
        // An attachment on its own is a message: "look at this" with the
        // picture doing the talking.
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        onSend(trimmed, attachments)
        text = ""
        attachments = []
    }
}

/// What can be typed next, while a command is being typed.
///
/// A plain list rather than a popover: the commands are few, the field is
/// right below it, and a popover over a window that is mostly conversation
/// hides the thing being talked about.
struct SlashSuggestionList: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    let suggestions: [SlashSuggestion]
    let onPick: (SlashSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    onPick(suggestion)
                } label: {
                    HStack(spacing: 8) {
                        Text("/\(suggestion.name)")
                            .font(ClientTheme.Typography.mono)
                            .foregroundStyle(palette.textPrimary)
                        Text(suggestion.summary)
                            .font(ClientTheme.Typography.sessionTitle)
                            .foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .background(palette.surface)
        .clipShape(.rect(cornerRadius: ClientTheme.Metrics.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ClientTheme.Metrics.cardCornerRadius)
                .strokeBorder(palette.surfaceBorder, lineWidth: 1)
        }
    }
}
