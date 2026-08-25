//
//  CodeSplitView.swift
//  Puck
//
//  A file's contents, opened beside the conversation rather than in a pane
//  of its own.
//
//  Clicking a file in the explorer splits the agent's column instead of
//  replacing it: the reason to look at the file is usually what was just
//  said about it, and a layout that hides one to show the other makes you
//  choose. The tab strip and the unsaved-close prompt came with it from
//  EditorPaneView, which no longer has a code half.
//

import CodeEditSourceEditor
import SwiftUI

struct CodeSplitView: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared

    @Environment(\.clientPalette) private var palette

    @ObservedObject var store: EditorPaneStore
    /// A trailing closure at the call site, so the split reads as "code, and
    /// here is how to put it away".
    var onCollapse: (() -> Void)?


    /// ⌘L's field, and what is typed into it. Held here rather than in the
    /// store: where the caret should go is the store's business, but whether
    /// a one-line prompt is on screen is this view's.
    /// Where the caret is in the file being edited, for the status line.
    /// Cleared when the tab changes: it belongs to one file.
    @State private var cursor: CursorPosition.Position?
    @State private var isOpenQuicklyShowing = false
    @State private var isGoToLineShowing = false
    @State private var goToLineDraft = ""
    @FocusState private var isGoToLineFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            EditorTabStripView(
                tabs: store.openTabs,
                activeTabPath: store.activeTabPath,
                canSave: store.canSaveActiveTab,
                onSelect: { store.select(path: $0) },
                onClose: { store.requestClose(path: $0) },
                onSave: { store.saveActiveTab() },
                onPreviousTab: { store.selectPreviousTab() },
                onNextTab: { store.selectNextTab() },
                onGoToLine: showGoToLine,
                onFind: { store.showFind() },
                onOpenQuickly: { isOpenQuicklyShowing = true },
                onCollapse: onCollapse
            )
            Divider()
            // Only when it says something the tab does not. A file at the
            // project root has a one-component path, and drawing it under a
            // tab with the same name on it is the same word twice.
            if let path = store.activeTabPath, path.contains("/") {
                breadcrumb(path)
                Divider()
            }
            if isGoToLineShowing { goToLineBar }
            EditorContentHostView(store: store) { cursor = $0 }
            if store.activeTabPath != nil {
                Divider()
                statusLine
            }
        }
        .onChange(of: store.activeTabPath) { cursor = nil }
        // Over the code rather than in a sheet: a sheet takes the window,
        // and this is a place to glance at the project, not a modal task.
        .overlay(alignment: .top) {
            if isOpenQuicklyShowing {
                OpenQuicklyView(
                    paths: FileTreeEntry.flattenedPaths(store.tree),
                    onOpen: { store.open(path: $0) },
                    onDismiss: { isOpenQuicklyShowing = false }
                )
                .padding(.top, 40)
            }
        }
        // Closing a tab with unsaved edits asks instead of dropping them.
        // A prompt rather than a silent save: the tab is a live view of a
        // file the agent also writes, and quietly committing a half-finished
        // draft on the way out is its own kind of damage. Three answers, in
        // the order macOS puts them.
        .confirmationDialog(
            Strings.text(.editorUnsavedTitle),
            isPresented: Binding(
                get: { store.pendingClosePath != nil },
                set: { if !$0 { store.cancelPendingClose() } }
            ),
            titleVisibility: .visible
        ) {
            Button(Strings.text(.editorSaveAndClose)) { store.confirmPendingCloseSaving() }
            Button(Strings.text(.editorDiscard), role: .destructive) { store.confirmPendingCloseDiscarding() }
            Button(Strings.text(.commonCancel), role: .cancel) { store.cancelPendingClose() }
        } message: {
            Text(pendingCloseMessage)
        }
    }

    /// One field, above the code. Escape puts it away; return jumps and puts
    /// it away, because a go-to-line box that stays open is one more thing to
    /// dismiss before typing again.
    private var goToLineBar: some View {
        HStack(spacing: 6) {
            Text(Strings.text(.editorGoToLine))
                .font(ClientTheme.Typography.caption)
                .foregroundStyle(palette.textSecondary)
            TextField(Strings.text(.editorGoToLinePlaceholder), text: $goToLineDraft)
                .textFieldStyle(.plain)
                .font(ClientTheme.Typography.caption)
                .foregroundStyle(palette.textPrimary)
                .frame(width: 60)
                .focused($isGoToLineFocused)
                .onSubmit(jumpToTypedLine)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(palette.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.surfaceBorder).frame(height: 1)
        }
        .onExitCommand { isGoToLineShowing = false }
    }

    private func showGoToLine() {
        goToLineDraft = ""
        isGoToLineShowing = true
        isGoToLineFocused = true
    }

    private func jumpToTypedLine() {
        // Nothing typed, or nothing numeric: leave the field alone rather
        // than closing it, so a typo does not cost the prompt as well.
        guard let line = Int(goToLineDraft.trimmingCharacters(in: .whitespaces)) else { return }
        store.goToLine(line)
        isGoToLineShowing = false
    }

    /// Under the code: what language it is being read as, and where the
    /// caret is. Both were things the pane knew and never said -- the
    /// language decides the highlighting, and a line number is what an error
    /// message from anywhere else is expressed in.
    private var statusLine: some View {
        HStack(spacing: 8) {
            if let path = store.activeTabPath, let language = EditorLanguage.displayName(forPath: path) {
                Text(language)
            }
            Spacer(minLength: 0)
            if let cursor {
                Text(verbatim: "\(cursor.line):\(cursor.column)")
                    .monospacedDigit()
            }
        }
        .font(ClientTheme.Typography.sessionTitle)
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(palette.surface)
    }

    /// The path of the file being edited, above it.
    ///
    /// The tab shows a file name, which is all that fits and not enough:
    /// three `index.ts` tabs are three identical labels, and in a project the
    /// interesting part of a path is the directories. Separators are drawn as
    /// chevrons so the components read as steps rather than as one long
    /// string.
    private func breadcrumb(_ path: String) -> some View {
        let components = path.split(separator: "/").map(String.init)
        return HStack(spacing: 3) {
            ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(palette.textSecondary.opacity(0.5))
                        // A separator between path components, spoken as
                        // "chevron right" between every one of them.
                        .accessibilityHidden(true)
                }
                Text(component)
                    .foregroundStyle(index == components.count - 1 ? palette.textPrimary : palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .font(ClientTheme.Typography.sessionTitle)
        .lineLimit(1)
        .truncationMode(.head)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .help(path)
    }

    private var pendingCloseMessage: String {
        guard let path = store.pendingClosePath else { return "" }
        return String(format: Strings.text(.editorUnsavedMessageFormat), (path as NSString).lastPathComponent)
    }
}
