//
//  FileMentionTests.swift
//  PuckTests
//
//  `@` in the composer: when it is a file being named, and when it is just an
//  at sign.
//

import XCTest
@testable import Puck

final class FileMentionTests: XCTestCase {
    func test_whatFollowsTheLastAtSignIsWhatIsBeingTyped() {
        XCTAssertEqual(FileMention.activeQuery(in: "@Chat"), "Chat")
        XCTAssertEqual(FileMention.activeQuery(in: "이거 고쳐줘 @Puck/Agent/Ag"), "Puck/Agent/Ag")
    }

    /// `@` on its own is the start of one, and offering everything is the
    /// right answer to it.
    func test_anAtSignOnItsOwnIsAMentionWithNothingTypedYet() {
        XCTAssertEqual(FileMention.activeQuery(in: "@"), "")
    }

    /// Mid-word it is an address, not a mention.
    func test_anAtSignInsideAWordIsNotAMention() {
        XCTAssertNil(FileMention.activeQuery(in: "byeolki@example.com"))
    }

    /// A space ends it: what is being typed now is the next word.
    func test_aFinishedMentionIsNotStillBeingTyped() {
        XCTAssertNil(FileMention.activeQuery(in: "@Puck/Agent/AgentRunner.swift 고쳐줘"))
        XCTAssertNil(FileMention.activeQuery(in: "고쳐줘"))
    }

    func test_completingReplacesWhatWasTypedAndLeavesRoomForTheNextWord() {
        XCTAssertEqual(
            FileMention.completing("이거 봐줘 @Agent", with: "Puck/Agent/AgentRunner.swift"),
            "이거 봐줘 @Puck/Agent/AgentRunner.swift "
        )
    }

    func test_completingWithNothingToCompleteChangesNothing() {
        XCTAssertEqual(FileMention.completing("고쳐줘", with: "a.swift"), "고쳐줘")
    }

    // MARK: - Reading a finished message

    func test_everyMentionedPathIsFoundInOrderAndWithoutRepeats() {
        let paths = FileMention.mentionedPaths(in: "@a/b.swift 랑 @c.swift 를 @a/b.swift 처럼")

        XCTAssertEqual(paths, ["a/b.swift", "c.swift"])
    }

    /// Sentence punctuation is not part of the path.
    func test_trailingPunctuationIsNotPartOfThePath() {
        XCTAssertEqual(FileMention.mentionedPaths(in: "@a/b.swift, 그리고 @c.swift."), ["a/b.swift", "c.swift"])
    }

    func test_anAtSignWithNothingAfterItMentionsNothing() {
        XCTAssertTrue(FileMention.mentionedPaths(in: "@ 뭐였지").isEmpty)
    }
}
