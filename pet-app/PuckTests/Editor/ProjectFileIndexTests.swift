//
//  ProjectFileIndexTests.swift
//  PuckTests
//
//  Listing a project's files by name, and ranking them the way somebody
//  typing a name expects.
//

import XCTest
@testable import Puck

final class ProjectFileIndexTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    func test_itListsEveryFileByItsPathRelativeToTheProject() throws {
        try write("Sources/App/main.swift")
        try write("README.md")

        let index = ProjectFileIndex.build(root: root)

        XCTAssertEqual(Set(index.paths), ["Sources/App/main.swift", "README.md"])
    }

    /// A file in `node_modules` is a by-product, not something anybody means
    /// to talk about -- and walking one is what would make this too slow to
    /// run from a keystroke.
    func test_theDirectoriesABuildToolOwnsAreNotWalked() throws {
        try write("src/index.js")
        try write("node_modules/left-pad/index.js")
        try write(".git/config")

        let index = ProjectFileIndex.build(root: root)

        XCTAssertEqual(index.paths, ["src/index.js"])
    }

    /// Hidden *files* are kept: `.gitignore` and a CI workflow are things
    /// people ask about by name.
    func test_hiddenFilesAreKeptEvenThoughHiddenBuildDirectoriesAreNot() throws {
        try write(".gitignore")
        try write(".github/workflows/ci.yml")

        let index = ProjectFileIndex.build(root: root)

        XCTAssertEqual(Set(index.paths), [".gitignore", ".github/workflows/ci.yml"])
    }

    func test_finderSLeftoversAreNotFiles() throws {
        try write("a.swift")
        try write(".DS_Store")

        XCTAssertEqual(ProjectFileIndex.build(root: root).paths, ["a.swift"])
    }

    // MARK: - What gets offered

    private let index = ProjectFileIndex(paths: [
        "Puck/Agent/Skills/SkillFrontmatter.swift",
        "Puck/Agent/Skills/Skill.swift",
        "Puck/Agent/Skills/SkillCatalog.swift",
        "docs/skills.md",
        "Puck/Movement/WalkState.swift",
    ])

    /// The file actually called that comes first, whatever else contains the
    /// word -- "skill" is somebody reaching for Skill.swift.
    func test_theFileActuallyCalledThatIsOfferedFirst() {
        XCTAssertEqual(index.suggestions(for: "skill").first, "Puck/Agent/Skills/Skill.swift")
    }

    /// A name match beats a match on a directory halfway up the path, which
    /// is the weakest reason to offer something.
    func test_aNameMatchBeatsAPathMatch() {
        let offered = index.suggestions(for: "skills")

        XCTAssertEqual(offered.first, "docs/skills.md")
        XCTAssertTrue(offered.contains("Puck/Agent/Skills/Skill.swift"), "the directory match is still offered, just later")
    }

    func test_aMatchAnywhereInThePathStillCounts() {
        XCTAssertEqual(index.suggestions(for: "movement"), ["Puck/Movement/WalkState.swift"])
    }

    func test_matchingIsCaseInsensitive() {
        XCTAssertEqual(index.suggestions(for: "WALKSTATE"), ["Puck/Movement/WalkState.swift"])
    }

    /// `@` on its own is somebody asking what there is.
    func test_anEmptyQueryOffersSomethingRatherThanNothing() {
        XCTAssertEqual(index.suggestions(for: "", limit: 2).count, 2)
    }

    func test_nothingMatchingOffersNothing() {
        XCTAssertTrue(index.suggestions(for: "zzzz").isEmpty)
    }

    /// More than a handful and nobody reads them.
    func test_theListIsCapped() {
        let many = ProjectFileIndex(paths: (0..<50).map { "file\($0).swift" })

        XCTAssertEqual(many.suggestions(for: "file").count, ProjectFileIndex.maximumSuggestions)
    }
}
