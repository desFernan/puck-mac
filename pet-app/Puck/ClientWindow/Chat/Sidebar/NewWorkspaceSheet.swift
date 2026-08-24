//
//  NewWorkspaceSheet.swift
//  Puck
//
//  Naming a new workspace and pointing it at a project folder.
//
//  Split out of ChatPaneView, which held the window's whole chat side in one
//  file: the conversation, the box you type into and a sheet for making a
//  workspace are three separate things.
//

import AppKit
import SwiftUI

/// The new-workspace sheet. The folder itself is chosen with NSOpenPanel -- SwiftUI
/// has no directory picker, and the panel is what the web version reached
/// through the bridge to get anyway.
struct NewWorkspaceSheet: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    @ObservedObject var store: ClientWindowStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var projectPath: String?

    var body: some View {
        Form {
            TextField(Strings.text(.chatWorkspaceName), text: $name)
            LabeledContent(Strings.text(.chatProjectFolder)) {
                HStack {
                    Text(projectPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? Strings.text(.chatNoFolderSelected))
                        .foregroundStyle(projectPath == nil ? .secondary : .primary)
                        .truncationMode(.head)
                        .lineLimit(1)
                    Button(Strings.text(.commonChoose), action: chooseFolder)
                }
            }
            Text(Strings.text(.chatProjectFolderExplanation))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button(Strings.text(.commonCancel), role: .cancel) { dismiss() }
                Button(Strings.text(.commonCreate)) {
                    store.requestNewWorkspace(name: name, projectPath: projectPath)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 420)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectPath = url.path
        // Naming a workspace after its folder is what the user would type
        // anyway; still editable above.
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = url.lastPathComponent
        }
    }
}
