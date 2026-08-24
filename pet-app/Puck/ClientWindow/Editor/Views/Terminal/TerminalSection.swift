//
//  TerminalSection.swift
//  Puck
//
//  The terminal's place in the editor column: a header you can grab, a shell
//  under it, and the memory of whether it was open.
//
//  Under the code rather than beside it, and in the same column: a terminal
//  belongs to the project you are looking at, and running it in a window of
//  its own is what people already do when the editor cannot offer one.
//

import SwiftUI

struct TerminalSection: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    let root: String
    @Binding var isOpen: Bool

    /// Dragged from the header, and remembered across launches like the
    /// island's height is. Clamped on read, so a value written by a version
    /// with different limits cannot leave a terminal too short to read.
    @AppStorage(TerminalSection.heightStorageKey) private var storedHeight = Double(defaultHeight)
    @State private var heightAtDragStart: CGFloat?
    /// Bumped to start a new shell in place of one that exited. The view is
    /// keyed on it, which is what makes SwiftUI build a fresh terminal rather
    /// than reuse the dead one.
    @State private var generation = 0
    /// Whether to replace a shell that exited -- see TerminalRestartPolicy,
    /// which owns the rule so it can be checked without a running terminal.
    @State private var restarts = TerminalRestartPolicy()
    @State private var lastStartedAt = Date.distantPast

    /// Written from three views -- the strip's button, the split that draws
    /// the terminal, and the window's toolbar toggle -- so the key is spelled
    /// once. Three string literals is three chances to desync a toggle from
    /// the thing it toggles, and the symptom is a button that appears to do
    /// nothing.
    static let openStorageKey = "Puck.terminalOpen"
    static let heightStorageKey = "Puck.terminalHeight"

    static let defaultHeight: CGFloat = 220
    static let minimumHeight: CGFloat = 90
    static let maximumHeight: CGFloat = 720
    static let headerHeight: CGFloat = 26

    private var height: CGFloat {
        PetTankView.clamped(storedHeight, from: Self.minimumHeight, to: Self.maximumHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            header
            Divider()
            if restarts.hasGivenUp {
                message
            } else {
                TerminalPane(root: root, palette: palette, onExit: shellExited)
                    .id("\(root)#\(generation)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { lastStartedAt = Date() }
            }
        }
        .frame(height: height + Self.headerHeight + 2)
        .background(palette.background)
    }

    /// Said once, instead of forking shells until someone closes the pane.
    private var message: some View {
        Text(Strings.text(.terminalCouldNotStart))
            .font(ClientTheme.Typography.caption)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 10)
    }

    private func shellExited() {
        switch restarts.shellExited(afterRunningFor: Date().timeIntervalSince(lastStartedAt)) {
        case .restart: generation += 1
        case .giveUp: break
        }
    }

    /// The name of the shell, a close button, and the whole strip doubling as
    /// the resize handle -- the edge between the code and the terminal is
    /// where the pointer goes to move it anyway.
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Strings.text(.terminalTitle))
                .font(ClientTheme.Typography.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button {
                isOpen = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.text(.terminalHide))
            .help(Strings.text(.terminalHide))
        }
        .padding(.horizontal, 10)
        .frame(height: Self.headerHeight)
        .contentShape(.rect)
        .onHover { inside in
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let start = heightAtDragStart ?? height
                    heightAtDragStart = start
                    // Up grows it: the header is the terminal's top edge, so
                    // the edge follows the pointer.
                    storedHeight = Double(
                        min(max(start - value.translation.height, Self.minimumHeight), Self.maximumHeight)
                    )
                }
                .onEnded { _ in heightAtDragStart = nil }
        )
    }
}
