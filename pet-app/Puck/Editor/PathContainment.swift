//
//  PathContainment.swift
//  Puck
//
//  Swift port of workspace/src/shared/path-containment.ts.
//

import Foundation

enum PathContainment {
    /// Whether `candidate` equals `root` or sits inside it. Both must
    /// already be absolute, standardized paths -- this does no resolution
    /// itself (see WorkspaceFileService.realpath for the symlink-aware step).
    static func isInside(root: String, candidate: String) -> Bool {
        let normalizedRoot = root.hasSuffix("/") ? String(root.dropLast()) : root
        return candidate == normalizedRoot || candidate.hasPrefix(normalizedRoot + "/")
    }

    /// `candidate` expressed relative to `root`, or nil if it is not inside.
    /// The root itself is "" -- it is inside, with nothing below it.
    ///
    /// Callers used to strip the root with a bare `hasPrefix(root)` +
    /// `dropFirst(root.count)`, which has no path-component boundary: with a
    /// root of `/Users/me/app`, `/Users/me/app-old/x.swift` passed the check
    /// and came back as `-old/x.swift`. The containment rule lives here, so
    /// the strip that depends on it does too.
    static func relativePath(root: String, candidate: String) -> String? {
        guard isInside(root: root, candidate: candidate) else { return nil }
        let normalizedRoot = root.hasSuffix("/") ? String(root.dropLast()) : root
        return String(candidate.dropFirst(normalizedRoot.count).drop(while: { $0 == "/" }))
    }
}
