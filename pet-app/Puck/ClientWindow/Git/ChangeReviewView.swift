//
//  ChangeReviewView.swift
//  Puck
//
//  What the agent changed, before you decide to keep it.
//
//  Opened from the row a finished editing run leaves in the transcript. A
//  sheet rather than another column: reviewing is a thing you do once, all
//  the way through, and then close -- and the window already has five things
//  across it.
//
//  Reverting is per file. See DiffReader.revert for why not per hunk.
//

import SwiftUI

@MainActor
final class ChangeReviewModel: ObservableObject {
    @Published private(set) var files: [FileDiff] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    /// Which files are open. Everything is closed to begin with: a run that
    /// touched twelve files opens onto twelve expanded diffs otherwise, and
    /// the list of what changed is the thing being looked at first.
    @Published var expanded: Set<String> = []

    /// How the diff is read, and how a file is put back. Injected so the
    /// model can be driven without a repository -- what is worth testing here
    /// is the reloading and the expansion, not git.
    private let read: (String) async -> [FileDiff]
    private let revertFile: (String, String, Bool) async -> Bool

    init(
        read: @escaping (String) async -> [FileDiff] = { path in
            await Task.detached(priority: .utility) { DiffReader.changes(projectPath: path) }.value
        },
        revertFile: @escaping (String, String, Bool) async -> Bool = { path, project, untracked in
            await Task.detached(priority: .utility) {
                DiffReader.revert(path: path, projectPath: project, isUntracked: untracked)
            }.value
        }
    ) {
        self.read = read
        self.revertFile = revertFile
    }

    var addedCount: Int { files.reduce(0) { $0 + $1.addedCount } }
    var removedCount: Int { files.reduce(0) { $0 + $1.removedCount } }

    func reload(projectPath: String?) async {
        guard let projectPath else {
            files = []
            hasLoaded = true
            return
        }
        isLoading = true
        files = await read(projectPath)
        isLoading = false
        hasLoaded = true
    }

    /// Puts one file back and takes it out of the list.
    ///
    /// Removed here rather than by re-reading: a reload costs a subprocess
    /// and, on a large project, long enough to see. The file is gone from the
    /// diff by definition -- that is what reverting it means.
    func revert(_ file: FileDiff, projectPath: String) async {
        // A file with no committed version is untracked, which is the same
        // thing `git status` calls "?" -- and the two are reverted
        // differently, so the distinction has to survive to here. A diff
        // against /dev/null has no removed lines and no previous path.
        let untracked = file.previousPath == nil && file.removedCount == 0 && !file.hasNoVisibleChange
            && file.hunks.allSatisfy { $0.lines.allSatisfy { $0.kind != .removed && $0.kind != .context } }
        guard await revertFile(file.path, projectPath, untracked) else { return }
        files.removeAll { $0.path == file.path }
        expanded.remove(file.path)
    }

    func toggle(_ path: String) {
        if expanded.contains(path) { expanded.remove(path) } else { expanded.insert(path) }
    }
}

struct ChangeReviewView: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    let projectPath: String?
    @StateObject private var model = ChangeReviewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 720, idealWidth: 940, minHeight: 460, idealHeight: 620)
        .background(palette.background)
        .task(id: projectPath) { await model.reload(projectPath: projectPath) }
    }

    private var header: some View {
        HStack(spacing: ClientTheme.Metrics.spacingMedium) {
            Text(Strings.text(.reviewTitle))
                .font(ClientTheme.Typography.workspaceName)
                .foregroundStyle(palette.textPrimary)
            if !model.files.isEmpty {
                Text(String(
                    format: Strings.text(.reviewCountFormat),
                    "\(model.files.count)", "\(model.addedCount)", "\(model.removedCount)"
                ))
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Button(Strings.text(.reviewRefresh)) {
                Task { await model.reload(projectPath: projectPath) }
            }
            .disabled(model.isLoading)
            Button(Strings.text(.commonDone)) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(ClientTheme.Metrics.spacingMedium)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && !model.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.files.isEmpty {
            ContentUnavailableView(
                Strings.text(.reviewNothingChanged),
                systemImage: "checkmark.circle",
                description: Text(Strings.text(.reviewNothingChangedDetail))
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingSmall) {
                    ForEach(model.files) { file in
                        fileSection(file)
                    }
                }
                .padding(ClientTheme.Metrics.spacingMedium)
            }
        }
    }

    private func fileSection(_ file: FileDiff) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            fileHeader(file)
            if model.expanded.contains(file.path) {
                if file.isBinary {
                    Text(Strings.text(.reviewBinaryFile))
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .padding(ClientTheme.Metrics.spacingMedium)
                } else if file.hasNoVisibleChange {
                    Text(Strings.text(.reviewNoContentChange))
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .padding(ClientTheme.Metrics.spacingMedium)
                } else {
                    ForEach(file.hunks) { hunk in
                        hunkView(hunk)
                    }
                }
            }
        }
        .background(palette.surface, in: .rect(cornerRadius: ClientTheme.Metrics.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ClientTheme.Metrics.cardCornerRadius)
                .strokeBorder(palette.surfaceBorder, lineWidth: 1)
        }
    }

    private func fileHeader(_ file: FileDiff) -> some View {
        HStack(spacing: ClientTheme.Metrics.spacingSmall) {
            Button {
                model.toggle(file.path)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.expanded.contains(file.path) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(file.path)
                        .font(ClientTheme.Typography.mono)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        // From the middle: the ends of a path identify it.
                        .truncationMode(.middle)
                    if let previous = file.previousPath {
                        Text(String(format: Strings.text(.reviewRenamedFromFormat), previous))
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            if file.addedCount > 0 {
                Text("+\(file.addedCount)").font(.caption).foregroundStyle(palette.statusSuccess)
            }
            if file.removedCount > 0 {
                Text("-\(file.removedCount)").font(.caption).foregroundStyle(palette.statusError)
            }
            Button(Strings.text(.reviewRevert)) {
                guard let projectPath else { return }
                Task { await model.revert(file, projectPath: projectPath) }
            }
            .controlSize(.small)
            .help(Strings.text(.reviewRevertHelp))
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
        .padding(.vertical, ClientTheme.Metrics.spacingSmall)
    }

    private func hunkView(_ hunk: DiffHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header)
                .font(.caption.monospaced())
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                .padding(.vertical, 3)
                .background(palette.background.opacity(0.6))
            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
    }

    private func lineView(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            // The two numbers, so a line in the review can be found in the
            // file. Fixed width, right aligned: ragged gutters are unreadable
            // at a glance, which is the only way anyone reads these.
            Text(line.oldLine.map(String.init) ?? "")
                .frame(width: 44, alignment: .trailing)
            Text(line.newLine.map(String.init) ?? "")
                .frame(width: 44, alignment: .trailing)
            Text(marker(for: line.kind))
                .frame(width: 14, alignment: .center)
            Text(line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(ClientTheme.Typography.mono)
        .foregroundStyle(colour(for: line.kind))
        .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
        .background(background(for: line.kind))
    }

    private func marker(for kind: DiffLine.Kind) -> String {
        switch kind {
        case .added: return "+"
        case .removed: return "-"
        case .context: return " "
        }
    }

    private func colour(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return palette.statusSuccess
        case .removed: return palette.statusError
        case .context: return palette.textSecondary
        }
    }

    private func background(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return palette.statusSuccess.opacity(0.10)
        case .removed: return palette.statusError.opacity(0.10)
        case .context: return .clear
        }
    }
}
