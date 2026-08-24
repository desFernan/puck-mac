//
//  WorkspaceBrowserSheet.swift
//  Puck
//
//  Every workspace at once, for choosing between more of them than the sidebar column can show.
//
//  Split out of ChatSidebarView: it had grown to seven types and seven
//  hundred lines, and the list, the rows it holds and a sheet listing every
//  workspace are three separate things.
//

import AppKit
import SwiftUI

/// Every workspace at once, with what each one is bound to.
///
/// The sidebar lists them too, but it lists them in a 220pt column beside
/// everything else; this is the view for choosing between more of them than
/// that column can show, and for making one.
struct WorkspaceBrowserSheet: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var store: ClientWindowStore
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Strings.text(.chatWorkspaces))
                    .font(ClientTheme.Typography.sectionHeader)
                Spacer()
                Button(Strings.text(.chatNewWorkspace), systemImage: "plus", action: onCreate)
            }
            .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
            .padding(.vertical, ClientTheme.Metrics.spacingMedium)
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.workspaces) { workspace in
                        row(workspace)
                    }
                }
                .padding(ClientTheme.Metrics.spacingMedium)
            }
            Divider()
            HStack {
                Spacer()
                Button(Strings.text(.commonClose)) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(ClientTheme.Metrics.spacingLarge)
        }
        .frame(width: 460, height: 420)
        .background(palette.background)
    }

    private func row(_ workspace: ClientWorkspace) -> some View {
        Button {
            if let session = store.sessions(in: workspace.id).first {
                store.selectSession(workspaceId: workspace.id, sessionId: session.id)
            } else {
                store.activeWorkspaceId = workspace.id
            }
            dismiss()
        } label: {
            HStack(spacing: ClientTheme.Metrics.spacingMedium) {
                Image(systemName: workspace.projectPath == nil ? "bubble.left" : "folder")
                    .font(.system(size: 15))
                    .foregroundStyle(workspace.id == store.activeWorkspaceId ? palette.accent : palette.textSecondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.displayName)
                        .font(ClientTheme.Typography.workspaceName)
                        .foregroundStyle(palette.textPrimary)
                    Text(workspace.projectPath ?? Strings.text(.chatNoProjectLinked))
                        .font(ClientTheme.Typography.sessionTitle)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 0)
                Text(String(store.sessions(in: workspace.id).count))
                    .font(ClientTheme.Typography.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
            .padding(.vertical, 6)
            .sidebarRowBackground(isSelected: workspace.id == store.activeWorkspaceId)
        }
        .buttonStyle(.plain)
    }
}
