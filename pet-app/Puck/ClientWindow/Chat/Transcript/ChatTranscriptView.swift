//
//  ChatTranscriptView.swift
//  Puck
//
//  The conversation itself, native again (2026-08-15). Replaces chat-web's
//  ChatTranscript/MessageBubble/ToolCallCard/ToolResultRow/RunningStatusLine.
//
//  Renders ChatSession.timeline directly -- that array is already exactly what
//  a transcript needs (ChatSession folds the BridgeEvent stream into it), so
//  there is no view model between them.
//

import AppKit
import SwiftUI

struct ChatTranscriptView: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    @ObservedObject var session: ChatSession
    let onApproval: (Bool) -> Void

    var body: some View {
        if session.timeline.isEmpty && !session.isRunning {
            EmptyTranscript()
        } else {
            transcript
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // 14, and tool rows tighten to 6 against the call above them
                // (see row spacing below): a call and its result are one
                // thought, two messages are two.
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(session.timeline) { entry in
                        row(for: entry)
                            .id(entry.id)
                            .frame(maxWidth: .infinity, alignment: alignment(for: entry))
                            // A run's own rows -- the tool calls it made and
                            // the line that ends it -- read as one block under
                            // the message that caused them, rather than as
                            // separate turns.
                            .padding(.top, entry.startsNewTurn ? 6 : -6)
                    }
                    if session.isRunning {
                        RunningStatusLine()
                            .id(Self.runningRowID)
                    }
                }
                // One column for every row -- messages, tool cards, banners --
                // capped and centred, with margin outside it. Widening the
                // window widens the margin, not the lines.
                .frame(maxWidth: ClientTheme.Metrics.transcriptColumnWidth, alignment: .leading)
                .padding(.horizontal, ClientTheme.Metrics.transcriptHorizontalPadding)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: session.timeline.count) { scrollToEnd(proxy) }
            .onChange(of: session.isRunning) { scrollToEnd(proxy) }
            // The last entry grows in place while text streams in, so its
            // count never changes -- without this the view stops following
            // mid-answer, which is the whole stretch worth following.
            .onChange(of: streamingTextLength) { scrollToEnd(proxy) }
        }
    }

    private static let runningRowID = "running"

    private var streamingTextLength: Int {
        if case .assistantText(_, let text) = session.timeline.last { return text.count }
        return 0
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        let target: AnyHashable? = session.isRunning
            ? AnyHashable(Self.runningRowID)
            : session.timeline.last?.id
        guard let target else { return }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .bottom) }
    }

    private func alignment(for entry: ChatTimelineEntry) -> Alignment {
        if case .userMessage = entry { return .trailing }
        return .leading
    }

    @ViewBuilder
    private func row(for entry: ChatTimelineEntry) -> some View {
        switch entry {
        case .userMessage(_, let text):
            UserMessageBubble(text: text)

        case .assistantText(_, let text):
            AgentMessage(text: text)

        case .notice(_, let text):
            NoticeMessage(text: text)

        case .toolCall(let id, let tool, let args):
            ToolCallRow(tool: tool, args: args, result: result(forCall: id))

        case .toolResult:
            // Rendered inside its own tool_call row, correlated by id -- a
            // result on its own line would separate it from the call it
            // answers, which is the only thing that makes it readable.
            EmptyView()

        case .approvalRequested(_, let approvalId, let summary):
            // Keyed by this row's own approvalId rather than by "is anything
            // pending": with two requests in flight, the shared flag made the
            // older one look answered while it was still waiting.
            ApprovalBanner(
                summary: summary,
                state: session.approvalState(for: approvalId),
                onApproval: onApproval
            )

        case .done(_, let ok, let summary):
            // Only failures get a row. A successful run's summary *is* the
            // answer the model just gave, which is already the bubble directly
            // above -- rendering both printed every reply twice. The answer is
            // its own completion signal; a failure has nothing above it to
            // read, so that one still needs saying.
            if ok {
                EmptyView()
            } else {
                DoneRow(ok: ok, summary: summary)
            }
        }
    }

    private func result(forCall callID: String) -> ChatTimelineEntry? {
        session.timeline.first {
            if case .toolResult(let id, _, _, _, _) = $0 { return id == callID }
            return false
        }
    }
}

/// The one line a failed tool call shows without being expanded, or nil when
/// there is nothing to report.
///
/// The first line of `detail` rather than all of it: a code_editor failure's
/// detail leads with the sentence written for the user and continues with the
/// vendor's own diagnostics (an error value, a stderr tail), which belong
/// behind the disclosure triangle. Falls back to the protocol error code when
/// there is no detail at all -- "execution_failed" is thin, but it is still
/// more than a bare icon.
func toolFailureLine(ok: Bool?, error: ToolErrorCode?, detail: String?) -> String? {
    guard ok == false else { return nil }
    let firstLine = detail?
        .split(separator: "\n", omittingEmptySubsequences: true)
        .first
        .map { $0.trimmingCharacters(in: .whitespaces) }
    if let firstLine, !firstLine.isEmpty { return firstLine }
    return error?.rawValue ?? Strings.text(.chatFailed)
}

/// The keys worth showing on a collapsed tool row, in the order they are
/// looked for.
///
/// Named rather than "whichever string comes first": a JSON object's key order
/// is arbitrary, so an unordered pick would put `cwd` on one row and `command`
/// on the next row of the same tool.
let toolSummaryKeys = [
    "command", "path", "file", "task", "query", "text", "name",
    "bundle_id", "app", "url", "contains", "script",
]

/// One line's worth of what a tool was called with, or nil when there is
/// nothing worth putting on the line.
///
/// This is what lets a tool call be a line rather than a card: three
/// `read_file` rows in a column are otherwise three identical rows, and which
/// files were read is the question being asked of them.
///
/// Whitespace collapsed and cut short -- a `run_shell` command can be a
/// heredoc, and a row is a row.
func toolArgumentSummary(_ args: JSONValue?, limit: Int = 80) -> String? {
    guard case .object(let fields)? = args else { return nil }
    let named = toolSummaryKeys.compactMap { key -> String? in
        guard case .string(let value)? = fields[key] else { return nil }
        return value
    }.first
    // Nothing recognised: the alphabetically first string field, which is at
    // least the same field every time for the same tool.
    let fallback = fields.sorted { $0.key < $1.key }.compactMap { _, value -> String? in
        guard case .string(let value) = value else { return nil }
        return value
    }.first
    guard let picked = named ?? fallback else { return nil }
    let flattened = picked.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard !flattened.isEmpty else { return nil }
    return flattened.count <= limit ? flattened : String(flattened.prefix(limit)) + "…"
}

// MARK: - Rows

/// What the user said: still a balloon, still trailing, still one glance's
/// worth. It hugs its text and stops short of the full column so the two
/// sides of the conversation stay told apart by shape rather than by colour
/// alone.
///
/// Tinted rather than filled. It was a solid accent fill with white on it,
/// which at this size is a lit orange slab: the accent is the app's one loud
/// colour and a bubble sent every other turn is the last place to spend it.
/// A wash of the same hue with the ordinary text colour on top says whose
/// message it is just as clearly, and lets the reply beside it be the thing
/// being read.
///
/// A long one is folded -- see LongMessage. Nothing is lost: the model was
/// sent all of it, the whole text is one press away, and `.txt로 열기` writes
/// it out for anything that wants a file.
private struct UserMessageBubble: View {
    /// Redraws this view when the UI language changes. Needed on every view
    /// that resolves a string, not just the window root: SwiftUI skips a
    /// child whose own inputs are unchanged, and a table lookup inside `body`
    /// is not an input.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.clientPalette) private var palette

    let text: String

    @State private var isExpanded = false

    private var isLong: Bool { LongMessage.isLong(text) }
    private var shown: String { isExpanded || !isLong ? text : LongMessage.preview(of: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(shown)
                .textSelection(.enabled)
                .foregroundStyle(palette.textPrimary)
            if isLong { footer }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.accent.opacity(0.14), in: .rect(cornerRadius: 12))
        // A hairline of the real accent: the wash alone is close enough to
        // the window's own ground that the bubble loses its edge on a wide
        // window, and the edge is what makes it a bubble.
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(palette.accent.opacity(0.35), lineWidth: 1)
        }
        .frame(maxWidth: ClientTheme.Metrics.transcriptColumnWidth * 0.8, alignment: .trailing)
    }

    /// How much is folded away, and the two ways to see it.
    private var footer: some View {
        HStack(spacing: 10) {
            Text(LongMessage.summary(of: text))
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
            Button(Strings.text(isExpanded ? .chatCollapseMessage : .chatExpandMessage)) {
                isExpanded.toggle()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundStyle(palette.accent)
            Button(Strings.text(.chatOpenMessageAsFile), action: openAsFile)
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.accent)
        }
    }

    /// Writes the message out and opens it.
    ///
    /// In the customisation folder rather than a temp directory: this is a
    /// file somebody asked for, and one that vanishes on the next reboot is
    /// not one they can point anything else at. `Customisation` already owns
    /// the folder people are sent to.
    private func openAsFile() {
        do {
            let directory = Customisation.messagesDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(LongMessage.fileName())
            try text.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            AppLogger.shared.log(.error, "could not write the message out: \(error)")
        }
    }
}

/// What the agent said: no balloon at all. A reply is a short document --
/// headings, lists, code -- and a rounded rect around several hundred words
/// of it reads as a quoted card rather than as the answer. Without one it is
/// just the page, at a size meant to be read rather than skimmed.
private struct AgentMessage: View {
    let text: String

    var body: some View {
        MarkdownText(markdown: text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The app answering a slash command. Reads as the agent's own prose --
/// same markdown, same column -- but tinted, because who is speaking matters
/// when the answer is about the app rather than from the model.
private struct NoticeMessage: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    let text: String

    var body: some View {
        MarkdownText(markdown: text)
            .font(ClientTheme.Typography.transcriptBody)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .padding(.leading, ClientTheme.Metrics.spacingLarge)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.tint)
                    .frame(width: 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A tool call and, once it lands, its result.
///
/// One line, collapsed by default. It was a card -- 10pt of padding around a
/// body-sized name, its own rounded rectangle -- which is fine for the two or
/// three calls an API turn makes and is most of the transcript once a coding
/// CLI is driving: those run tools constantly, and a screen of cards with one
/// word in each pushes the conversation they belong to off the top. A line
/// with the call summarised on it says more in a fifth of the height, and the
/// arguments are still one click away.
private struct ToolCallRow: View {
    let tool: String
    let args: JSONValue?
    let result: ChatTimelineEntry?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isExpanded.toggle()
            } label: {
                header
            }
            .buttonStyle(.plain)
            failureLine
            if isExpanded { expanded }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 6))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The whole row, collapsed: what was called, and enough of what it was
    /// called with to recognise it. The argument summary is what makes a line
    /// enough -- three `read_file` rows in a column are otherwise three
    /// identical rows, and which files were read is the question being asked.
    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
                // The row says what it is; the triangle only says which way
                // it is turned.
                .accessibilityHidden(true)
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(iconStyle)
                // Decoration: the tool's name is next to it, and a failure
                // spells itself out on the line below.
                .accessibilityHidden(true)
            Text(tool)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            if let summary = toolArgumentSummary(args) {
                Text(summary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // From the middle: the ends of a path and of a command are
                    // the parts that identify it.
                    .truncationMode(.middle)
            }
            if isPending {
                ProgressView().controlSize(.mini)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }

    /// Shown collapsed, under the name: a failed call used to be an orange
    /// triangle and nothing else, with the reason behind a triangle nobody had
    /// a reason to open. Only a failure gets the second line -- a row that
    /// worked stays one line tall, which is the point of the row.
    @ViewBuilder
    private var failureLine: some View {
        if let failure = toolFailureLine(ok: ok, error: resultError, detail: resultDetail) {
            Text(failure)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
                .padding(.leading, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let args, let rendered = Self.pretty(args) {
                Text(rendered)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            if let detail = fullResultDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 18)
    }

    private var isPending: Bool { result == nil }

    private var ok: Bool? {
        if case .toolResult(_, let ok, _, _, _) = result { return ok }
        return nil
    }

    private var resultError: ToolErrorCode? {
        if case .toolResult(_, _, _, let error, _) = result { return error }
        return nil
    }

    private var resultDetail: String? {
        if case .toolResult(_, _, _, _, let detail) = result { return detail }
        return nil
    }

    /// Everything the result carried, for the expanded view.
    private var fullResultDetail: String? {
        guard result != nil else { return nil }
        let joined = [resultError?.rawValue, resultDetail].compactMap { $0 }.joined(separator: " — ")
        return joined.isEmpty ? nil : joined
    }

    private var icon: String {
        switch ok {
        case .some(true): return "checkmark.circle.fill"
        case .some(false): return "exclamationmark.triangle.fill"
        case nil: return "wrench.and.screwdriver"
        }
    }

    private var iconStyle: Color {
        switch ok {
        case .some(true): return .green
        case .some(false): return .orange
        case nil: return .secondary
        }
    }

    /// Pretty-printed with sorted keys so the same call always reads the same
    /// way -- JSON object order is otherwise arbitrary between runs.
    static func pretty(_ value: JSONValue) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct ApprovalBanner: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    let summary: String
    let state: ApprovalState
    let onApproval: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(summary, systemImage: "hand.raised.fill")
            switch state {
            case .resolved:
                Text(Strings.text(.chatApprovalAnswered))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .queued:
                Text(Strings.text(.chatApprovalRespondToPreviousFirst))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .actionable:
                HStack {
                    Button(Strings.text(.chatApprovalAllow)) { onApproval(true) }
                        .keyboardShortcut(.defaultAction)
                    Button(Strings.text(.chatApprovalDeny), role: .cancel) { onApproval(false) }
                }
            }
        }
        .padding(12)
        .background(.yellow.opacity(0.12), in: .rect(cornerRadius: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DoneRow: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    let ok: Bool
    let summary: String

    var body: some View {
        Label {
            Text(summary.isEmpty ? (Strings.text(ok ? .chatDone : .chatDoneFailed)) : summary)
        } icon: {
            Image(systemName: ok ? "checkmark.circle" : "xmark.circle")
                // Orange for a failure, the same signal a failed tool call
                // uses. This row is the only place a failed run's reason
                // appears now, so it has to be findable at caption size.
                .foregroundStyle(ok ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shown instead of an empty scroll view. Carried over from chat-web's
/// EmptyTranscript, which the native rewrite dropped -- a new chat opened onto
/// a blank rectangle with no indication it was ready for input.
private struct EmptyTranscript: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    var body: some View {
        VStack(spacing: 4) {
            Text(Strings.text(.chatEmptyTitle))
                .font(.title3.weight(.semibold))
            Text(Strings.text(.chatEmptySubtitle))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RunningStatusLine: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(Strings.text(.chatThinking))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
