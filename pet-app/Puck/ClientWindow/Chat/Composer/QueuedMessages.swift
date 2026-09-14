//
//  QueuedMessages.swift
//  Puck
//
//  What is waiting for the run in flight to finish.
//
//  Above the composer rather than in the transcript: it has not been said
//  yet. A queued message in the timeline would read as part of the
//  conversation the agent is having, and the agent has not seen it.
//
//  Each one can be taken back, because the common reason for a second message
//  is realising the first was wrong -- and a queue you can only add to is one
//  people work around by cancelling the whole run.
//

import SwiftUI

struct QueuedMessagesView: View {
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    let messages: [String]
    let onRemove: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text(.queuedMessagesHeader))
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
            ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(ClientTheme.Typography.sessionTitle)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button {
                        onRemove(index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(text(.queuedMessageRemove))
                    .accessibilityLabel(text(.queuedMessageRemove))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(palette.surface, in: .rect(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func text(_ key: L10nKey) -> String {
        Strings.text(key, language: localization.language)
    }
}
