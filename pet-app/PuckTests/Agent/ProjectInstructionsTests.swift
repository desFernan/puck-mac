//
//  ProjectInstructionsTests.swift
//  PuckTests
//
//  Reading the file a project keeps for whoever works on it.
//

import XCTest
@testable import Puck

final class ProjectInstructionsTests: XCTestCase {
    private var project: URL!

    override func setUpWithError() throws {
        project = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: project)
    }

    private func write(_ name: String, _ body: String) throws {
        let url = project.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    func test_theProjectsOwnInstructionsAreRead() throws {
        try write("AGENTS.md", "테스트는 scripts/test.sh 로 돌린다")

        XCTAssertEqual(ProjectInstructions.load(projectPath: project.path), "테스트는 scripts/test.sh 로 돌린다")
    }

    /// A project with both almost always has one that includes the other by
    /// reference, and reading both means being told everything twice -- where
    /// they disagree, twice and contradictorily.
    func test_onlyTheFirstOneFoundIsRead() throws {
        try write("AGENTS.md", "이걸 읽어라")
        try write("CLAUDE.md", "이건 읽지 마라")

        XCTAssertEqual(ProjectInstructions.load(projectPath: project.path), "이걸 읽어라")
    }

    func test_theOtherNamesAreLookedForInTurn() throws {
        try write("CLAUDE.md", "클로드용")

        XCTAssertEqual(ProjectInstructions.load(projectPath: project.path), "클로드용")
    }

    func test_pucksOwnFileIsTheLastResort() throws {
        try write(".puck/instructions.md", "퍽 전용")

        XCTAssertEqual(ProjectInstructions.load(projectPath: project.path), "퍽 전용")
    }

    func test_aProjectWithNoneOfThemHasNothingToSay() {
        XCTAssertNil(ProjectInstructions.load(projectPath: project.path))
    }

    /// A chat-only workspace has no project to read one from.
    func test_withoutAProjectThereIsNothingToRead() {
        XCTAssertNil(ProjectInstructions.load(projectPath: nil))
    }

    func test_anEmptyFileIsTreatedAsNoFileAtAll() throws {
        try write("AGENTS.md", "   \n\n  ")
        try write("CLAUDE.md", "진짜 내용")

        XCTAssertEqual(ProjectInstructions.load(projectPath: project.path), "진짜 내용")
    }

    /// An agent that has read two thirds of the rules and does not know it is
    /// worse than one that has read none.
    func test_aFileLongerThanPuckReadsSaysWhereItWasCut() throws {
        try write("AGENTS.md", String(repeating: "가", count: ProjectInstructions.maximumCharacters + 500))

        let loaded = try XCTUnwrap(ProjectInstructions.load(projectPath: project.path))

        XCTAssertTrue(loaded.hasSuffix("[cut here: this file is longer than Puck reads]"))
        XCTAssertLessThan(loaded.count, ProjectInstructions.maximumCharacters + 100)
    }

    // MARK: - How it reaches the model

    func test_thePromptSaysWhoseInstructionsTheseAreAndWhatTheyDecide() throws {
        try write("AGENTS.md", "커밋 메시지는 영어로")

        let section = try XCTUnwrap(ProjectInstructions.promptSection(for: project.path))

        XCTAssertTrue(section.contains("커밋 메시지는 영어로"))
        XCTAssertTrue(section.contains("project"), "the model has to be able to tell them from its own")
        // A file in a repository is something a pull request could have put
        // there, so it decides how work is done and not what is allowed.
        XCTAssertTrue(section.lowercased().contains("do not grant permissions"))
    }

    func test_aProjectWithNoInstructionsAddsNothingToThePrompt() {
        XCTAssertNil(ProjectInstructions.promptSection(for: project.path))
    }
}
