//
//  EditorLanguage.swift
//  Puck
//
//  Swift port of file-service.ts's languageFor() -- a pure extension-to-
//  display-name lookup for FileContent.language (badge display, wire
//  parity). Separate from CodeLanguage (CodeEditLanguages), which the
//  editor view derives itself via CodeLanguage.detectLanguageFrom(url:)
//  for actual tree-sitter syntax highlighting.
//

import Foundation

enum EditorLanguage {
    static func displayName(forPath path: String) -> String? {
        let extensionName = "." + (path as NSString).pathExtension.lowercased()
        return map[extensionName]
    }

    private static let map: [String: String] = [
        ".ts": "typescript",
        ".tsx": "typescript",
        ".js": "javascript",
        ".jsx": "javascript",
        ".json": "json",
        ".md": "markdown",
        ".css": "css",
        ".html": "html",
        ".py": "python",
        ".rs": "rust",
        ".swift": "swift",
        ".sh": "shell",
        ".yml": "yaml",
        ".yaml": "yaml",
    ]
}
