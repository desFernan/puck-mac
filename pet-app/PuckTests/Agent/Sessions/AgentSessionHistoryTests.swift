//
//  AgentSessionHistoryTests.swift
//  Puck
//

import XCTest
@testable import Puck

final class AgentSessionHistoryTests: XCTestCase {
    private var directories: [URL] = []

    override func tearDown() {
        for url in directories { try? FileManager.default.removeItem(at: url) }
        directories = []
        super.tearDown()
    }

    private func makeTranscript(_ lines: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("puck-sessions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        directories.append(root)
        let file = root.appendingPathComponent("11111111-2222-3333-4444-555555555555.jsonl")
        try lines.joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func test_readsTheDirectoryTheTitleAndTheModel() throws {
        let file = try makeTranscript([
            #"{"type":"queue-operation","sessionId":"s"}"#,
            #"{"type":"user","cwd":"/Users/me/app","message":{"content":"Add a reset() method"}}"#,
            #"{"type":"assistant","message":{"model":"claude-opus-5","content":[{"type":"text","text":"Done."}]}}"#,
        ])
        let session = try XCTUnwrap(AgentSessionHistory.summarise(transcript: file, modifiedAt: .distantPast))

        XCTAssertEqual(session.workingDirectory, "/Users/me/app")
        XCTAssertEqual(session.title, "Add a reset() method")
        XCTAssertEqual(session.model, "claude-opus-5")
        XCTAssertEqual(session.id, "11111111-2222-3333-4444-555555555555")
    }

    /// The enclosing folder is the path with every `/` and `.` turned into
    /// `-`, which cannot be turned back -- so the label comes from the `cwd`
    /// the transcript carries.
    func test_labelsAProjectByItsLastTwoComponents() throws {
        let file = try makeTranscript([
            #"{"type":"user","cwd":"/Users/me/Developer/Speaki-e/puck","message":{"content":"hi"}}"#,
        ])
        let session = try XCTUnwrap(AgentSessionHistory.summarise(transcript: file, modifiedAt: .distantPast))
        XCTAssertEqual(session.projectLabel, "Speaki-e/puck")
    }

    /// Content is a string or the API's block array, and only text blocks say
    /// anything about what was asked.
    func test_takesTheTitleFromTextBlocksOnly() {
        XCTAssertEqual(AgentSessionHistory.firstLine(of: "plain"), "plain")
        XCTAssertEqual(
            AgentSessionHistory.firstLine(of: [
                ["type": "tool_result", "content": "ignored"],
                ["type": "text", "text": "the question"],
            ]),
            "the question"
        )
        XCTAssertEqual(AgentSessionHistory.firstLine(of: [["type": "image"]]), "")
        XCTAssertEqual(AgentSessionHistory.firstLine(of: nil), "")
    }

    /// One line, and never a blank one: a title is a row in a list.
    func test_theTitleIsTheFirstNonEmptyLine() {
        XCTAssertEqual(AgentSessionHistory.firstLine(of: "\n\n  first\nsecond"), "first")
    }

    /// A turn can arrive wrapped in something the CLI added --
    /// `<local-command-caveat>`, `<command-name>` -- which nobody typed and
    /// which reads the same on every session.
    func test_skipsAWrapperAndTitlesTheSessionByWhatWasAsked() throws {
        let file = try makeTranscript([
            #"{"type":"user","cwd":"/a/b","message":{"content":"<local-command-caveat>Caveat: ...</local-command-caveat>"}}"#,
            #"{"type":"user","message":{"content":"what I actually asked"}}"#,
        ])
        let session = try XCTUnwrap(AgentSessionHistory.summarise(transcript: file, modifiedAt: .distantPast))
        XCTAssertEqual(session.title, "what I actually asked")
    }

    func test_nilForATranscriptWithNothingToShow() throws {
        XCTAssertNil(AgentSessionHistory.summarise(transcript: try makeTranscript([]), modifiedAt: .distantPast))
        XCTAssertNil(AgentSessionHistory.summarise(transcript: try makeTranscript(["not json"]), modifiedAt: .distantPast))
    }

    /// A malformed line in the middle must not lose the ones around it: these
    /// files are appended to live, so the last line can be half-written.
    func test_skipsLinesItCannotParse() throws {
        let file = try makeTranscript([
            "{ broken",
            #"{"type":"user","cwd":"/a/b","message":{"content":"still read"}}"#,
        ])
        let session = try XCTUnwrap(AgentSessionHistory.summarise(transcript: file, modifiedAt: .distantPast))
        XCTAssertEqual(session.title, "still read")
    }

    /// Only the head is read, so a transcript far larger than that still
    /// summarises -- and costs the same as a small one.
    func test_readsOnlyTheHeadOfALargeTranscript() throws {
        let filler = String(repeating: #"{"type":"assistant","message":{"content":[]}}"#, count: 1).appending("")
        var lines = [#"{"type":"user","cwd":"/big/project","message":{"content":"the first ask"}}"#]
        lines.append(contentsOf: Array(repeating: filler, count: 20_000))
        let file = try makeTranscript(lines)
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, AgentSessionHistory.headBytes, "the fixture has to exceed the head to test it")

        let session = try XCTUnwrap(AgentSessionHistory.summarise(transcript: file, modifiedAt: .distantPast))
        XCTAssertEqual(session.title, "the first ask")
        XCTAssertEqual(session.workingDirectory, "/big/project")
    }

    /// The head is cut at a byte count, which can land in the middle of a
    /// character. A transcript whose 256KB mark falls inside an emoji used to
    /// decode as nothing and vanish from the list entirely.
    func test_summarisesEvenWhenTheHeadIsCutInsideACharacter() throws {
        var lines = [#"{"type":"user","cwd":"/emoji/project","message":{"content":"the first ask"}}"#]
        // Padded with a line of emoji long enough to reach past the head, so
        // wherever the cut lands it lands inside one of them.
        let padding = String(repeating: "🐙", count: 4_000)
        lines.append(contentsOf: Array(repeating: #"{"type":"assistant","message":{"content":"\#(padding)"}}"#, count: 40))
        let file = try makeTranscript(lines)
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, AgentSessionHistory.headBytes)

        let session = try XCTUnwrap(AgentSessionHistory.summarise(transcript: file, modifiedAt: .distantPast))

        XCTAssertEqual(session.title, "the first ask")
        XCTAssertEqual(session.workingDirectory, "/emoji/project")
    }
}
