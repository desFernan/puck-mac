//
//  ConflictBannerView.swift
//  Puck
//
//  Shown when EditorTab.diskChanged is set -- the disk copy changed since
//  this tab last synced with it (a failed save's revision mismatch, or an
//  external edit detected while the tab was open). Exactly two resolutions,
//  no diff view: keep the in-editor draft, or discard it for what's on disk.
//

import SwiftUI

struct ConflictBannerView: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    let onKeepMine: () -> Void
    let onUseDisk: () -> Void

    @Environment(\.clientPalette) private var palette

    var body: some View {
        HStack(spacing: ClientTheme.Metrics.spacingMedium) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.statusWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.text(.editorConflictTitle))
                    .font(ClientTheme.Typography.toolLabel)
                Text(Strings.text(.editorConflictMessage))
                    .font(ClientTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(Strings.text(.editorUseDiskVersion), action: onUseDisk)
            Button(Strings.text(.editorKeepMyVersion), action: onKeepMine)
                .buttonStyle(.borderedProminent)
        }
        .padding(ClientTheme.Metrics.spacingMedium)
        .background(palette.surface)
        .clipShape(ClientTheme.Shapes.card)
        .overlay(ClientTheme.Shapes.card.stroke(palette.surfaceBorder))
        .padding(ClientTheme.Metrics.spacingMedium)
    }
}
