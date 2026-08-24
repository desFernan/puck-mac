//
//  OpenQuicklyView.swift
//  Puck
//
//  Type a few letters, get the file. The explorer is a tree, and a tree is
//  the slow way to reach a file whose name you already know -- in a project
//  of any size it is several disclosure triangles and a scroll.
//

import SwiftUI

struct OpenQuicklyView: View {
    /// Every file in the project, as relative paths.
    let paths: [String]
    let onOpen: (String) -> Void
    let onDismiss: () -> Void

    @Environment(\.clientPalette) private var palette
    @ObservedObject private var localization = Localization.shared

    @State private var query = ""
    @FocusState private var isFieldFocused: Bool

    /// Enough to choose from without turning into a second file tree.
    private static let shown = 8

    private var results: [String] {
        FuzzyPathMatch.matches(query, in: paths, limit: Self.shown)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(Strings.text(.editorOpenQuicklyPlaceholder), text: $query)
                .textFieldStyle(.plain)
                .font(ClientTheme.Typography.sessionTitle)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                .frame(height: 36)
                .focused($isFieldFocused)
                // Return takes the first result, which is the whole point of
                // ranking them: the answer is already under the cursor.
                .onSubmit { if let first = results.first { open(first) } }
            if !results.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(results, id: \.self) { path in
                            row(path)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .background(palette.surface)
        .overlay {
            RoundedRectangle(cornerRadius: ClientTheme.Metrics.panelCornerRadius)
                .strokeBorder(palette.surfaceBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: ClientTheme.Metrics.panelCornerRadius))
        .frame(width: 380)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .onAppear { isFieldFocused = true }
        .onExitCommand(perform: onDismiss)
    }

    private func row(_ path: String) -> some View {
        Button {
            open(path)
        } label: {
            HStack(spacing: ClientTheme.Metrics.spacingSmall) {
                Text((path as NSString).lastPathComponent)
                    .font(ClientTheme.Typography.workspaceName)
                    .foregroundStyle(palette.textPrimary)
                // The directory, dimmer: three files called index.ts are told
                // apart by where they are, not by what they are called.
                Text((path as NSString).deletingLastPathComponent)
                    .font(ClientTheme.Typography.sessionTitle)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
            .frame(height: 26)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func open(_ path: String) {
        onOpen(path)
        onDismiss()
    }
}
