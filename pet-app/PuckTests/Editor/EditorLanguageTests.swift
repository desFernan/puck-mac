//
//  EditorLanguageTests.swift
//  Puck
//
//  Locked against the same extension set as file-service.ts's languageFor()
//  to catch silent drift between the two ports.
//

import XCTest
@testable import Puck

final class EditorLanguageTests: XCTestCase {
    private static let expectedByExtension: [String: String] = [
        "ts": "typescript",
        "tsx": "typescript",
        "js": "javascript",
        "jsx": "javascript",
        "json": "json",
        "md": "markdown",
        "css": "css",
        "html": "html",
        "py": "python",
        "rs": "rust",
        "swift": "swift",
        "sh": "shell",
        "yml": "yaml",
        "yaml": "yaml",
    ]

    func test_mapsEveryKnownExtension() {
        for (ext, expected) in Self.expectedByExtension {
            XCTAssertEqual(EditorLanguage.displayName(forPath: "file.\(ext)"), expected, "extension .\(ext)")
        }
    }

    func test_isCaseInsensitive() {
        XCTAssertEqual(EditorLanguage.displayName(forPath: "file.TS"), "typescript")
        XCTAssertEqual(EditorLanguage.displayName(forPath: "file.Swift"), "swift")
    }

    func test_unknownExtension_returnsNil() {
        XCTAssertNil(EditorLanguage.displayName(forPath: "file.xyz"))
    }

    func test_noExtension_returnsNil() {
        XCTAssertNil(EditorLanguage.displayName(forPath: "Makefile"))
    }
}
