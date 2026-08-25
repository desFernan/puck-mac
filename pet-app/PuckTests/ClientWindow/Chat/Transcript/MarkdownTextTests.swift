//
//  MarkdownTextTests.swift
//  Puck
//
//  The block parser and the inline fallback, which are pure. The layout they
//  feed (column measure, padding, which side gets a balloon) is not unit
//  tested: it has no return value to assert on, and a snapshot of it would
//  fail on every deliberate spacing change without ever catching a real bug.
//

import XCTest
@testable import Puck

final class MarkdownTextTests: XCTestCase {
    // MARK: - Blocks

    func test_headings_carryTheirLevelAndLoseTheirHashes() {
        XCTAssertEqual(parseMarkdownBlocks("# Title"), [.heading(level: 1, text: "Title")])
        XCTAssertEqual(parseMarkdownBlocks("### Deeper"), [.heading(level: 3, text: "Deeper")])
        XCTAssertEqual(parseMarkdownBlocks("## Closed ##"), [.heading(level: 2, text: "Closed")])
        // Seven is not a heading in CommonMark, and a hash with no space is a
        // hashtag -- both stay prose rather than becoming a giant line.
        XCTAssertEqual(parseMarkdownBlocks("####### Seven"), [.paragraph("####### Seven")])
        XCTAssertEqual(parseMarkdownBlocks("#tag"), [.paragraph("#tag")])
    }

    func test_aHeadingSeparatesTheParagraphsAroundIt() {
        XCTAssertEqual(
            parseMarkdownBlocks("intro\n# Title\nbody"),
            [.paragraph("intro"), .heading(level: 1, text: "Title"), .paragraph("body")]
        )
    }

    func test_bulletList() {
        XCTAssertEqual(
            parseMarkdownBlocks("- one\n* two\n+ three"),
            [.list([
                MarkdownListItem(level: 0, ordinal: nil, text: "one"),
                MarkdownListItem(level: 0, ordinal: nil, text: "two"),
                MarkdownListItem(level: 0, ordinal: nil, text: "three")
            ])]
        )
    }

    func test_orderedList_keepsTheAuthorsOwnNumbers() {
        XCTAssertEqual(
            parseMarkdownBlocks("1. one\n2. two\n7) seven"),
            [.list([
                MarkdownListItem(level: 0, ordinal: 1, text: "one"),
                MarkdownListItem(level: 0, ordinal: 2, text: "two"),
                MarkdownListItem(level: 0, ordinal: 7, text: "seven")
            ])]
        )
    }

    /// `*bold* text` is a paragraph: a marker needs a space after it.
    func test_emphasisAtTheStartOfALine_isNotAList() {
        XCTAssertEqual(parseMarkdownBlocks("*bold* text"), [.paragraph("*bold* text")])
    }

    func test_listItemsKeepTheirInlineMarkdownForTheInlineParser() {
        XCTAssertEqual(
            parseMarkdownBlocks("- a **b** and `c`"),
            [.list([MarkdownListItem(level: 0, ordinal: nil, text: "a **b** and `c`")])]
        )
        XCTAssertEqual(
            String(markdownInline("a **b** and `c`").characters),
            "a b and c"
        )
    }

    func test_nestingIsClampedRatherThanIndentingOffTheWindow() {
        let blocks = parseMarkdownBlocks("- top\n" + String(repeating: " ", count: 200) + "- deep")
        guard case .list(let items) = blocks.first, items.count == 2 else {
            return XCTFail("expected one list of two items, got \(blocks)")
        }
        XCTAssertEqual(items[0].level, 0)
        XCTAssertEqual(items[1].level, 5)
    }

    func test_fencedCode_keepsItsWhitespaceAndIsNotMarkdownParsed() {
        XCTAssertEqual(
            parseMarkdownBlocks("```swift\nlet x = 1\n    if **y** {}\n```"),
            [.codeBlock(language: "swift", code: "let x = 1\n    if **y** {}")]
        )
    }

    func test_fencedCode_dropsOnlyTheFencesOwnIndentation() {
        XCTAssertEqual(
            parseMarkdownBlocks("  ```\n  a\n      b\n  ```"),
            [.codeBlock(language: nil, code: "a\n    b")]
        )
    }

    /// A model that stops mid-answer leaves the fence open. Everything after
    /// it still has to appear -- as code, to EOF -- rather than vanish.
    func test_anUnterminatedFence_stillRendersEverythingAfterIt() {
        XCTAssertEqual(
            parseMarkdownBlocks("intro\n```\nstill here\nand here"),
            [.paragraph("intro"), .codeBlock(language: nil, code: "still here\nand here")]
        )
    }

    func test_blockquotesAndRules() {
        XCTAssertEqual(parseMarkdownBlocks("> quoted\n> more"), [.quote("quoted\nmore")])
        XCTAssertEqual(parseMarkdownBlocks("a\n\n---\n\nb"), [.paragraph("a"), .rule, .paragraph("b")])
    }

    func test_emptyAndBlankInput_produceNoBlocks() {
        XCTAssertEqual(parseMarkdownBlocks(""), [])
        XCTAssertEqual(parseMarkdownBlocks("\n\n   \n"), [])
    }

    func test_aPlainAnswer_isOneParagraphPerBlankLineSeparatedRun() {
        XCTAssertEqual(
            parseMarkdownBlocks("첫 문단입니다.\n같은 문단.\n\n다음 문단."),
            [.paragraph("첫 문단입니다.\n같은 문단."), .paragraph("다음 문단.")]
        )
    }

    // MARK: - Inline

    func test_aLink_keepsItsLabelAndItsDestination() {
        let rendered = markdownInline("see [docs](https://example.com) now")
        XCTAssertEqual(String(rendered.characters), "see docs now")
        XCTAssertTrue(rendered.runs.contains { $0.link?.absoluteString == "https://example.com" })
    }

    /// A transcript is not a place to hand a model's chosen URL scheme to
    /// `openURL`. The label survives; the click does not.
    func test_aLinkWithAnUnexpectedScheme_keepsItsTextButNotItsLink() {
        let rendered = markdownInline("[click](javascript:alert(1))")
        XCTAssertEqual(String(rendered.characters), "click")
        XCTAssertTrue(rendered.runs.allSatisfy { $0.link == nil })
    }

    func test_textThatIsNotMarkdown_survivesCharacterForCharacter() {
        let samples = [
            "TODO: fix the * in file_name.txt",
            "2 * 3 * 4 = 24",
            "snake_case_and_more_snake_case",
            "쉼표, 별표 *, 밑줄 _ 가 섞인 평범한 문장입니다."
        ]
        for sample in samples {
            XCTAssertEqual(String(markdownInline(sample).characters), sample, sample)
        }
    }

    /// Malformed markdown falls back to the literal text rather than dropping
    /// anything: styling is worth less than the characters themselves.
    func test_malformedMarkdown_losesNoCharacters() {
        let samples = [
            "**unclosed bold",
            "[unclosed link](http://example.com",
            "`unclosed code",
            "~~~",
            "***"
        ]
        for sample in samples {
            let rendered = String(markdownInline(sample).characters)
            XCTAssertEqual(
                rendered.filter { $0.isLetter || $0.isNumber },
                sample.filter { $0.isLetter || $0.isNumber },
                sample
            )
        }
    }

    /// Angle brackets used to be parsed as raw HTML and dropped whole, which
    /// is how a generic type written in prose disappeared.
    func test_angleBrackets_areNotTreatedAsHTML() {
        XCTAssertEqual(
            String(markdownInline("Array<Element> 를 <b>쓰세요</b>").characters),
            "Array<Element> 를 <b>쓰세요</b>"
        )
    }

    func test_inlineParsing_handlesAVeryLongSingleLine() {
        let long = String(repeating: "말 ", count: 20_000)
        XCTAssertFalse(String(markdownInline(long).characters).isEmpty)
    }
}
