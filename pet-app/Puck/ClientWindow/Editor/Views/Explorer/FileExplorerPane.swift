//
//  FileExplorerPane.swift
//  Puck
//
//  The right-hand column: the project's files, and the CLI's past sessions,
//  behind a tab strip.
//
//  Split out of EditorPaneView, which used to hold the tree and the code side
//  by side. They are in different parts of the window now -- the tree on the
//  right, a file's contents beside the conversation -- so neither can own the
//  other, and both take the store from ClientWindowView.
//

import AppKit
import SwiftUI

/// What the right column is showing.
enum ExplorerTab: String, CaseIterable, Identifiable {
    case files
    case sessions
    case git

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .files: return "doc.on.doc"
        case .sessions: return "square.grid.2x2"
        case .git: return "arrow.triangle.branch"
        }
    }

    var displayName: String {
        switch self {
        case .files: return Strings.text(.explorerTabFiles)
        case .sessions: return Strings.text(.explorerTabSessions)
        case .git: return Strings.text(.explorerTabGit)
        }
    }
}

struct FileExplorerPane: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    @ObservedObject var store: EditorPaneStore
    /// Driven from the window's toolbar when there is one -- the band above
    /// this column is otherwise empty, and a switcher up there is where Xcode
    /// puts its navigator's. nil in the detached editor window, whose toolbar
    /// is not ours, and then the strip below is used instead.
    var externalTab: Binding<ExplorerTab>?

    /// Kept for the window's life rather than per workspace: which of these
    /// someone wants open is about what they are doing, not which project.
    @State private var internalTab: ExplorerTab = .files
    /// Held here so it survives a tab switch: the sessions list is built from
    /// forty transcripts' worth of filesystem reads, and rescanning them for
    /// every glance at the file tree is work nobody asked for.
    @StateObject private var sessions = AgentSessionListModel()
    /// Held here for the same reason as `sessions`: the tab `switch` destroys
    /// whichever branch is not showing, and re-running git on every glance at
    /// the file tree is work nobody asked for.
    @StateObject private var git = GitStatusModel()

    /// The switcher's state, wherever it lives.
    private var tab: Binding<ExplorerTab> { externalTab ?? $internalTab }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if externalTab == nil {
                tabStrip
                Divider()
            }
            switch tab.wrappedValue {
            case .files:
                filesTab
            case .sessions:
                AgentSessionListView(model: sessions)
            case .git:
                GitStatusView(
                    model: git,
                    projectPath: store.rootPath,
                    onOpen: { store.open(path: $0) }
                )
            }
        }
        // Under the list, where the actions that fail are: renaming onto a
        // name that exists, deleting something already gone, creating in a
        // folder that has moved. Every one of those used to set an error
        // nothing displayed, so the menu item simply appeared to do nothing.
        .safeAreaInset(edge: .bottom) {
            if let error = store.lastError {
                ExplorerErrorBanner(message: error.message) { store.lastError = nil }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // The ground reaches up into the toolbar's band, which is empty above
        // this column. The controls stay below it -- the toolbar takes every
        // click in that band -- but leaving it unpainted read as a gap
        // between the window's top and the tabs.
        .background(palette.background.ignoresSafeArea(edges: .top))
        // Read for the pane, not for the git tab: the file tree marks changed
        // files too now, so the status has to be there before anyone opens
        // that tab -- and after every write the tree hears about.
        .task(id: store.rootPath) { await git.reload(projectPath: store.rootPath) }
        .onChange(of: store.treeRevision) {
            Task { await git.reload(projectPath: store.rootPath) }
        }
    }

    /// Git's letter per changed file, keyed by project-relative path.
    private var changedPaths: [String: String] {
        guard let files = git.status?.files else { return [:] }
        return Dictionary(files.map { ($0.path, $0.displayStatus) }, uniquingKeysWith: { first, _ in first })
    }

    /// Icons rather than words. The column is 200pt and its job is the list
    /// under it; two labelled segments would take a third of the width to say
    /// what two icons say.
    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(ExplorerTab.allCases) { candidate in
                Button {
                    tab.wrappedValue = candidate
                } label: {
                    Image(systemName: candidate.symbolName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tab.wrappedValue == candidate ? palette.textPrimary : palette.textSecondary)
                        .frame(width: 34, height: 26)
                        .contentShape(.rect)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(tab.wrappedValue == candidate ? palette.accent : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.displayName)
                .help(candidate.displayName)
            }
            Spacer()
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
    }

    private var filesTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // No "파일" heading. The tab strip above already says which of the
            // three this is, and a title repeating it cost a row of the
            // column's height -- with the search field under it, three rows of
            // chrome stood between the top of the pane and the first file.
            FileTreeView(
                entries: store.tree,
                onOpen: { store.open(path: $0) },
                changedPaths: changedPaths,
                activePath: store.activeTabPath,
                actions: FileTreeActions(
                    rename: { store.rename(path: $0, to: $1) },
                    trash: { store.trash(path: $0) },
                    create: { store.create(name: $0, directory: $1, in: $2) },
                    revealInFinder: {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            URL(fileURLWithPath: store.absolutePath(for: $0)),
                        ])
                    },
                    copyPath: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.absolutePath(for: $0), forType: .string)
                    }
                )
            )
        }
    }
}

/// One line, in the pane the action was taken in. Not an alert: a name that
/// is already taken is a correction, not an interruption, and an alert for it
/// would take the keyboard away from someone in the middle of typing another.
private struct ExplorerErrorBanner: View {
    @Environment(\.clientPalette) private var palette

    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(palette.statusError)
            Text(message)
                .font(ClientTheme.Typography.caption)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.text(.commonCancel))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(palette.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.surfaceBorder).frame(height: 1)
        }
    }
}
