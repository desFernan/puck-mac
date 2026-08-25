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

// MARK: - Rows

/// What the user said: still a balloon, still trailing, still one glance's
/// worth. It hugs its text and stops short of the full column so the two
/// sides of the conversation stay told apart by shape rather than by colour
/// alone.
private struct UserMessageBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.tint, in: .rect(cornerRadius: 12))
            .foregroundStyle(.white)
            .frame(maxWidth: ClientTheme.Metrics.transcriptColumnWidth * 0.8, alignment: .trailing)
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

/// A tool call and, once it lands, its result. Collapsed by default: the
/// arguments matter when something went wrong and are noise otherwise.
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

private struct ToolCallRow: View {
    let tool: String
    let args: JSONValue?
    let result: ChatTimelineEntry?

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
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
            .padding(.top, 4)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundStyle(iconStyle)
                        // Decoration: the tool's name is next to it, and the
                        // outcome is spelled out in the row below.
                        .accessibilityHidden(true)
                    Text(tool)
                        .font(.system(.body, design: .monospaced))
                    if isPending {
                        ProgressView().controlSize(.small)
                    }
                }
                // Shown collapsed, not inside the disclosure body: a failed
                // call used to be a red triangle next to the tool's name and
                // nothing else, with the reason hidden behind a triangle the
                // user had no reason to think held anything.
                if let failure = toolFailureLine(ok: ok, error: resultError, detail: resultDetail) {
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
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
