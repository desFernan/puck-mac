//
//  SkillCatalogTests.swift
//  Puck
//

import XCTest
@testable import Puck

final class SkillFrontmatterTests: XCTestCase {
    func test_readsAPlainNameAndDescription() {
        let parsed = SkillFrontmatter.parse("""
        ---
        name: computer-use
        description: Drive a desktop app.
        ---

        # Computer Use
        """)
        XCTAssertEqual(parsed?.name, "computer-use")
        XCTAssertEqual(parsed?.description, "Drive a desktop app.")
    }

    /// The shape these are actually written in: a folded scalar wrapping the
    /// description across lines. Read line-by-line it comes back as ">-".
    func test_foldsAWrappedDescriptionIntoOneLine() {
        let parsed = SkillFrontmatter.parse("""
        ---
        name: orca-cli
        description: >-
          Use the public orca CLI to operate worktrees,
          terminals and repos.
        ---
        """)
        XCTAssertEqual(parsed?.description, "Use the public orca CLI to operate worktrees, terminals and repos.")
    }

    /// A literal block keeps its line breaks, which is the whole difference
    /// between `|` and `>`.
    func test_aLiteralBlockKeepsItsLineBreaks() {
        let parsed = SkillFrontmatter.parse("""
        ---
        name: n
        description: |
          first
          second
        ---
        """)
        XCTAssertEqual(parsed?.description, "first\nsecond")
    }

    func test_stripsSurroundingQuotes() {
        let parsed = SkillFrontmatter.parse("---\nname: \"quoted\"\ndescription: 'also'\n---")
        XCTAssertEqual(parsed?.name, "quoted")
        XCTAssertEqual(parsed?.description, "also")
    }

    /// A colon inside the value is part of the value -- descriptions are full
    /// of them ("Use when: ...").
    func test_splitsOnTheFirstColonOnly() {
        let parsed = SkillFrontmatter.parse("---\nname: n\ndescription: Use when: you need it\n---")
        XCTAssertEqual(parsed?.description, "Use when: you need it")
    }

    /// Worth listing without one: hiding it would hide the skill from
    /// whoever is trying to work out where a behaviour came from.
    func test_aMissingDescriptionIsEmptyRatherThanAFailure() {
        let parsed = SkillFrontmatter.parse("---\nname: bare\n---")
        XCTAssertEqual(parsed?.name, "bare")
        XCTAssertEqual(parsed?.description, "")
    }

    func test_nilWhenThereIsNoFrontmatterAtAll() {
        XCTAssertNil(SkillFrontmatter.parse("# Just a heading\n"))
        XCTAssertNil(SkillFrontmatter.parse("---\nname: unterminated\n"))
        XCTAssertNil(SkillFrontmatter.parse(""))
    }
}

final class SkillCatalogTests: XCTestCase {
    private var directories: [URL] = []

    override func tearDown() {
        for url in directories { try? FileManager.default.removeItem(at: url) }
        directories = []
        super.tearDown()
    }

    private func makeSkills(_ named: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("puck-skills-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        directories.append(root)
        for (name, description) in named {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "---\nname: \(name)\ndescription: \(description)\n---\n"
                .write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        return root
    }

    func test_readsEverySkillInADirectory() throws {
        let root = try makeSkills(["alpha": "first", "beta": "second"])
        let skills = SkillCatalog.skills(in: root, source: .personal)

        XCTAssertEqual(skills.map(\.name), ["alpha", "beta"], "alphabetical, so a second read scans the same")
        XCTAssertEqual(skills.first?.description, "first")
        XCTAssertEqual(skills.first?.source, .personal)
        XCTAssertTrue(skills.first?.path.hasSuffix("alpha/SKILL.md") ?? false)
    }

    /// `.claude/skills` holds other things too, and a directory without a
    /// manifest is not a broken skill -- it is not a skill.
    func test_skipsDirectoriesWithNoManifest() throws {
        let root = try makeSkills(["real": "yes"])
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("not-a-skill", isDirectory: true),
            withIntermediateDirectories: true
        )
        XCTAssertEqual(SkillCatalog.skills(in: root, source: .personal).map(\.name), ["real"])
    }

    /// A name in both places is the project's: that is the one the CLI
    /// loads, and listing two would say otherwise.
    func test_theProjectsCopyWinsOverThePersonalOne() throws {
        let personal = try makeSkills(["shared": "the personal one", "only-mine": "kept"])
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("puck-proj-\(UUID().uuidString)", isDirectory: true)
        let projectSkills = projectRoot
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("shared", isDirectory: true)
        try FileManager.default.createDirectory(at: projectSkills, withIntermediateDirectories: true)
        directories.append(projectRoot)
        try "---\nname: shared\ndescription: the project one\n---\n"
            .write(to: projectSkills.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let found = SkillCatalog.discover(projectPath: projectRoot.path, personalDirectory: personal)

        XCTAssertEqual(found.map(\.name), ["shared", "only-mine"], "the project's comes first and is not repeated")
        XCTAssertEqual(found.first?.description, "the project one")
        XCTAssertEqual(found.first?.source, .project)
        XCTAssertEqual(found.last?.source, .personal)
    }

    func test_aWorkspaceWithNoProjectStillListsThePersonalOnes() throws {
        let personal = try makeSkills(["only-mine": "kept"])
        let found = SkillCatalog.discover(projectPath: nil, personalDirectory: personal)
        XCTAssertEqual(found.map(\.name), ["only-mine"])
    }

    func test_aMissingDirectoryIsNoSkillsRatherThanAnError() {
        let absent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertTrue(SkillCatalog.skills(in: absent, source: .project).isEmpty)
    }

    /// The name is what the CLI keys on, so a manifest that forgot `name:`
    /// still belongs to its folder.
    func test_fallsBackToTheDirectoryNameWhenTheManifestHasNone() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("puck-skills-\(UUID().uuidString)", isDirectory: true)
        let skill = root.appendingPathComponent("folder-named", isDirectory: true)
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        directories.append(root)
        try "---\ndescription: no name here\n---\n"
            .write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        XCTAssertEqual(SkillCatalog.skills(in: root, source: .personal).map(\.name), ["folder-named"])
    }
}
