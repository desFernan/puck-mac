//
//  FuzzyPathMatchTests.swift
//  PuckTests
//
//  What "open quickly" has to get right: the obvious file first.
//

import XCTest
@testable import Puck

final class FuzzyPathMatchTests: XCTestCase {
    private let paths = [
        "Puck/ClientWindow/Editor/EditorPaneStore.swift",
        "Puck/ClientWindow/Editor/Views/EditorPaneView.swift",
        "Puck/Movement/BallPhysics.swift",
        "docs/tasks.md",
        "README.md",
    ]

    func test_initials_findTheFileTheyAbbreviate() {
        XCTAssertEqual(
            FuzzyPathMatch.matches("eps", in: paths).first,
            "Puck/ClientWindow/Editor/EditorPaneStore.swift"
        )
    }

    func test_aPlainName_findsIt() {
        XCTAssertEqual(FuzzyPathMatch.matches("ballphys", in: paths).first, "Puck/Movement/BallPhysics.swift")
    }

    /// Typing part of the file's own name should beat the same letters
    /// spread across the directories above it.
    func test_aMatchInTheFileName_outranksOneInTheDirectories() {
        let ranked = FuzzyPathMatch.matches("tasks", in: paths)

        XCTAssertEqual(ranked.first, "docs/tasks.md")
    }

    func test_letters_thatAreNotThere_matchNothing() {
        XCTAssertTrue(FuzzyPathMatch.matches("zzzz", in: paths).isEmpty)
    }

    /// A box that opens on nothing is a box that has to be typed into before
    /// it says anything at all.
    func test_anEmptyQuery_offersTheProjectsFiles() {
        XCTAssertEqual(FuzzyPathMatch.matches("", in: paths).count, paths.count)
    }

    func test_theLimit_isHonoured() {
        XCTAssertEqual(FuzzyPathMatch.matches("", in: paths, limit: 2).count, 2)
    }

    func test_matching_ignoresCase() {
        XCTAssertEqual(FuzzyPathMatch.matches("READ", in: paths).first, "README.md")
        XCTAssertEqual(FuzzyPathMatch.matches("readme", in: paths).first, "README.md")
    }

    /// Letters have to appear in the order they were typed -- otherwise the
    /// box answers with files that merely contain the same letters.
    func test_orderMatters() {
        XCTAssertNil(FuzzyPathMatch.score("dm", against: "md"))
        XCTAssertNotNil(FuzzyPathMatch.score("md", against: "md"))
    }

    /// Consecutive letters are a better answer than the same letters
    /// scattered, which is what keeps the exact file above its neighbours.
    func test_consecutiveLetters_scoreHigherThanScatteredOnes() throws {
        let together = try XCTUnwrap(FuzzyPathMatch.score("edit", against: "edit.swift"))
        let scattered = try XCTUnwrap(FuzzyPathMatch.score("edit", against: "e_d_i_t.swift"))

        XCTAssertGreaterThan(together, scattered)
    }
}
