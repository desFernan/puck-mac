//
//  EditorTabStripView.swift
//  Puck
//
//  Design system v2 (2026-08-14): switched internal spacing/padding to
//  ClientTheme.Metrics (tab strip pattern).
//  stripHeight/tabHeight stay plain literals rather than derived from a
//  spacing token -- they're this view's own dimensions, not a spacing
//  concern, and coupling them to a generic token would let retuning that
//  token silently resize the tab strip.
//

import SwiftUI

struct EditorTabStripView: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    let tabs: [EditorTab]
    let activeTabPath: String?
    let canSave: Bool
    let onSelect: (String) -> Void
    let onClose: (String) -> Void
    let onSave: () -> Void
    /// Moving between what is already open, and jumping inside it. Optional
    /// because the detached window builds this strip too and hands them in
    /// the same way; nil simply leaves the buttons out.
    var onPreviousTab: (() -> Void)?
    var onNextTab: (() -> Void)?
    var onGoToLine: (() -> Void)?
    var onFind: (() -> Void)?
    var onOpenQuickly: (() -> Void)?
    /// Hides the code column without closing what is open in it. Nil in the
    /// detached window, which has nothing to collapse into.
    var onCollapse: (() -> Void)?
    @Environment(\.clientPalette) private var palette

    private static let stripHeight: CGFloat = 32

    private static let tabHeight: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(tabs) { tab in
                        tabButton(for: tab)
                    }
                }
            }
            if let onPreviousTab, let onNextTab { tabNavigationButtons(previous: onPreviousTab, next: onNextTab) }
            if let onOpenQuickly { openQuicklyButton(onOpenQuickly) }
            if let onFind { findButton(onFind) }
            if let onGoToLine { goToLineButton(onGoToLine) }
            saveButton
            if let onCollapse { collapseButton(onCollapse) }
        }
        .frame(height: Self.stripHeight)
        .background(palette.surface)
    }

    /// Puts the file away and gives the width back to the conversation.
    /// Distinct from closing the tab: the file stays open, so coming back to
    /// it does not mean finding it again.
    private func collapseButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.right.to.line")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: Self.stripHeight, height: Self.stripHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.text(.editorCollapse))
        .help(Strings.text(.editorCollapse))
    }

    /// ⌘⇧[ and ⌘⇧], where every editor with tabs puts them. Buttons rather
    /// than shortcuts alone for the same reason the save button is one: the
    /// strip scrolls once a few files are open, and a shortcut nothing shows
    /// is a shortcut nobody finds.
    private func tabNavigationButtons(
        previous: @escaping () -> Void,
        next: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            stripButton(
                systemImage: "chevron.left",
                label: Strings.text(.editorPreviousTab),
                shortcut: "[",
                action: previous
            )
            stripButton(
                systemImage: "chevron.right",
                label: Strings.text(.editorNextTab),
                shortcut: "]",
                action: next
            )
        }
        .disabled(tabs.count < 2)
        .opacity(tabs.count < 2 ? 0.35 : 1)
    }

    /// ⌘⇧O. Not disabled with nothing open: reaching a file is exactly what
    /// this is for when nothing is.
    private func openQuicklyButton(_ action: @escaping () -> Void) -> some View {
        stripButton(
            systemImage: "text.magnifyingglass",
            label: Strings.text(.editorOpenQuickly),
            shortcut: "o",
            action: action
        )
    }

    /// ⌘F, into the editor's own find bar.
    private func findButton(_ action: @escaping () -> Void) -> some View {
        stripButton(
            systemImage: "magnifyingglass",
            label: Strings.text(.editorFind),
            shortcut: "f",
            modifiers: .command,
            action: action
        )
        .disabled(activeTabPath == nil)
        .opacity(activeTabPath == nil ? 0.35 : 1)
    }

    /// ⌘L. Disabled with nothing open, which is also what keeps the shortcut
    /// a silent no-op there rather than a beep.
    private func goToLineButton(_ action: @escaping () -> Void) -> some View {
        stripButton(
            systemImage: "arrow.right.to.line",
            label: Strings.text(.editorGoToLine),
            shortcut: "l",
            modifiers: .command,
            action: action
        )
        .disabled(activeTabPath == nil)
        .opacity(activeTabPath == nil ? 0.35 : 1)
    }

    private func stripButton(
        systemImage: String,
        label: String,
        shortcut: KeyEquivalent,
        modifiers: EventModifiers = [.command, .shift],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: Self.stripHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.textSecondary)
        .keyboardShortcut(shortcut, modifiers: modifiers)
        .accessibilityLabel(label)
        .help(label)
    }

    /// Always present, not only while something is dirty: it is where ⌘S is
    /// declared, and a shortcut that exists only once the user has already
    /// typed is a shortcut nobody discovers. Disabled it is also what makes
    /// ⌘S a silent no-op with nothing to save instead of a system beep.
    private var saveButton: some View {
        Button(action: onSave) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .foregroundStyle(canSave ? palette.textPrimary : palette.textSecondary)
        .opacity(canSave ? 1 : 0.35)
        .keyboardShortcut("s", modifiers: .command)
        .help(Strings.text(.editorSaveHint))
        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
        .accessibilityIdentifier("editor.save")
    }

    private func tabButton(for tab: EditorTab) -> some View {
        let isActive = tab.path == activeTabPath
        return HStack(spacing: ClientTheme.Metrics.spacingSmall) {
            Text((tab.path as NSString).lastPathComponent)
                .font(ClientTheme.Typography.sessionTitle)
                .lineLimit(1)
            if tab.isDirty {
                StatusDotView(status: .active, palette: palette, diameter: 5, pulses: false)
            }
            Button(action: { onClose(tab.path) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
        .frame(height: Self.tabHeight)
        .background(isActive ? palette.background : Color.clear)
        .foregroundStyle(isActive ? palette.textPrimary : palette.textSecondary)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(tab.path) }
    }
}
