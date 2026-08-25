//
//  AgentSessionListView.swift
//  Puck
//
//  Past conversations with the coding CLI, newest first.
//
//  Loaded off the main thread and only when this tab is looked at: the
//  transcripts live outside any project Puck knows about, and scanning them
//  is filesystem work nobody asked for while they are reading code.
//

import SwiftUI

@MainActor
final class AgentSessionListModel: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var isLoading = false

    private var hasLoaded = false

    /// Idempotent, so appearing on screen twice does not scan twice. The
    /// refresh button is the way to ask again.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    func reload() async {
        isLoading = true
        let found = await Task.detached(priority: .utility) { AgentSessionHistory.discover() }.value
        sessions = found
        isLoading = false
    }
}

struct AgentSessionListView: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette
    /// Owned by FileExplorerPane, not by this view. A `switch` on the tab
    /// destroys whichever branch is not showing, so a model held here would
    /// be rebuilt -- and rescan every transcript -- each time someone looked
    /// at the file list and came back.
    @ObservedObject var model: AgentSessionListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if model.sessions.isEmpty {
                Text(model.isLoading ? Strings.text(.sessionsLoading) : Strings.text(.sessionsEmpty))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(ClientTheme.Metrics.spacingLarge)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.sessions) { session in
                            row(session)
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .task { await model.loadIfNeeded() }
    }

    private var header: some View {
        HStack {
            Text(Strings.text(.sessionsHeader))
                .font(ClientTheme.Typography.sectionHeader)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await model.reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(model.isLoading)
            .accessibilityLabel(Strings.text(.sessionsRefresh))
            .help(Strings.text(.sessionsRefresh))
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
        .padding(.vertical, ClientTheme.Metrics.spacingMedium)
    }

    private func row(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.title)
                .font(ClientTheme.Typography.sessionTitle)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: ClientTheme.Metrics.spacingSmall) {
                Text(session.projectLabel)
                    .font(ClientTheme.Typography.caption)
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
                Text(RelativeTime.short(since: session.modifiedAt))
                    .font(ClientTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            if let model = session.model {
                Text(model)
                    .font(ClientTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
        .padding(.vertical, ClientTheme.Metrics.spacingMedium)
        .contentShape(.rect)
        // Finder rather than the editor: a transcript lives under ~/.claude,
        // outside any project the editor can open.
        .onTapGesture {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.transcriptPath)])
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(Strings.text(.skillReveal))) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.transcriptPath)])
        }
        .help(session.workingDirectory)
    }
}
