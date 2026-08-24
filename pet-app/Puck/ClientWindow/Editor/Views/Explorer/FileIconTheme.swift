//
//  FileIconTheme.swift
//  Puck
//
//  Material Icon Theme in the editor's file tree (2026-08-15). Vendored by
//  scripts/vendor-file-icons.sh -- see that script for where it comes from and
//  why the released .vsix is the source rather than the git repo.
//
//  Two reasons this is a small file: the theme ships a resolved
//  extension/filename/folder -> icon-name map, so there is no pattern matching
//  to reimplement, and NSImage reads SVG natively on macOS, so there is no
//  renderer to integrate. What is left is lookup order and a cache.
//

import AppKit
import SwiftUI

/// Resolves a file or folder to its Material icon.
///
/// Loaded once and shared: the map is ~350KB of JSON and the icons are read
/// from disk on first use, neither of which should happen per row in a list
/// that rebuilds on every keystroke in the filter field.
@MainActor
final class FileIconTheme {
    static let shared = FileIconTheme()

    private struct IconMap: Decodable {
        let file: String
        let folder: String
        let folderExpanded: String
        let fileExtensions: [String: String]
        let fileNames: [String: String]
        let folderNames: [String: String]
        let folderNamesExpanded: [String: String]
    }

    private let map: IconMap?
    private let iconDirectory: URL?
    /// icon name -> image. Misses are cached as nil too, so a project full of
    /// files with no icon does not re-hit the filesystem for each one.
    private var cache: [String: NSImage?] = [:]
    private let lock = NSLock()

    private init(bundle: Bundle = .main) {
        let directory = bundle.url(forResource: "FileIcons", withExtension: nil)
        iconDirectory = directory?.appendingPathComponent("icons")
        map = directory
            .map { $0.appendingPathComponent("icon-map.json") }
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(IconMap.self, from: $0) }
    }

    /// - Parameter isExpanded: folders only; an open folder gets its own icon,
    ///   which is most of what makes a Material tree readable while browsing.
    func icon(for entry: FileTreeEntry, isExpanded: Bool = false) -> NSImage? {
        guard let map else { return nil }
        switch entry.kind {
        case .directory:
            return image(named: folderIconName(for: entry.name, isExpanded: isExpanded, map: map))
        case .file, .symlink:
            return image(named: fileIconName(for: entry.name, map: map))
        }
    }

    // MARK: - Name resolution

    /// Exact filename first, then the longest matching extension. Both orders
    /// matter: `tsconfig.json` is a filename match that must beat `.json`, and
    /// `component.test.ts` should find `test.ts` before `ts`.
    private func fileIconName(for name: String, map: IconMap) -> String {
        let lowercased = name.lowercased()
        if let byName = map.fileNames[lowercased] { return byName }

        let parts = lowercased.split(separator: ".")
        // Longest suffix first: for a.b.c try "b.c" then "c".
        for start in 1..<max(parts.count, 1) {
            let candidate = parts[start...].joined(separator: ".")
            if let byExtension = map.fileExtensions[candidate] { return byExtension }
        }
        return map.file
    }

    private func folderIconName(for name: String, isExpanded: Bool, map: IconMap) -> String {
        let lowercased = name.lowercased()
        let names = isExpanded ? map.folderNamesExpanded : map.folderNames
        return names[lowercased] ?? (isExpanded ? map.folderExpanded : map.folder)
    }

    // MARK: - Loading

    private func image(named name: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[name] { return cached }
        let loaded = iconDirectory
            .map { $0.appendingPathComponent("\(name).svg") }
            .flatMap { NSImage(contentsOf: $0) }
        // Vector: the tree renders at 14pt but the same image is asked for at
        // other sizes elsewhere, and an SVG rep scales without a second file.
        loaded?.isTemplate = false
        cache[name] = loaded
        return loaded
    }
}

/// One tree row's icon: the vendored Material SVG, or an SF Symbol when the
/// theme is unavailable (a build without the resources) so the tree still
/// reads as a tree rather than losing its leading column.
struct FileIconView: View {
    let entry: FileTreeEntry
    /// 16 rather than 14: this is the only thing in the row that says what
    /// kind of file it is, and Xcode's navigator draws its icons at the row's
    /// full text height rather than under it.
    var size: CGFloat = 16

    var body: some View {
        if let icon = FileIconTheme.shared.icon(for: entry) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackSymbol)
                .font(.system(size: size - 3))
        }
    }

    private var fallbackSymbol: String {
        switch entry.kind {
        case .directory: return "folder"
        case .symlink: return "arrow.triangle.branch"
        case .file: return "doc"
        }
    }
}
