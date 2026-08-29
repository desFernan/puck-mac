//
//  AvatarInstaller.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Seeds the bundled dummy avatar into Application Support on first run.
//
//  AvatarLoader reads from ~/Library/Application Support/Puck/Avatars/
//  {name}/, but the only thing writing there was AvatarManagementView's
//  user-driven import — so a fresh clone launched with no avatar and the pet
//  never appeared. The bundled dummy is what makes the app run immediately
//  after cloning.
//

import Foundation

enum AvatarInstaller {
    enum Outcome: Equatable {
        case installed
        /// Something is already installed under that name — left untouched.
        case alreadyPresent
        /// The app bundle carries no package to seed at all (e.g. a build
        /// missing Puck/Resources/Avatars/dummy from its target membership).
        case noBundledPackage
        case failed(String)
    }

    /// A real usdz is a zip archive; a git-lfs pointer left behind by a clone
    /// that skipped `git lfs pull` is ~130 bytes of this exact text. Checking
    /// the prefix is enough — no legitimate usdz starts with it.
    private static let lfsPointerPrefix = "version https://git-lfs.github.com/spec/v1"

    /// Copies `bundledPackage` to `intoAvatarsDirectory/<package name>` unless
    /// something is already there. Never overwrites a real existing install:
    /// the installed copy belongs to the user, who may have imported a real
    /// avatar over it. A destination directory missing its manifest.json is
    /// not a real install (a previous copy that died partway through) and is
    /// repaired rather than left broken forever.
    ///
    /// `overwriteExisting` is for the user-driven "Import Avatar Package…"
    /// flow (AvatarManagementView), which explicitly means to replace
    /// whatever's there -- it used to reimplement this copy-in logic by hand
    /// instead of going through here, silently skipping the LFS-pointer check
    /// below (found via review).
    @discardableResult
    static func installIfNeeded(
        bundledPackage: URL,
        intoAvatarsDirectory avatarsDirectory: URL,
        overwriteExisting: Bool = false
    ) -> Outcome {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: bundledPackage.path) else {
            return .noBundledPackage
        }

        let destination = avatarsDirectory.appendingPathComponent(bundledPackage.lastPathComponent, isDirectory: true)
        let destinationManifest = destination.appendingPathComponent("manifest.json")
        guard overwriteExisting || !fileManager.fileExists(atPath: destinationManifest.path) else {
            return .alreadyPresent
        }

        if let pointerFile = firstUnpulledLFSPointerFile(in: bundledPackage) {
            return .failed("bundled asset '\(pointerFile)' is an un-pulled Git LFS pointer, not real content -- run 'git lfs pull'")
        }

        do {
            try? fileManager.removeItem(at: destination) // clear a partial/broken previous copy, if any
            try fileManager.createDirectory(at: avatarsDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: bundledPackage, to: destination)
            return .installed
        } catch {
            return .failed(String(describing: error))
        }
    }

    /// Scans the top level of `package` for a file whose content is a Git LFS
    /// pointer instead of real data. A pointer file is tiny (well under any
    /// real usdz/wav), so reading a small prefix is cheap even for a large
    /// asset that's actually real.
    private static func firstUnpulledLFSPointerFile(in package: URL) -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: package, includingPropertiesForKeys: nil) else {
            return nil
        }
        for entry in entries {
            guard let handle = try? FileHandle(forReadingFrom: entry) else { continue }
            defer { try? handle.close() }
            let prefix = (try? handle.read(upToCount: lfsPointerPrefix.utf8.count)) ?? Data()
            if String(data: prefix, encoding: .utf8) == lfsPointerPrefix {
                return entry.lastPathComponent
            }
        }
        return nil
    }
}
