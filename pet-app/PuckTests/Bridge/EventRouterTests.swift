//
//  EventRouterTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Verifies the event -> reaction mapping table (F3, "소켓 이벤트 -> 반응
//  매핑").
//

import XCTest
@testable import Puck

final class EventRouterTests: XCTestCase {
    func test_agentThinking_transitionsToIdle() {
        let reaction = EventRouter.reaction(for: .agentThinking)
        XCTAssertEqual(reaction, EventReaction(stateTransition: .idle, emotion: "thinking"))
    }

    func test_toolCall_codeEditor_transitionsToType() {
        let reaction = EventRouter.reaction(for: .toolCall(id: "t1", tool: "code_editor", args: nil, detail: nil))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .type))
    }

    // MARK: - code_editor detail.path change -> jump (F3: "detail.path
    // 변경 시 짧은 점프") -- decoded via EventReaction.jump but
    // never actually checked for a change until now (found via spec
    // cross-check).

    func test_toolCall_codeEditor_firstEventEver_doesNotJump() {
        // Nothing to compare the very first path against -- entering Type
        // isn't itself a "change".
        let reaction = EventRouter.reaction(
            for: .toolCall(id: "t1", tool: "code_editor", args: nil, detail: .object(["path": .string("src/main.ts")])),
            previousCodeEditorPath: nil
        )
        XCTAssertEqual(reaction, EventReaction(stateTransition: .type, jump: false))
    }

    func test_toolCall_codeEditor_samePathAsBefore_doesNotJump() {
        let reaction = EventRouter.reaction(
            for: .toolCall(id: "t1", tool: "code_editor", args: nil, detail: .object(["path": .string("src/main.ts")])),
            previousCodeEditorPath: "src/main.ts"
        )
        XCTAssertEqual(reaction, EventReaction(stateTransition: .type, jump: false))
    }

    func test_toolCall_codeEditor_differentPathThanBefore_jumps() {
        let reaction = EventRouter.reaction(
            for: .toolCall(id: "t1", tool: "code_editor", args: nil, detail: .object(["path": .string("src/other.ts")])),
            previousCodeEditorPath: "src/main.ts"
        )
        XCTAssertEqual(reaction, EventReaction(stateTransition: .type, jump: true))
    }

    /// The jump belongs to code_editor moving to another file, and nothing
    /// else may borrow it -- a previous path left over from an earlier call
    /// must not make an unrelated tool hop.
    func test_toolCall_runShell_neverJumpsRegardlessOfPreviousPath() {
        let reaction = EventRouter.reaction(
            for: .toolCall(id: "t1", tool: "run_shell", args: nil, detail: nil),
            previousCodeEditorPath: "src/main.ts"
        )
        XCTAssertFalse(reaction.jump)
    }

    /// A shell command is the pet working, not the pet showing.
    ///
    /// It used to `point`, which was right while every tool but code_editor
    /// acted on something on screen. It stopped being right as the agent grew
    /// tools that are it working on its own -- there is nothing to point at
    /// during a `run_shell`, and the pet stood with its arm out at nothing.
    /// See EventRouter.posture(forTool:).
    func test_toolCall_runShell_makesThePetWork() {
        let reaction = EventRouter.reaction(for: .toolCall(id: "t1", tool: "run_shell", args: nil, detail: nil))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .type))
    }

    func test_toolCall_runAppleScript_makesThePetWork() {
        let reaction = EventRouter.reaction(for: .toolCall(id: "t1", tool: "run_applescript", args: nil, detail: nil))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .type))
    }

    /// And a tool that *is* about a place on screen still points.
    func test_toolCall_clickElement_stillPoints() {
        let reaction = EventRouter.reaction(for: .toolCall(id: "t1", tool: "click_element", args: nil, detail: nil))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .point))
    }

    func test_toolResult_failure_reactsWithTaskFailSFX() {
        let reaction = EventRouter.reaction(for: .toolResult(id: "t1", ok: false, data: nil, error: nil, detail: nil))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .reactClick, sfxKey: "task_fail", emotion: "sad"))
    }

    func test_toolResult_success_isNoOp() {
        let reaction = EventRouter.reaction(for: .toolResult(id: "t1", ok: true, data: nil, error: nil, detail: nil))
        XCTAssertEqual(reaction, EventReaction())
    }

    /// The waiting sound and face, and -- since 2026-09-04 -- the pet coming
    /// to the pointer with the question.
    ///
    /// It used to `point`, which was pointing at nothing in particular: the
    /// banner it meant to indicate is inside a window that, whenever this
    /// matters, is behind something else. Until an approval is answered the
    /// agent does nothing at all, so this is the one thing worth interrupting
    /// for.
    func test_awaitApproval_bringsThePetOverWithTheWaitingSFX() {
        let reaction = EventRouter.reaction(for: .awaitApproval(summary: "rm -rf ./dist", approvalId: "a1"))

        XCTAssertEqual(reaction.sfxKey, "await_approval")
        XCTAssertEqual(reaction.emotion, "thinking")
        XCTAssertTrue(reaction.comesToCursor)
        XCTAssertEqual(reaction.bubbleText, "rm -rf ./dist")
        XCTAssertTrue(reaction.bubbleWhenAwayOnly)
    }

    /// The sound, the jump and the face mark the answer, and the words only
    /// when nobody can read them anywhere else.
    ///
    /// The original rule was "no bubble at all", for a good reason: the reply
    /// is already in the transcript, the pet stands inside the island at the
    /// top of that same window, and a bubble over its head repeated one line
    /// of the answer on top of the answer. That reason holds exactly while
    /// the window is the one being looked at -- which is what
    /// `bubbleWhenAwayOnly` now says. With the window behind something else
    /// there is no transcript on screen, and "it finished" is worth knowing.
    func test_agentDone_success_marksTheMomentAndSpeaksOnlyWhenAway() {
        let reaction = EventRouter.reaction(for: .agentDone(ok: true, summary: "3 tests passed"))

        XCTAssertEqual(reaction.sfxKey, "task_success")
        XCTAssertTrue(reaction.jump)
        XCTAssertEqual(reaction.emotion, "happy")
        XCTAssertTrue(reaction.runFinished)
        XCTAssertEqual(reaction.bubbleText, "3 tests passed")
        XCTAssertTrue(reaction.bubbleWhenAwayOnly)
        XCTAssertFalse(reaction.comesToCursor, "a finished run can wait to be looked at")
    }

    /// A code tour's caption still speaks, and still keeps only the headline:
    /// it is said while pointing at code, with nothing else on screen saying
    /// it, and the bubble is one line beside a 100px character.
    func test_petSays_keepsOnlyTheHeadline() {
        let wall = """
        hello.ts에 주석을 추가했어요. 파일 맨 위에 한 줄 주석을 넣었고, \
        나머지 코드는 손대지 않았습니다.
        추가로 확인이 필요하면 말씀해 주세요.
        """
        let reaction = EventRouter.reaction(for: .petSays(text: wall))

        XCTAssertEqual(reaction.bubbleText, "hello.ts에 주석을 추가했어요.")
    }

    /// The pet speaks the answer, and the answer is markdown now. A bubble
    /// that reads out `## 확인` shows syntax it cannot render, wrapped around
    /// a heading that states nothing.
    func test_bubbleSummary_skipsAHeadingAndSpeaksTheFirstRealLine() {
        let reply = """
        ## 확인
        - 워크스페이스에 프로젝트 폴더가 연결돼 있지 않습니다.
        - 빌드를 돌리려면 프로젝트가 필요합니다.
        """

        XCTAssertEqual(EventRouter.bubbleSummary(from: reply), "워크스페이스에 프로젝트 폴더가 연결돼 있지 않습니다.")
    }

    /// ...but a heading is better than silence when it is all there is.
    func test_bubbleSummary_fallsBackToAHeadingWhenNothingElseSpeaks() {
        XCTAssertEqual(EventRouter.bubbleSummary(from: "# 빌드 실패\n\n---"), "빌드 실패")
    }

    func test_bubbleSummary_dropsInlineMarkdownButKeepsTheWords() {
        XCTAssertEqual(EventRouter.bubbleSummary(from: "**다 고쳤어요**"), "다 고쳤어요")
        XCTAssertEqual(EventRouter.bubbleSummary(from: "`swift build`로 확인했어요."), "swift build로 확인했어요.")
        XCTAssertEqual(EventRouter.bubbleSummary(from: "[문서](https://example.com)를 봤어요."), "문서를 봤어요.")
    }

    /// A fenced block is not something to read out, and its punctuation would
    /// cut the sentence in the wrong place.
    func test_bubbleSummary_ignoresCodeBlocks() {
        let reply = """
        ```swift
        let x = 1
        ```
        고쳤어요.
        """

        XCTAssertEqual(EventRouter.bubbleSummary(from: reply), "고쳤어요.")
    }

    /// Emphasis is not a bullet: a marker is followed by a space.
    func test_bubbleSummary_doesNotMistakeEmphasisForAListMarker() {
        XCTAssertEqual(EventRouter.bubbleSummary(from: "*강조*만 있는 줄"), "강조만 있는 줄")
        XCTAssertEqual(EventRouter.bubbleSummary(from: "1. 첫 번째"), "첫 번째")
        XCTAssertEqual(EventRouter.bubbleSummary(from: "> 인용된 말"), "인용된 말")
    }

    func test_bubbleSummary_edges() {
        // No sentence terminator: capped with an ellipsis rather than cut mid-air.
        let long = String(repeating: "가", count: 80)
        XCTAssertEqual(EventRouter.bubbleSummary(from: long), String(repeating: "가", count: 60) + "…")
        // Nothing to say means no bubble at all, not an empty one.
        XCTAssertNil(EventRouter.bubbleSummary(from: "   \n  "))
        // Already short: untouched, terminator kept.
        XCTAssertEqual(EventRouter.bubbleSummary(from: "Safari 켰어요!"), "Safari 켰어요!")
    }

    /// A failed run says what happened, and wears it.
    ///
    /// It used to say nothing beyond ending the run, on the grounds that
    /// toolResult(ok=false) already signalled the failure -- true while the
    /// window is in front, and no help at all when it is not: a tool result
    /// is a row in a transcript nobody is looking at. `runFinished` is still
    /// the part the user does not see, and still what makes the pet let go of
    /// a long point_at hold.
    func test_agentDone_failure_saysSoAndStillEndsTheRun() {
        let reaction = EventRouter.reaction(for: .agentDone(ok: false, summary: "failed"))

        XCTAssertTrue(reaction.runFinished)
        XCTAssertEqual(reaction.bubbleText, "failed")
        XCTAssertEqual(reaction.emotion, "sad")
        XCTAssertTrue(reaction.bubbleWhenAwayOnly)
        XCTAssertNil(reaction.sfxKey, "a failure is not celebrated")
    }

    /// text_chunk is chat-only; a tour stop needs the pet itself to say a
    /// line while it points.
    func test_petSays_becomesABubble() {
        let reaction = EventRouter.reaction(for: .petSays(text: "여기가 진입점이에요"))

        XCTAssertEqual(reaction.bubbleText, "여기가 진입점이에요")
    }

    /// The caption is held as long as the pointing it describes, rather than
    /// expiring like a notice while the pet still stands over the code.
    func test_petSays_holdsUntilTheRunEnds() {
        XCTAssertTrue(EventRouter.reaction(for: .petSays(text: "여기예요")).bubbleHoldsForRun)
        XCTAssertFalse(
            EventRouter.reaction(for: .agentDone(ok: true, summary: "끝")).bubbleHoldsForRun,
            "a summary is read once and gone; nothing is holding it open"
        )
    }

    /// Speech and nothing else: the stop's point_at has already put the pet
    /// where it wants it, and a transition here would undo the pointing.
    func test_petSays_doesNotMoveThePet() {
        let reaction = EventRouter.reaction(for: .petSays(text: "여기예요"))

        XCTAssertNil(reaction.stateTransition)
        XCTAssertFalse(reaction.jump)
        XCTAssertFalse(reaction.runFinished)
    }

    // MARK: - What the pet says when nobody is looking at the window

    /// A finished run now carries a line for the pet to say -- but marked as
    /// away-only, because with the window in front the transcript already
    /// holds the whole answer and a bubble repeats a piece of it on top.
    func test_aFinishedRunSpeaksOnlyWhileTheWindowIsAway() {
        let reaction = EventRouter.reaction(for: .agentDone(ok: true, summary: "세 파일 고쳤어요"))

        XCTAssertEqual(reaction.bubbleText, "세 파일 고쳤어요")
        XCTAssertTrue(reaction.bubbleWhenAwayOnly)
        XCTAssertFalse(reaction.comesToCursor, "news can wait to be looked at")
        XCTAssertTrue(reaction.runFinished)
    }

    /// A failed one says so too, and wears it. It used to say nothing at all
    /// beyond ending the run.
    func test_aFailedRunAlsoSaysWhatHappened() {
        let reaction = EventRouter.reaction(for: .agentDone(ok: false, summary: "빌드가 깨졌어요"))

        XCTAssertEqual(reaction.bubbleText, "빌드가 깨졌어요")
        XCTAssertEqual(reaction.emotion, "sad")
        XCTAssertTrue(reaction.bubbleWhenAwayOnly)
        XCTAssertTrue(reaction.runFinished)
    }

    /// The one thing that cannot wait: until an approval is answered the
    /// agent does nothing at all, and the banner is in a window that is
    /// behind something else.
    func test_anApprovalBringsThePetToThePointer() {
        let reaction = EventRouter.reaction(
            for: .awaitApproval(summary: "rm -rf 해도 될까요", approvalId: "a1")
        )

        XCTAssertTrue(reaction.comesToCursor)
        XCTAssertEqual(reaction.bubbleText, "rm -rf 해도 될까요")
        XCTAssertTrue(reaction.bubbleWhenAwayOnly, "with the window in front the banner is right there")
        XCTAssertEqual(reaction.emotion, "thinking")
    }

    /// And nothing else summons anyone. A tool call that points at a window
    /// is the pet doing its job, not asking for attention.
    func test_ordinaryProgressDoesNotComeToThePointer() {
        for event in [
            BridgeEvent.agentThinking,
            .toolCall(id: "1", tool: "run_shell", args: nil, detail: nil),
            .toolResult(id: "1", ok: true, data: nil, error: nil, detail: nil),
            .textChunk(text: "..."),
        ] {
            XCTAssertFalse(EventRouter.reaction(for: event).comesToCursor, "\(event)")
        }
    }

    // MARK: - What the pet does while a tool runs

    /// A tool whose purpose is a place on screen: the pet points at it.
    func test_aToolAboutSomewhereOnScreenMakesThePetPoint() {
        for tool in ["click_element", "find_ui_element", "app_snapshot", "scroll", "launch_app"] {
            XCTAssertEqual(EventRouter.posture(forTool: tool), .point, tool)
        }
    }

    /// A tool that is the agent working on its own: there is nothing to point
    /// at, and the pet stood with its arm out at nothing.
    func test_aToolThatIsJustWorkMakesThePetWork() {
        for tool in ["run_shell", "terminal_start", "terminal_read", "read_file", "list_files"] {
            XCTAssertEqual(EventRouter.posture(forTool: tool), .type, tool)
        }
    }

    /// A tool nobody listed points, which is what everything did before and
    /// is the safer of the two to be wrong about: a pet pointing is looking
    /// at something, a pet typing claims to be working.
    func test_anUnknownToolPoints() {
        XCTAssertEqual(EventRouter.posture(forTool: "something_new"), .point)
    }

    /// And the reaction actually uses it.
    func test_aShellCallDoesNotMakeThePetPointAtNothing() {
        let reaction = EventRouter.reaction(
            for: .toolCall(id: "1", tool: "run_shell", args: nil, detail: nil)
        )

        XCTAssertEqual(reaction.stateTransition, .type)
    }
}
