//
//  SidebarRows.swift
//  Puck
//
//  The three kinds of row the chat sidebar holds: an action, a workspace and its chats, and one chat.
//
//  Split out of ChatSidebarView: it had grown to seven types and seven
//  hundred lines, and the list, the rows it holds and a sheet listing every
//  workspace are three separate things.
//

import AppKit
import SwiftUI

/// One of the things this sidebar can start. Flat, full-width and the same
/// height as every other row here, which is what makes the top of the list
/// read as a group rather than as three loose buttons.
struct SidebarActionRow: View {
    @Environment(\.clientPalette) private var palette

    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(title)
                    .font(ClientTheme.Typography.workspaceName)
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.textPrimary)
            .frame(height: 30)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// One workspace, and the chats inside it.
///
/// Clicking it opens it rather than only switching to it: the chats that
/// belong to a workspace are the reason to go there, and they used to be
/// visible only after switching -- so choosing between two workspaces meant
/// entering one to find out what was in it.
struct WorkspaceGroup: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    let workspace: ClientWorkspace
    /// nil when the workspace has no project, when it is not a repository, or
    /// when HEAD is detached -- none of which is a branch name.
    let branch: String?
    let isActive: Bool
    let sessions: [ChatSession]
    let activeSessionId: String
    @Binding var isExpanded: Bool
    let onSelectSession: (ChatSession) -> Void
    /// Chosen without a chat to land in. The list can hand this group no
    /// chats at all -- a filter that a workspace's *name* answers while none
    /// of its chats do -- and clicking it then opened the group and left the
    /// window in the workspace it was already in.
    let onSelectWorkspace: () -> Void
    /// Right-click, delete. Nil for one that cannot go -- the default
    /// workspace, which is where a deleted one's chats would have landed.
    let onDelete: (() -> Void)?
    let onDeleteSession: (ChatSession) -> Void
    let canDeleteSession: (ChatSession) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header
            if isExpanded {
                ForEach(sessions) { session in
                    ChatSessionRow(
                        session: session,
                        isActive: isActive && session.id == activeSessionId,
                        onSelect: { onSelectSession(session) }
                    )
                    // Indented under the workspace they belong to, which is
                    // what says they belong to it.
                    .padding(.leading, 12)
                    .contextMenu {
                        Button(Strings.text(.commonDelete), role: .destructive) {
                            onDeleteSession(session)
                        }
                        .disabled(!canDeleteSession(session))
                    }
                }
                if sessions.isEmpty {
                    Text(Strings.text(.chatNoSessionsHere))
                        .font(ClientTheme.Typography.sessionTitle)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.leading, 22)
                        .frame(height: 24, alignment: .leading)
                }
            }
        }
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
            // Opening a workspace is also choosing it: the first chat in it
            // is what you came for, and leaving the window on another
            // workspace while its chats are on screen is the confusion this
            // list is being rebuilt to remove.
            if isExpanded, !isActive {
                if let first = sessions.first {
                    onSelectSession(first)
                } else {
                    onSelectWorkspace()
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 12)
                    // Both decoration: the row is one button that says the
                    // workspace's name, and an arrow and a folder read out
                    // before every one of them is noise.
                    .accessibilityHidden(true)
                Image(systemName: workspace.projectPath == nil ? "bubble.left" : "folder")
                    .font(.system(size: 13))
                    .frame(width: 16)
                    .foregroundStyle(isActive ? palette.accent : palette.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(workspace.displayName)
                        .font(ClientTheme.Typography.workspaceName)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(ClientTheme.Typography.sessionTitle)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                if sessions.contains(where: { $0.isRunning }) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                        .help(Strings.text(.chatRunning))
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .sidebarRowBackground(isSelected: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(workspace.displayName)
        .help(workspace.projectPath ?? workspace.displayName)
        .contextMenu {
            // Same shape as a chat's: right-click on the row, destructive,
            // and asked about before it happens -- a workspace takes its
            // chats with it.
            if let onDelete {
                Button(Strings.text(.commonDelete), role: .destructive, action: onDelete)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isExpanded)
    }

    /// The project and the branch on one line: the sidebar is where you pick
    /// which workspace to talk in, and which branch it is on is half of what
    /// that choice means.
    private var subtitle: String? {
        let parts = [workspace.projectLabel, branch].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct ChatSessionRow: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    @ObservedObject var session: ChatSession
    let isActive: Bool
    let onSelect: () -> Void
    @Environment(\.clientPalette) private var palette

    var body: some View {
        Button(action: onSelect) {
            row
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.displayTitle)
    }

    private var row: some View {
        HStack(spacing: 6) {
            // A spinner while the turn is running, a dot once it has
            // settled, both in a box of the same size so the titles beside
            // them do not shift as runs start and finish.
            //
            // The dot pulsed instead, which is not enough to answer "is that
            // chat still working?" -- the question is being asked precisely
            // because the answer lives in a session you are not looking at.
            ZStack {
                if session.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .accessibilityLabel(Strings.text(.chatRunning))
                        .help(Strings.text(.chatRunning))
                } else {
                    StatusDotView(
                        status: dotStatus,
                        palette: palette,
                        pulses: false,
                        // Green or red is the only record of how the last run
                        // ended once the row is collapsed.
                        label: dotStatus == .error ? Strings.text(.chatFailed) : nil
                    )
                }
            }
            .frame(width: 12, height: 12)
            Text(session.displayTitle)
                .font(ClientTheme.Typography.workspaceName)
                .lineLimit(1)
            Spacer(minLength: 4)
            let relative = RelativeTime.short(since: session.lastActivityAt)
            if !relative.isEmpty {
                Text(relative)
                    .font(ClientTheme.Typography.sessionTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 28)
        .sidebarRowBackground(isSelected: isActive)
    }

    private var dotStatus: DotStatus {
        switch session.lastRunOk {
        case .some(true): return .success
        case .some(false): return .error
        case nil: return .idle
        }
    }
}
