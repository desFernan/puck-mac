//
//  EventRouterTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Verifies the event -> reaction mapping table in
//  plan/02_pet-app.md section 3 F3 ("소켓 이벤트 -> 반응 매핑").
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

    // MARK: - code_editor detail.path change -> jump (02_pet-app.md F3:
    // "detail.path 변경 시 짧은 점프") -- decoded via EventReaction.jump but
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

    func test_toolCall_runShell_neverJumpsRegardlessOfPreviousPath() {
        let reaction = EventRouter.reaction(
            for: .toolCall(id: "t1", tool: "run_shell", args: nil, detail: nil),
            previousCodeEditorPath: "src/main.ts"
        )
        XCTAssertEqual(reaction, EventReaction(stateTransition: .point, jump: false))
    }

    func test_toolCall_runShell_transitionsToPoint() {
        let reaction = EventRouter.reaction(for: .toolCall(id: "t1", tool: "run_shell", args: nil, detail: nil))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .point))
    }

    func test_toolCall_runAppleScript_transitionsToPoint() {
        let reaction = EventRouter.reaction(for: .toolCall(id: "t1", tool: "run_applescript", args: nil, detail: nil))
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

    func test_awaitApproval_transitionsToPointWithWaitingSFX() {
        let reaction = EventRouter.reaction(for: .awaitApproval(summary: "rm -rf ./dist", approvalId: "a1"))
        XCTAssertEqual(reaction, EventReaction(stateTransition: .point, sfxKey: "await_approval", emotion: "thinking"))
    }

    /// The sound, the jump and the face mark the answer; the words do not.
    /// The reply is already in the transcript, and the pet stands inside the
    /// island at the top of that same window -- a bubble over its head
    /// repeated one line of the answer on top of the answer.
    func test_agentDone_success_marksTheMomentWithoutABubble() {
        let reaction = EventRouter.reaction(for: .agentDone(ok: true, summary: "3 tests passed"))
        XCTAssertEqual(
            reaction,
            EventReaction(sfxKey: "task_success", jump: true, emotion: "happy", runFinished: true)
        )
        XCTAssertNil(reaction.bubbleText)
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

    func test_agentDone_failure_isSilentButStillEndsTheRun() {
        // Not specified in the reaction table — only agent_done(ok=true) is; toolResult(ok=false)
        // already covers the failure-signaling case. runFinished is not a
        // reaction the user sees: it is what makes the pet let go of a long
        // point_at hold, and a failed run has to let go too.
        let reaction = EventRouter.reaction(for: .agentDone(ok: false, summary: "failed"))
        XCTAssertEqual(reaction, EventReaction(runFinished: true))
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
}
