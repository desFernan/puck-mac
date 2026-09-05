//
//  ChatSession.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  One chat session's rendered timeline, built by folding the same
//  BridgeEvent stream EventRouter reads for pet reactions into something the
//  client window (F13) can render: streaming assistant
//  text, a tool-call/result timeline correlated by id, and an approval banner.
//

import Foundation

/// One row in a chat session's timeline. toolCall/toolResult reuse the
/// protocol's own tool_use `id` as their identity (already unique per
/// session); the rest mint their own, since nothing else in the wire format
/// gives them one.
enum ChatTimelineEntry: Equatable {
    /// The user's own sent message -- BridgeEvent never carries this (it's
    /// workspace -> pet-app only), so ChatSession.appendUserMessage mints it
    /// locally the moment the store sends, rather than folding it from
    /// an event like every other case here.
    case userMessage(id: UUID, text: String)
    case assistantText(id: UUID, text: String)
    /// The app answering the user directly -- a slash command's reply. Not
    /// the agent's, and never sent to it, so it is its own case rather than
    /// an assistant message the transcript would attribute wrongly.
    case notice(id: UUID, text: String)
    case toolCall(id: String, tool: String, args: JSONValue?)
    case toolResult(id: String, ok: Bool, data: JSONValue?, error: ToolErrorCode?, detail: String?)
    case approvalRequested(id: UUID, approvalId: String, summary: String)
    case done(id: UUID, ok: Bool, summary: String)
}

extension ChatTimelineEntry {
    /// Whether this row begins a new exchange. Only what a person said, or the
    /// agent's own prose answering it, starts one; a tool call and its outcome
    /// belong to the turn that produced them.
    var startsNewTurn: Bool {
        switch self {
        case .userMessage, .assistantText, .notice: return true
        case .toolCall, .toolResult, .approvalRequested, .done: return false
        }
    }
}

extension ChatTimelineEntry: Identifiable {
    // toolCall and toolResult share the same underlying tool_use id (that's
    // the point -- it's how a view correlates them), so their *displayed
    // entry* ids need distinct prefixes or the two rows collide.
    var id: AnyHashable {
        switch self {
        case .userMessage(let id, _): return id
        case .assistantText(let id, _): return id
        case .notice(let id, _): return id
        case .toolCall(let id, _, _): return "call:\(id)"
        case .toolResult(let id, _, _, _, _): return "result:\(id)"
        case .approvalRequested(let id, _, _): return id
        // Was a fixed "done" on the assumption that agent_done happens once
        // per session. It doesn't: a session takes as many prompts as the
        // user types, and every run ends with one. Two rows sharing an id in
        // the transcript's ForEach is undefined behaviour -- what it did in
        // practice was throw the scroll position to the top of the list the
        // moment a second run finished.
        case .done(let id, _, _): return id
        }
    }
}

/// One approval the agent is blocked on. Identified by the protocol's own
/// `approval_id`: that is the id the answer has to be addressed to, and the
/// only thing that ties a banner to the request waiting behind it.
struct PendingApproval: Equatable, Identifiable {
    let approvalId: String
    let summary: String

    var id: String { approvalId }
}

/// What an approval banner can do right now.
enum ApprovalState: Equatable {
    /// The one the buttons act on -- the oldest request still unanswered.
    case actionable
    /// Asked for, but an older request is still in front of it.
    case queued
    /// Answered, or abandoned when the run ended.
    case resolved
}

/// One chat session under a workspace. `id`/`workspaceId` are the protocol's
/// own ids (both "default" for the always-present casual session -- see
/// ClientWindowStore's composite-key note on why that's not a collision).
final class ChatSession: ObservableObject, Identifiable {
    let id: String
    let workspaceId: String
    let origin: SessionOrigin
    @Published var title: String
    @Published private(set) var timeline: [ChatTimelineEntry] = []
    /// Every approval still waiting on the user, oldest first.
    ///
    /// A queue rather than a single slot: the coding agent batches parallel
    /// tool calls, so two `session/request_permission` calls can be in flight
    /// at once. With one slot the second overwrote the first, the UI could
    /// then only ever produce an answer for the second, and the first request's
    /// caller waited on an answer that could no longer be given -- which stalls
    /// the agent for the whole tool timeout. Answered oldest-first so the two
    /// buttons always mean one unambiguous request.
    @Published private(set) var pendingApprovals: [PendingApproval] = []
    @Published private(set) var isRunning = false

    /// How many runs this chat is waiting on.
    ///
    /// A count rather than a flag, because there can genuinely be two. Sending
    /// while the agent is working supersedes the first run (AgentRunHandle),
    /// and a superseded run keeps going until it next looks at
    /// `Task.isCancelled` -- so it ends *after* the run that replaced it
    /// started, and it ends the way every run ends, with `agent_done`.
    ///
    /// Against a flag that was the bug: the older run's ending turned off the
    /// newer run's spinner and cleared the approval it was waiting on, so the
    /// chat sat still and silent while the agent was in fact working, and an
    /// approval banner vanished with nothing left to answer it.
    private var runsInFlight = 0

    /// The request the approval buttons answer, or nil when none is waiting.
    var pendingApproval: PendingApproval? { pendingApprovals.first }

    /// When this session last saw any agent event. Drives the sidebar's relative
    /// time (see RelativeTime) -- nothing else in the app tracked time before v3.
    @Published private(set) var lastActivityAt: Date?

    /// Outcome of the most recent completed run, or nil if none has completed.
    /// Derived from the timeline rather than stored: `.done` already carries `ok`,
    /// and a second copy could disagree with it.
    var lastRunOk: Bool? {
        for entry in timeline.reversed() {
            if case .done(_, let ok, _) = entry { return ok }
        }
        return nil
    }

    /// Whether the name is one this app picked for itself, and may therefore
    /// replace. False for a task session the agent named through
    /// open_task_session -- renaming that out from under its owner is not a
    /// refinement, it is a loss. True for every chat that still carries a
    /// default name, the always-present one included: a sidebar of rows all
    /// called the same thing is one you cannot navigate.
    let isAutoTitled: Bool

    /// Set once the model has named this chat after the first exchange, so a
    /// second run does not pay for a second title.
    private(set) var hasTopicTitle = false

    init(id: String, workspaceId: String, title: String, origin: SessionOrigin) {
        self.id = id
        self.workspaceId = workspaceId
        self.title = title
        self.origin = origin
        self.isAutoTitled = Self.isDefaultTitle(title)
    }

    /// A chat read back off disk -- see ChatArchive.
    ///
    /// Everything a live chat derives from what has happened to it is passed
    /// in instead, because none of it can be derived after the fact:
    /// `isAutoTitled` was decided from the title this chat *started* with and
    /// a restored one no longer has that, and `lastActivityAt` is when the
    /// agent last said something rather than when the file was read.
    ///
    /// `isRunning` and `pendingApprovals` are deliberately not among them.
    /// Both belong to a process that has gone: a restored spinner would never
    /// stop, and a restored approval would offer two buttons with nothing
    /// left to receive the answer.
    init(
        id: String,
        workspaceId: String,
        title: String,
        origin: SessionOrigin,
        isAutoTitled: Bool,
        hasTopicTitle: Bool,
        lastActivityAt: Date?,
        timeline: [ChatTimelineEntry]
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.title = title
        self.origin = origin
        self.isAutoTitled = isAutoTitled
        self.hasTopicTitle = hasTopicTitle
        self.lastActivityAt = lastActivityAt
        self.timeline = timeline
    }

    /// What the model has to be told again to carry a restored chat on.
    ///
    /// The prose only -- what was asked and what was answered. Tool calls are
    /// left out on purpose: a provider rejects a stack whose assistant message
    /// asks for tools that nothing replied to, and rebuilding those pairs
    /// exactly across a restart is a way to break every message sent in the
    /// chat from then on. What a continued conversation needs is what was
    /// said, and that is what this is.
    var spokenHistory: [(isUser: Bool, text: String)] {
        timeline.compactMap { entry in
            switch entry {
            case .userMessage(_, let text):
                return text.isEmpty ? nil : (true, text)
            case .assistantText(_, let text):
                return text.isEmpty ? nil : (false, text)
            case .notice, .toolCall, .toolResult, .approvalRequested, .done:
                return nil
            }
        }
    }

    /// The opening question and the answer to it -- the material a title is
    /// read off. Nil until both halves exist: a chat with nothing said in it,
    /// or one whose run produced only tool calls, has no topic to name yet.
    ///
    /// The *last* thing the agent said before the next question, not the
    /// first. A run that uses tools usually opens with a placeholder ("확인해
    /// 볼게요") and says what it actually found at the end -- naming the chat
    /// off the opener would title every one of them after the throat-clearing.
    var firstExchange: (user: String, reply: String)? {
        var user: String?
        var reply: String?
        for entry in timeline {
            switch entry {
            case .userMessage(_, let text):
                // The second question begins a turn this title is not about.
                if user != nil { return reply.map { (user!, $0) } }
                user = text
            case .assistantText(_, let text):
                guard user != nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                reply = text
            default:
                continue
            }
        }
        guard let user, let reply else { return nil }
        return (user, reply)
    }

    /// Renames the chat after what the model read the exchange to be about.
    /// Ignored for a chat this app did not name, and ignored twice over --
    /// the first topic stands, later runs do not re-title.
    func applyTopicTitle(_ topic: String) {
        guard isAutoTitled, !hasTopicTitle else { return }
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hasTopicTitle = true
        title = Self.title(fromFirstMessage: trimmed)
    }

    /// The name a chat carries until something is said in it. Matched on
    /// rather than a separate "has been named" flag: the placeholder *is* the
    /// state, and a flag could disagree with the title shown in the sidebar.
    static let placeholderTitle = "새 대화"

    /// The always-present entry point under every workspace.
    ///
    /// Like `placeholderTitle`, this is a stored, matched-on value rather
    /// than display text -- `isAutoTitled` and `ClientWindowStore` compare
    /// against both. Translating what gets stored would strand every chat
    /// created under the other language, so the language only enters at
    /// `displayTitle`.
    static let casualTitle = "일상 대화"

    /// What SessionRegistry stores for a session created without a name.
    /// Stored, not displayed, for the same reason as the two above.
    static let untitledTitle = "새 세션"

    /// The title to show. The two titles this app assigns itself are
    /// language-independent on disk (see `casualTitle`), so this is where
    /// they become words; anything the user or the agent named stands as-is.
    var displayTitle: String {
        switch title {
        case Self.placeholderTitle: return Strings.text(.chatNewSession)
        case Self.casualTitle: return Strings.text(.chatCasualSession)
        case Self.untitledTitle: return Strings.text(.sessionDefaultTitle)
        default: return title
        }
    }

    /// The app's own reply to a slash command. Does not name the chat the way
    /// `appendUserMessage` does: a session called "/help" tells the sidebar
    /// nothing about what the conversation is.
    func appendNotice(_ text: String) {
        timeline.append(.notice(id: UUID(), text: text))
    }

    /// Local echo of the user's own send -- called by ClientWindowStore, not
    /// folded from a BridgeEvent (protocol never sends the user's own text
    /// back).
    ///
    /// Also where a chat gets its name: a sidebar of rows all called the
    /// placeholder is one you cannot navigate. Only while the title is still the
    /// placeholder, which leaves alone both the casual session (`casualTitle`,
    /// the always-present entry point under every workspace) and a task
    /// session the agent already named through open_task_session -- the latter
    /// matters because moveTurnToTaskSession feeds it the message that started
    /// it, which would otherwise overwrite the agent's title immediately.
    func appendUserMessage(_ text: String) {
        if Self.isDefaultTitle(title) {
            title = Self.title(fromFirstMessage: text)
        }
        timeline.append(.userMessage(id: UUID(), text: text))
    }

    /// Whether this is still a name the app gave it rather than one the
    /// conversation earned.
    ///
    /// All three count now. The casual session was left out because it is the
    /// always-present entry point under every workspace -- but every workspace
    /// having one row called the same thing is exactly the sidebar you cannot
    /// navigate, and being the entry point is about its id, not its name.
    static func isDefaultTitle(_ title: String) -> Bool {
        title == placeholderTitle || title == casualTitle || title == untitledTitle
    }

    /// What the chat turned out to be about, taken from the first thing said
    /// in it. Deliberately not a model call: naming is wanted the instant the
    /// message is sent, and a summary that costs a round trip would land after
    /// the answer it was meant to label -- for a one-line sidebar row the
    /// opening line is as good a topic as a paraphrase of it.
    ///
    /// First line only, whitespace collapsed: a pasted stack trace or a
    /// numbered list of repro steps is a paragraph, and a row is one line.
    static func title(fromFirstMessage text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let collapsed = firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return placeholderTitle }
        guard collapsed.count > Self.titleLimit else { return collapsed }
        return collapsed.prefix(Self.titleLimit).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Chosen against the sidebar's own width (180-280pt): long enough to tell
    /// two chats apart, short enough that the row truncates rarely.
    private static let titleLimit = 28

    /// The send landed, so the agent owes an answer -- shown as the thinking
    /// row until the first text_chunk replaces it -- the user should see that
    /// the agent is working while it generates a reply, not a blank gap.
    ///
    /// Set here rather than waiting for agent_thinking: that event is produced
    /// by the agent, put on the socket, and relayed back to this app, so the
    /// window would sit with no feedback for the whole round trip -- and if
    /// the agent's very first act is a slow model call, that is the exact
    /// stretch the user is staring at.
    func markWaitingForAgent() {
        runsInFlight += 1
        isRunning = true
    }

    /// A run this chat never saw start -- the first thing heard from it is
    /// the agent already working. Counted as one so its `agent_done` balances
    /// rather than driving the count negative.
    private func noteRunStartedElsewhere() {
        guard runsInFlight == 0 else { return }
        runsInFlight = 1
    }

    /// Folds one BridgeEvent into the timeline. Caller (ClientWindowStore) is
    /// responsible for routing the event to the right session by
    /// workspace_id/session_id first -- this type has no notion of "is this
    /// event mine".
    func apply(_ event: BridgeEvent) {
        lastActivityAt = Date()
        switch event {
        case .agentThinking:
            noteRunStartedElsewhere()
            isRunning = true

        case .textChunk(let text):
            noteRunStartedElsewhere()
            isRunning = true
            if case .assistantText(let entryId, let existing) = timeline.last {
                timeline[timeline.count - 1] = .assistantText(id: entryId, text: existing + text)
            } else {
                timeline.append(.assistantText(id: UUID(), text: text))
            }

        case .toolCall(let id, let tool, let args, _):
            // `detail` (curated pet-reaction summary) is intentionally dropped
            // here -- the chat view shows the tool's real args instead.
            timeline.append(.toolCall(id: id, tool: tool, args: args))

        case .toolResult(let id, let ok, let data, let error, let detail):
            timeline.append(.toolResult(id: id, ok: ok, data: data, error: error, detail: detail))

        case .awaitApproval(let summary, let approvalId):
            // Re-broadcast of an id already queued is not a second request --
            // and it is not a second card either. The transcript printed the
            // same approval twice while only one of them could be answered,
            // which reads as a second thing to decide.
            guard !pendingApprovals.contains(where: { $0.approvalId == approvalId }) else { break }
            pendingApprovals.append(PendingApproval(approvalId: approvalId, summary: summary))
            timeline.append(.approvalRequested(id: UUID(), approvalId: approvalId, summary: summary))
            // The run is stopped until this is answered, and the banner it is
            // waiting behind arrives without taking focus -- so behind a
            // screen reader the turn simply goes quiet. High priority because
            // nothing else the chat says is more urgent than the thing it has
            // stopped for. Announced once per request, which the guard above
            // is also what guarantees.
            VoiceOverAnnouncer.announce(
                String(format: Strings.text(.a11yApprovalNeededFormat), summary),
                priority: .high
            )

        case .agentDone(let ok, let summary):
            // One run ended, which is not the same as this chat being idle --
            // see `runsInFlight`. A superseded turn ends while the turn that
            // replaced it is still working, and it must not answer for it.
            runsInFlight = max(0, runsInFlight - 1)
            isRunning = runsInFlight > 0
            // Only once nothing is left running. The side holding the
            // requests fails whatever it still owns (AgentHost), so no answer
            // is silently dropped here -- but clearing the queue while a
            // newer run is waiting on it takes away a banner that has an
            // answer coming.
            if runsInFlight == 0 { pendingApprovals.removeAll() }
            timeline.append(.done(id: UUID(), ok: ok, summary: summary))

        case .petSays:
            // The pet's speech bubble only. The caption is a shortened echo of
            // what the model is already saying in text_chunk, so putting it in
            // the timeline too would print every tour stop twice.
            break
        }
    }

    /// The user answered this request; it stops being pending and the next one
    /// in line becomes actionable. Unknown ids are ignored -- an answer that
    /// crossed with `agent_done` is not an error.
    func resolveApproval(approvalId: String) {
        pendingApprovals.removeAll { $0.approvalId == approvalId }
    }

    func approvalState(for approvalId: String) -> ApprovalState {
        guard let index = pendingApprovals.firstIndex(where: { $0.approvalId == approvalId }) else {
            return .resolved
        }
        return index == 0 ? .actionable : .queued
    }
}
