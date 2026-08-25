//
//  FileTreeView.swift
//  Puck
//
//  Recursive file tree with client-side substring search, mirroring
//  workspace's own FileTree.tsx behavior (full eager tree, not lazy/
//  virtualized -- WorkspaceFileService.listTree already walks the whole
//  project up front). Directories/files come pre-sorted from the service;
//  this view doesn't re-sort.
//
//  A real List(_:children:selection:) with .listStyle(.sidebar), not a
//  hand-rolled OutlineGroup+manual row backgrounds -- native macOS code
//  editors (CodeEdit, whose own CodeEditSourceEditor this app already
//  embeds; Xcode; Finder) all get their navigator's selection highlight,
//  hover state, and disclosure triangles from this exact system component
//  rather than reimplementing them, and so does this one now.
//

import SwiftUI

struct FileTreeView: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    let entries: [FileTreeEntry]
    let onOpen: (String) -> Void
    /// Project-relative path to git's single letter for it -- M, A, D. Empty
    /// when the project is not a repository, or before the first read.
    ///
    /// On the tree rather than only in the git tab: which files a turn
    /// touched is the question the tree is being looked at with, and having
    /// to switch tabs to answer it means holding two lists in your head.
    var changedPaths: [String: String] = [:]
    /// What a right-click can do. Nil in a tree that only browses -- the
    /// detached window's, for one -- so the menu is absent rather than
    /// present and inert.
    /// The file the editor is showing, so the tree points at it. Xcode keeps
    /// its navigator on the file in the editor; a tree that stays where you
    /// last clicked makes you find the current file by reading.
    var activePath: String?
    var actions: FileTreeActions?

    @State private var query = ""
    /// Xcode's "modified" filter: with a git status in hand, the useful
    /// question in a big project is usually "what did this turn touch".
    @State private var changedOnly = false
    @State private var selection: String?
    /// The row a name is being typed for, and what kind of thing the typing
    /// will produce. One prompt for renaming and both kinds of creation:
    /// all three ask for exactly one name.
    @State private var prompt: NamePrompt?
    /// The row whose Delete was picked, held until the confirmation is
    /// answered. Deleting is the one action here with no undo inside the app.
    @State private var pendingDeletion: FileTreeEntry?
    @Environment(\.clientPalette) private var palette

    private var filtered: [FileTreeEntry] {
        var result = entries
        if changedOnly {
            result = Self.keepingChanged(result, changedPaths: changedPaths)
        }
        guard !query.isEmpty else { return result }
        return Self.filter(result, query: query.lowercased())
    }

    var body: some View {
        VStack(spacing: 0) {
            List(filtered, children: \.children, selection: $selection) { entry in
                row(for: entry)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onChange(of: selection) { _, newValue in
                guard let newValue, Self.entry(at: newValue, in: filtered)?.kind != .directory else { return }
                onOpen(newValue)
            }
            // Under the tree, where Xcode keeps its navigator's filter: the
            // list is what the column is for, and chrome above it is chrome
            // between you and the first file.
            Divider()
            filterBar
        }
        .background(palette.surface)
        // Follows the editor rather than the last click. Guarded on being
        // different, or this would fight the user's own selection every time
        // the tree redrew.
        .onChange(of: activePath) { _, newValue in
            guard let newValue, newValue != selection else { return }
            selection = newValue
        }
        // On the whole tree, not only on a row: making a file at the top
        // level means right-clicking where there are no rows.
        .contextMenu {
            if let actions { creationItems(actions, parent: nil) }
        }
        .sheet(item: $prompt) { prompt in
            NamePromptSheet(prompt: prompt) { name in
                switch prompt.kind {
                case .rename: actions?.rename(prompt.path ?? "", name)
                case .newFile: actions?.create(name, false, prompt.path)
                case .newFolder: actions?.create(name, true, prompt.path)
                }
            }
        }
        .confirmationDialog(
            String(format: Strings.text(.explorerDeleteTitleFormat), pendingDeletion?.name ?? ""),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { entry in
            Button(Strings.text(.explorerDelete), role: .destructive) { actions?.trash(entry.path) }
            Button(Strings.text(.commonCancel), role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            Text(Strings.text(.explorerDeleteMessage))
        }
    }

    /// New file and new folder, made inside `parent` -- the directory that
    /// was right-clicked, or the project root when the click landed on empty
    /// space or on a file.
    @ViewBuilder
    private func creationItems(_ actions: FileTreeActions, parent: String?) -> some View {
        Button(Strings.text(.explorerNewFile)) {
            prompt = NamePrompt(kind: .newFile, path: parent, initialName: "")
        }
        Button(Strings.text(.explorerNewFolder)) {
            prompt = NamePrompt(kind: .newFolder, path: parent, initialName: "")
        }
    }

    /// The row menu: what can be done to this one thing, then what can be
    /// made next to it.
    @ViewBuilder
    private func rowMenu(for entry: FileTreeEntry, actions: FileTreeActions) -> some View {
        Button(Strings.text(.explorerRename)) {
            prompt = NamePrompt(kind: .rename, path: entry.path, initialName: entry.name)
        }
        Button(Strings.text(.explorerDelete), role: .destructive) { pendingDeletion = entry }
        Divider()
        creationItems(actions, parent: entry.kind == .directory ? entry.path : nil)
        Divider()
        Button(Strings.text(.explorerRevealInFinder)) { actions.revealInFinder(entry.path) }
        Button(Strings.text(.explorerCopyPath)) { actions.copyPath(entry.path) }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .accessibilityHidden(true)
            TextField(Strings.text(.editorSearchFiles), text: $query)
                .textFieldStyle(.plain)
                .font(ClientTheme.Typography.sessionTitle)
            Button {
                changedOnly.toggle()
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(changedOnly ? palette.accent : palette.textSecondary)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(changedPaths.isEmpty)
            .opacity(changedPaths.isEmpty ? 0.35 : 1)
            .accessibilityLabel(Strings.text(.editorChangedOnly))
            // Same as the mic: on is a tint, and a tint is not a state
            // anything can read out.
            .accessibilityAddTraits(changedOnly ? .isSelected : [])
            .help(Strings.text(.editorChangedOnly))
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(palette.background)
        .clipShape(Capsule())
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    private func row(for entry: FileTreeEntry) -> some View {
        Label {
            Text(entry.name)
                .font(ClientTheme.Typography.sessionTitle)
                .lineLimit(1)
                // lineLimit alone still lets a long name push the row wider
                // than the column and get clipped at the edge. Truncating at
                // the middle keeps both the start of the name and its
                // extension, which is what identifies a file.
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(entry.name)
        } icon: {
            FileIconView(entry: entry)
        }
        .badge(badge(for: entry))
        .tag(entry.path)
        .contextMenu {
            if let actions { rowMenu(for: entry, actions: actions) }
        }
    }

    /// Git's letter for a file, or -- for a directory -- how many files under
    /// it changed. A folder that says nothing while three files inside it did
    /// is a folder you have to open to learn anything.
    private func badge(for entry: FileTreeEntry) -> Text? {
        guard !changedPaths.isEmpty else { return nil }
        if entry.kind == .directory {
            return changedCounts[entry.path].map { Text("\($0)") }
        }
        return changedPaths[entry.path].map { Text($0) }
    }

    /// How many changed files sit under each directory, counted once per
    /// change rather than once per row: scanning every changed path for every
    /// folder on screen is the product of two numbers that both get large in
    /// exactly the repositories where this is worth showing.
    private var changedCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for path in changedPaths.keys {
            var components = path.split(separator: "/").dropLast()
            var directory = ""
            while let head = components.first {
                directory = directory.isEmpty ? String(head) : directory + "/" + head
                counts[directory, default: 0] += 1
                components = components.dropFirst()
            }
        }
        return counts
    }

    private static func entry(at path: String, in entries: [FileTreeEntry]) -> FileTreeEntry? {
        for candidate in entries {
            if candidate.path == path { return candidate }
            if let children = candidate.children, let found = entry(at: path, in: children) { return found }
        }
        return nil
    }

    /// The tree with only the changed files left in it, and only the
    /// directories that lead to one.
    static func keepingChanged(_ entries: [FileTreeEntry], changedPaths: [String: String]) -> [FileTreeEntry] {
        entries.compactMap { entry -> FileTreeEntry? in
            guard let children = entry.children else {
                return changedPaths[entry.path] == nil ? nil : entry
            }
            let kept = keepingChanged(children, changedPaths: changedPaths)
            guard !kept.isEmpty else { return nil }
            var copy = entry
            copy.children = kept
            return copy
        }
    }

    private static func filter(_ entries: [FileTreeEntry], query: String) -> [FileTreeEntry] {
        entries.compactMap { entry -> FileTreeEntry? in
            if entry.name.lowercased().contains(query) { return entry }
            guard let children = entry.children else { return nil }
            let filteredChildren = filter(children, query: query)
            guard !filteredChildren.isEmpty else { return nil }
            var copy = entry
            copy.children = filteredChildren
            return copy
        }
    }
}

/// What the explorer's menu can do, handed in rather than reached for: the
/// tree draws a project it does not own, and the store that does own it is
/// the one that has to hear about a rename.
struct FileTreeActions {
    let rename: (String, String) -> Void
    let trash: (String) -> Void
    /// (name, isDirectory, parent) -- parent nil means the project root.
    let create: (String, Bool, String?) -> Void
    let revealInFinder: (String) -> Void
    let copyPath: (String) -> Void
}

/// One name, being typed for one reason.
struct NamePrompt: Identifiable {
    enum Kind {
        case rename
        case newFile
        case newFolder
    }

    let kind: Kind
    /// The thing being renamed, or the directory being created in. Nil means
    /// the project root.
    let path: String?
    let initialName: String

    var id: String { "\(kind)#\(path ?? "")" }

    var title: String {
        switch kind {
        case .rename: return Strings.text(.explorerRenameTitle)
        case .newFile: return Strings.text(.explorerNewFileTitle)
        case .newFolder: return Strings.text(.explorerNewFolderTitle)
        }
    }

    var confirmTitle: String {
        kind == .rename ? Strings.text(.explorerRename) : Strings.text(.explorerCreate)
    }
}

/// A sheet rather than an inline field in the row.
///
/// Inline editing is what Finder does and it is nicer, but a `List` row that
/// swaps its label for a `TextField` loses first responder to the list's own
/// selection handling on macOS, and the workarounds are worse than a sheet
/// that is unambiguous about what is being named.
private struct NamePromptSheet: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.dismiss) private var dismiss

    let prompt: NamePrompt
    let onConfirm: (String) -> Void

    @State private var name: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingLarge) {
            Text(prompt.title)
                .font(ClientTheme.Typography.sectionHeader)
            TextField(Strings.text(.explorerNamePlaceholder), text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(confirm)
                .frame(width: 260)
            HStack {
                Spacer()
                Button(Strings.text(.commonCancel), role: .cancel) { dismiss() }
                Button(prompt.confirmTitle, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(ClientTheme.Metrics.windowEdgePadding)
        .onAppear {
            name = prompt.initialName
            isFocused = true
        }
    }

    private func confirm() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onConfirm(trimmed)
        dismiss()
    }
}
