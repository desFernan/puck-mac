//
//  EventRouter.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Maps protocol 3.2 state events to FSM/SFX reactions
//
//  This is a pure decision function — it does not touch CharacterController or
//  SFXTriggering directly. Wiring `reaction(for:)`'s output to real, shared
//  state instances happens at app-bootstrap time (once CharacterController is
//  constructed with the FSM's long-lived state set); creating a fresh state
//  instance per event here would break CharacterController's same-state no-op
//  check and reset per-state timers/data on every repeated event.

/// The FSM's states, named without reference to their concrete StateHandler
/// instances so EventRouter and the states themselves can request a
/// transition without holding one.
enum StateKind: Equatable, CaseIterable {
    case idle
    case walk
    case climb
    case walkOnTop
    case fall
    case land
    case moveTo
    case point
    case type
    case listen
    case reactClick
    case reactDrag
    /// The twirl after the user finishes petting the pet's head (2026-07-29).
    /// Never reachable from a socket event -- see EventRouter.reaction(for:).
    case spin
    /// F12 (2026-07-29, optional ball-toy interaction): chase a thrown ball,
    /// then kick it away. Never reachable from a socket event -- see
    /// EventRouter.reaction(for:), which has no case producing these.
    case chaseBall
    /// A couple of small pops before the final kick-away (2026-07-29, more
    /// interaction variety), between chaseBall arriving and kickBall.
    case juggleBall
    case kickBall
    /// F3 ceiling-crawling (2026-07-29): climb straight up to the ceiling,
    /// then crawl there upside-down. Reached only from WanderScheduler's
    /// idle roll, never from a socket event.
    case climbToCeiling
    case ceiling
    /// Double-tap "petting" interaction (2026-07-29). Never reachable from a socket event, same as
    /// chaseBall/kickBall.
    case petting
    /// F13 (2026-07-29): holds still while the Option+Shift+Space client
    /// window is open, same "capture then restore" pattern as Listen (F7).
    /// Never reachable from a socket event.
    case pinned
    /// Carried between the desktop and the pet's tank. Never reachable from a
    /// socket event -- see EventRouter.reaction(for:), which has no case
    /// producing it; AppDelegate+Tank drives it directly.
    case travel
}

/// The result of routing one BridgeEvent: an optional state transition, an
/// optional extra SFX key (beyond whatever the target state's own name would
/// trigger), optional jump/speech-bubble flourishes, and an optional emotion
/// key (Settings' emotion mapping, 2026-07-29 -- AvatarPlayable.showEmotion).
struct EventReaction: Equatable {
    var stateTransition: StateKind?
    var sfxKey: String?
    var jump: Bool = false
    var bubbleText: String?
    var emotion: String?
    /// The bubble stays up until the run ends, instead of the few seconds a
    /// notice gets. What a code tour's caption wants: it describes pointing
    /// that is held just as long, and a caption that expires first leaves the
    /// pet standing over code with nothing said about it.
    var bubbleHoldsForRun: Bool = false
    /// The run this event belongs to has ended, whether it succeeded or not.
    /// The pet holds things on a run's behalf -- a point_at with a long
    /// `hold_seconds`, the tour's raised walking speed -- and this is when it
    /// lets go of them.
    var runFinished: Bool = false
}

enum EventRouter {
    /// Maps a protocol 3.2 event to a reaction, per the table in
    /// 02_pet-app.md section 3 F3 ("소켓 이벤트 -> 반응 매핑").
    ///
    /// - Parameter previousCodeEditorPath: the `detail.path` from the most
    ///   recent code_editor tool_call, if any -- kept here as an explicit
    ///   parameter rather than mutable state on this type (a pure decision
    ///   function, per the file header) so the caller (BridgeMessageRouter)
    ///   owns tracking it across calls. Used to detect a path *change*
    ///   ("detail.path 변경 시 짧은 점프") -- the very first code_editor
    ///   event of a session has nothing to compare against, so it never
    ///   jumps on its own.
    static func reaction(for event: BridgeEvent, previousCodeEditorPath: String? = nil) -> EventReaction {
        switch event {
        case .agentThinking:
            return EventReaction(stateTransition: .idle, emotion: "thinking")

        case .textChunk:
            // Chat-rendering data for F13 (2026-07-29), not a pet reaction --
            // no-op here, same as toolResult(ok: true) below.
            return EventReaction()

        case .toolCall(_, let tool, _, let detail):
            // code_editor gets a dedicated typing reaction; every other tool
            // (run_shell, run_applescript, and anything else) points at wherever
            // the action is happening — the "run_shell 계열" row in the table.
            guard tool == "code_editor" else {
                return EventReaction(stateTransition: .point)
            }
            let path = codeEditorPath(from: detail)
            let pathChanged = previousCodeEditorPath != nil && path != nil && path != previousCodeEditorPath
            return EventReaction(stateTransition: .type, jump: pathChanged)

        case .toolResult(_, let ok, _, _, _):
            return ok
                ? EventReaction()
                : EventReaction(stateTransition: .reactClick, sfxKey: "task_fail", emotion: "sad")

        case .awaitApproval:
            return EventReaction(stateTransition: .point, sfxKey: "await_approval", emotion: "thinking")

        case .agentDone(let ok, _):
            // Only agent_done(ok=true) is specified; a failed run is already
            // signaled via toolResult(ok=false).
            //
            // No bubble. The answer is in the transcript, in full, and the pet
            // now stands inside the island at the top of that same window --
            // so a bubble over its head repeated a line of the reply on top of
            // the reply. The sound, the jump and the face still mark the
            // moment. A code tour's caption (petSays) is a different thing and
            // keeps its bubble: it is said while pointing at code, and there
            // is nothing else on screen saying it.
            return ok
                ? EventReaction(sfxKey: "task_success", jump: true, emotion: "happy", runFinished: true)
                : EventReaction(runFinished: true)

        case .petSays(let text):
            // Speech and nothing else. A code tour's stop has already put the
            // pet where it wants it (point_at), so a state transition here
            // would undo the pointing the caption is describing.
            //
            // Through the same shortener agent_done's summary goes through:
            // the bubble is one line beside a 100px character either way, and
            // a caption is only as short as the model felt like being.
            return EventReaction(bubbleText: bubbleSummary(from: text), bubbleHoldsForRun: true)
        }
    }

    /// The speech bubble gets the headline, not the whole answer.
    ///
    /// agent_done's summary is whatever the agent that produced it
    /// felt like putting there -- for the F15 local agent it is literally the
    /// full reply text, and an ACP/editor run can hand back several
    /// paragraphs. The full text is already in the chat transcript
    /// (text_chunk); the bubble floating next to a 100px character is the one
    /// surface that cannot carry it.
    ///
    /// Trimmed here rather than at each agent: this is the only place a
    /// bubble is built, so every producer -- local, workspace, whatever comes
    /// next -- is covered by the one rule.
    static func bubbleSummary(from summary: String, limit: Int = 60) -> String? {
        guard let firstLine = firstSpokenLine(in: summary) else { return nil }

        // First sentence, keeping its terminator -- "고쳤어요." reads finished,
        // "고쳤어요" reads cut off. A terminator only ends a sentence when what
        // follows is whitespace or nothing: otherwise "hello.ts에 주석을
        // 추가했어요." becomes "hello." (which the test caught), and the same
        // goes for version numbers and 0.5.
        let sentence = firstLine.indices
            .first { index in
                guard ".!?。".contains(firstLine[index]) else { return false }
                let next = firstLine.index(after: index)
                return next == firstLine.endIndex || firstLine[next].isWhitespace
            }
            .map { String(firstLine[...$0]) } ?? firstLine

        guard sentence.count > limit else { return sentence }
        return sentence.prefix(limit).trimmingCharacters(in: .whitespaces) + "…"
    }


    /// The first line of the answer that is worth saying out loud, with its
    /// markdown taken off.
    ///
    /// Replies are markdown now, and the bubble used to take line one
    /// whatever it was -- so an answer opening with `## 확인` put the literal
    /// characters `## 확인` next to the pet: syntax the bubble cannot render,
    /// wrapped around a heading that is a label rather than a statement.
    ///
    /// Prose wins over a heading for that reason. A heading is only used when
    /// the answer is nothing but headings, where saying its words is still
    /// better than saying nothing.
    private static func firstSpokenLine(in summary: String) -> String? {
        var headingFallback: String?
        var insideCodeFence = false

        for rawLine in summary.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                insideCodeFence.toggle()
                continue
            }
            // Code says nothing a bubble can use, and it is where stray
            // punctuation would break the sentence split below.
            if insideCodeFence { continue }
            if line.isEmpty { continue }
            // A rule, or a table's divider row: separators, not sentences.
            if line.allSatisfy({ "-=_*|: ".contains($0) }) { continue }

            if line.hasPrefix("#") {
                let heading = strippedOfInlineMarkdown(
                    String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                )
                if headingFallback == nil, !heading.isEmpty { headingFallback = heading }
                continue
            }

            let spoken = strippedOfInlineMarkdown(strippedOfLeadingMarker(line))
            if !spoken.isEmpty { return spoken }
        }
        return headingFallback
    }

    /// A bullet, a numbered item or a quote marker. The text after it is
    /// content; the marker is punctuation the bubble should not read out.
    private static func strippedOfLeadingMarker(_ line: String) -> String {
        var rest = Substring(line)
        while let first = rest.first, "->+*".contains(first) || first == ">" {
            let afterMarker = rest.dropFirst()
            // `*emphasis*` is not a bullet -- a marker is followed by a space.
            guard afterMarker.first == " " else { break }
            rest = afterMarker.drop { $0 == " " }
        }
        // `1.` / `1)` at the start, and only there.
        let digits = rest.prefix { $0.isNumber }
        if !digits.isEmpty {
            let afterDigits = rest.dropFirst(digits.count)
            if let punctuation = afterDigits.first, punctuation == "." || punctuation == ")",
               afterDigits.dropFirst().first == " " {
                rest = afterDigits.dropFirst().drop { $0 == " " }
            }
        }
        return String(rest)
    }

    /// Emphasis, inline code and link syntax removed, keeping the words.
    /// Deliberately a character sweep rather than a parser: this feeds a
    /// 60-character bubble, and MarkdownText already owns real rendering.
    private static func strippedOfInlineMarkdown(_ line: String) -> String {
        var result = ""
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            switch character {
            case "*", "_", "`", "~":
                index = line.index(after: index)
            case "[":
                // `[text](url)` keeps text; a bare `[` keeps itself.
                if let close = line[index...].firstIndex(of: "]"),
                   line.index(after: close) < line.endIndex,
                   line[line.index(after: close)] == "(",
                   let end = line[close...].firstIndex(of: ")") {
                    result += line[line.index(after: index)..<close]
                    index = line.index(after: end)
                } else {
                    result.append(character)
                    index = line.index(after: index)
                }
            case "\\":
                // An escape: the next character is literal.
                let next = line.index(after: index)
                if next < line.endIndex {
                    result.append(line[next])
                    index = line.index(after: next)
                } else {
                    index = next
                }
            default:
                result.append(character)
                index = line.index(after: index)
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Extracts `detail.path` from a code_editor tool_call (protocol 3.2:
    /// `{"event":"tool_call","tool":"code_editor","detail":{"path":"src/main.ts"}}`).
    /// Exposed so BridgeMessageRouter can track it across calls without
    /// duplicating the JSONValue destructuring.
    static func codeEditorPath(from detail: JSONValue?) -> String? {
        guard case .object(let fields)? = detail, case .string(let path)? = fields["path"] else { return nil }
        return path
    }
}
