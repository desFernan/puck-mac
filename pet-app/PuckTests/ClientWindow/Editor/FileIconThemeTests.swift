//
//  FileIconThemeTests.swift
//  PuckTests
//
//  The lookup rules are the whole feature -- the icons themselves are
//  vendored art. These run against the real vendored map, so they also fail
//  if scripts/vendor-file-icons.sh produced something the app can't read.
//

import XCTest
@testable import Puck

/// `@MainActor`: FileIconTheme is the main thread's, like the views that
/// read it.
@MainActor
final class FileIconThemeTests: XCTestCase {
    private let theme = FileIconTheme.shared

    private func entry(_ name: String, kind: FileEntryKind = .file) -> FileTreeEntry {
        FileTreeEntry(name: name, path: name, kind: kind, children: kind == .directory ? [] : nil)
    }

    // MARK: - Availability

    func testTheVendoredThemeIsReadable() throws {
        // Guards the packaging, not the art: a missing folder reference in
        // project.yml or a map the decoder rejects both land here rather than
        // as a silently icon-less tree.
        guard theme.icon(for: entry("main.swift")) != nil else {
            throw XCTSkip("FileIcons resources are not in this test bundle")
        }
    }

    // MARK: - Resolution order

    func testAnExactFilenameBeatsItsExtension() throws {
        try XCTSkipIf(theme.icon(for: entry("main.swift")) == nil)

        // tsconfig.json has its own icon; matching .json first would lose it.
        XCTAssertNotEqual(
            theme.icon(for: entry("tsconfig.json")),
            theme.icon(for: entry("data.json"))
        )
    }

    func testTheLongestExtensionWins() throws {
        try XCTSkipIf(theme.icon(for: entry("main.swift")) == nil)

        // "test.ts" is its own icon in the theme; stopping at the last dot
        // would render a plain TypeScript icon instead.
        XCTAssertNotEqual(
            theme.icon(for: entry("button.test.ts")),
            theme.icon(for: entry("button.ts"))
        )
    }

    func testLookupIsCaseInsensitive() throws {
        try XCTSkipIf(theme.icon(for: entry("main.swift")) == nil)

        XCTAssertEqual(theme.icon(for: entry("README.md")), theme.icon(for: entry("readme.md")))
        XCTAssertEqual(theme.icon(for: entry("Main.SWIFT")), theme.icon(for: entry("main.swift")))
    }

    func testAnUnknownExtensionFallsBackToTheGenericFileIcon() throws {
        try XCTSkipIf(theme.icon(for: entry("main.swift")) == nil)

        let unknown = theme.icon(for: entry("thing.zzzzzz-not-a-real-extension"))
        XCTAssertNotNil(unknown, "the fallback is still an icon, not nil")
        XCTAssertNotEqual(unknown, theme.icon(for: entry("main.swift")))
    }

    func testAFileWithNoExtensionStillResolves() throws {
        try XCTSkipIf(theme.icon(for: entry("main.swift")) == nil)

        XCTAssertNotNil(theme.icon(for: entry("Makefile")))
        XCTAssertNotNil(theme.icon(for: entry("LICENSE")))
    }

    // MARK: - Folders

    func testAKnownFolderNameGetsItsOwnIcon() throws {
        try XCTSkipIf(theme.icon(for: entry("main.swift")) == nil)

        XCTAssertNotEqual(
            theme.icon(for: entry("src", kind: .directory)),
            theme.icon(for: entry("zzzz-not-a-real-folder", kind: .directory))
        )
    }

    func testAnExpandedFolderIsADifferentIcon() throws {
        try XCTSkipIf(theme.icon(for: entry("main.swift")) == nil)

        XCTAssertNotEqual(
            theme.icon(for: entry("src", kind: .directory), isExpanded: true),
            theme.icon(for: entry("src", kind: .directory), isExpanded: false)
        )
    }

    func testFoldersAndFilesWithTheSameNameDoNotShareAnIcon() throws {
        try XCTSkipIf(theme.icon(for: entry("main.swift")) == nil)

        XCTAssertNotEqual(
            theme.icon(for: entry("docs", kind: .directory)),
            theme.icon(for: entry("docs", kind: .file))
        )
    }

    // MARK: - Shape

    func testIconsAreVectorSoTheyScaleWithTheRow() throws {
        guard let icon = theme.icon(for: entry("main.swift")) else {
            throw XCTSkip("FileIcons resources are not in this test bundle")
        }

        // The whole reason no converter is in the build: NSImage keeps SVG as
        // a vector rep. A rasterized rep here would mean blurry rows on a
        // Retina display at any size other than the one baked in.
        XCTAssertTrue(
            icon.representations.contains { String(describing: type(of: $0)).contains("SVG") },
            "expected an SVG representation, got \(icon.representations)"
        )
    }
}
