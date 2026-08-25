//
//  GitStatusView.swift
//  Puck
//
//  What has changed in the project, beside the conversation that changed it.
//
//  Read-only. This answers "what did that turn actually touch", which is the
//  question an agent editing files creates; committing and pushing from a
//  sidebar is a different kind of action and is not wired to anything here.
//

import SwiftUI

@MainActor
final class GitStatusModel: ObservableObject {
    /// How a status is read. Injectable so the coalescing below can be tested
    /// without a repository and without forking git -- the rule it enforces
    /// is about overlapping calls, not about what git says.
    private let read: (String) async -> GitStatus?

    init(read: @escaping (String) async -> GitStatus? = { path in
        await Task.detached(priority: .utility) { GitStatusReader.read(projectPath: path) }.value
    }) {
        self.read = read
    }

    @Published private(set) var status: GitStatus?
    @Published private(set) var isLoading = false
    /// Distinguishes "not a repository" from "not looked yet", which read the
    /// same on screen and mean different things.
    @Published private(set) var hasLoaded = false

    /// Set while a read is running, so an ask that arrives during one is
    /// remembered rather than run alongside it.
    private var wantsAnotherRead = false

    func reload(projectPath: String?) async {
        guard let projectPath else {
            status = nil
            hasLoaded = true
            return
        }
        // An agent writing a file at a time asks for this once per write, and
        // each read forks two git processes over the whole worktree. Running
        // them concurrently is both slower and pointless -- only the last
        // answer is the true one -- so a read in flight collects the asks
        // that arrive during it and runs once more at the end.
        guard !isLoading else {
            wantsAnotherRead = true
            return
        }
        isLoading = true
        repeat {
            wantsAnotherRead = false
            status = await read(projectPath)
        } while wantsAnotherRead
        hasLoaded = true
        isLoading = false
    }
}

struct GitStatusView: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    @ObservedObject var model: GitStatusModel
    let projectPath: String?
    /// Opening a changed file is the point of listing it.
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let status = model.status {
                branchLine(status)
                Divider()
                if status.files.isEmpty {
                    message(Strings.text(.gitClean))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(status.files) { file in
                                row(file)
                            }
                        }
                    }
                }
            } else if model.hasLoaded {
                message(Strings.text(.gitNotARepository))
            } else {
                message(Strings.text(.sessionsLoading))
            }
            Spacer(minLength: 0)
        }
        .task(id: projectPath) { await model.reload(projectPath: projectPath) }
    }

    private var header: some View {
        HStack {
            Text(Strings.text(.gitHeader))
                .font(ClientTheme.Typography.sectionHeader)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await model.reload(projectPath: projectPath) }
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

    private func branchLine(_ status: GitStatus) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: ClientTheme.Metrics.spacingSmall) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(status.branch ?? Strings.text(.gitDetached))
                    .font(ClientTheme.Typography.toolLabel)
                    .lineLimit(1)
                Spacer()
                if status.addedLines > 0 || status.deletedLines > 0 {
                    Text("+\(status.addedLines)")
                        .foregroundStyle(palette.statusSuccess)
                    Text("-\(status.deletedLines)")
                        .foregroundStyle(palette.statusError)
                }
            }
            .font(ClientTheme.Typography.caption)
            if let upstream = status.upstream {
                HStack(spacing: ClientTheme.Metrics.spacingSmall) {
                    Text("→ \(upstream)")
                        .lineLimit(1)
                    if status.ahead > 0 { Text("↑\(status.ahead)") }
                    if status.behind > 0 { Text("↓\(status.behind)") }
                }
                .font(ClientTheme.Typography.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
        .padding(.bottom, ClientTheme.Metrics.spacingMedium)
    }

    private func row(_ file: GitFileChange) -> some View {
        HStack(spacing: ClientTheme.Metrics.spacingMedium) {
            Text(file.displayStatus)
                .font(ClientTheme.Typography.mono)
                .foregroundStyle(colour(for: file))
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text((file.path as NSString).lastPathComponent)
                    .font(ClientTheme.Typography.sessionTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text((file.path as NSString).deletingLastPathComponent)
                    .font(ClientTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
            if let added = file.addedLines, let deleted = file.deletedLines {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("+\(added)").foregroundStyle(palette.statusSuccess)
                    Text("-\(deleted)").foregroundStyle(palette.statusError)
                }
                .font(ClientTheme.Typography.caption)
            }
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
        .padding(.vertical, ClientTheme.Metrics.spacingSmall)
        .contentShape(.rect)
        .onTapGesture { onOpen(file.path) }
        // Same reason as the editor's tabs: a tap gesture is not a control
        // as far as VoiceOver is concerned, so the row could be read and
        // never opened.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(Strings.text(.a11yOpenFile))) { onOpen(file.path) }
        .help(file.path)
    }

    private func colour(for file: GitFileChange) -> Color {
        switch file.displayStatus {
        case "A": return palette.statusSuccess
        case "D": return palette.statusError
        default: return palette.statusWarning
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(ClientTheme.Metrics.spacingLarge)
    }
}
