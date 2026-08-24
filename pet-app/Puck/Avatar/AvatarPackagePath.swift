//
//  AvatarPackagePath.swift
//  Puck
//
//  Resolves a name out of an avatar's manifest against that avatar's own
//  directory, and refuses anything that lands outside it.
//

import Foundation

/// manifest.json is data an avatar package brings with it, and packages come
/// from wherever the person who installed one got it. The clip and sound
/// tables were joined onto the package directory verbatim, so a manifest that
/// named `../../../../etc/passwd` -- or an absolute path -- read a file that
/// has nothing to do with the avatar. The clip case only rendered it if it
/// happened to decode as a PNG, but the read itself is the part that should
/// not have happened.
enum AvatarPackagePath {
    /// `relativePath` resolved inside `directory`, or nil if it points
    /// anywhere else.
    ///
    /// The check is on the path, not on the file: a symlink placed inside the
    /// package still leads where it leads. That is a package the person
    /// installed, and it is the same trust as the images themselves; what is
    /// refused here is the manifest reaching out on its own.
    static func fileURL(in directory: URL, relativePath: String) -> URL? {
        guard !relativePath.isEmpty else { return nil }
        // Rebuilt as a directory URL: a caller that made `directory` without
        // `isDirectory: true` (the filesystem is asked, and the folder may not
        // exist yet) leaves a URL that resolves relative paths against its
        // *parent*, which turned every legitimate name into a refusal.
        let base = URL(fileURLWithPath: directory.path, isDirectory: true).standardizedFileURL
        let candidate = URL(fileURLWithPath: relativePath, relativeTo: base).standardizedFileURL
        guard candidate.path.hasPrefix(base.path + "/") else { return nil }
        return candidate
    }
}
