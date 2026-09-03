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

import CryptoKit
import Foundation

enum AvatarInstaller {
    /// Who put the installed copy there.
    ///
    /// Recorded beside it, because "is this ours" is the only way to tell a
    /// stale copy we seeded from an avatar the user chose -- and the two want
    /// opposite treatment. Ours may be replaced; theirs may never be.
    enum Origin: Equatable {
        case bundled
        case userImport
    }

    enum Outcome: Equatable {
        case installed
        /// Ours, and out of date: replaced with what the app now carries.
        case replaced
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
    /// what is already there is the user's.
    ///
    /// An avatar the user imported is never touched. A copy this app seeded
    /// is replaced when the app now carries a different one -- which it did
    /// not used to do, and that turned out to matter: the bundled avatar was
    /// withdrawn and replaced, and every machine that had already run the app
    /// went on using the withdrawn one, because the installer saw a
    /// manifest.json and stopped. Shipping a replacement is no use if it is
    /// never installed.
    ///
    /// A copy with no marker beside it predates all of this. It is treated as
    /// ours and replaced, which is the whole point -- those are the machines
    /// still carrying the withdrawn package. The narrow cost is somebody who
    /// imported an avatar of their own named exactly like the bundled one
    /// before markers existed; they are asked to import it again, which is
    /// the lesser of the two wrongs here.
    ///
    /// A destination directory missing its manifest.json is not a real
    /// install (a previous copy that died partway through) and is repaired
    /// rather than left broken forever.
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
        overwriteExisting: Bool = false,
        origin: Origin = .bundled
    ) -> Outcome {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: bundledPackage.path) else {
            return .noBundledPackage
        }

        let destination = avatarsDirectory.appendingPathComponent(bundledPackage.lastPathComponent, isDirectory: true)
        let destinationManifest = destination.appendingPathComponent("manifest.json")
        let isPresent = fileManager.fileExists(atPath: destinationManifest.path)
        var replacing = false

        if isPresent, !overwriteExisting {
            switch marker(at: destination) {
            case .some("user"):
                return .alreadyPresent
            case .some(let recorded) where recorded == seedMarker(for: bundledPackage):
                return .alreadyPresent
            default:
                // Ours and stale, or from before markers existed. Either way
                // the app carries something newer.
                replacing = true
            }
        }

        if let pointerFile = firstUnpulledLFSPointerFile(in: bundledPackage) {
            return .failed("bundled asset '\(pointerFile)' is an un-pulled Git LFS pointer, not real content -- run 'git lfs pull'")
        }

        do {
            try? fileManager.removeItem(at: destination) // clear a partial/broken previous copy, if any
            try fileManager.createDirectory(at: avatarsDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: bundledPackage, to: destination)
            writeMarker(
                origin == .userImport ? "user" : seedMarker(for: bundledPackage),
                at: destination
            )
            return replacing ? .replaced : .installed
        } catch {
            return .failed(String(describing: error))
        }
    }

    // MARK: - Telling our copy from theirs

    /// The file recording who put the installed package there. A dotfile, so
    /// it is not mistaken for part of the avatar by anything listing it.
    static let markerName = ".puck-origin"

    /// What the bundled package looks like right now.
    ///
    /// Every file's name and length, plus the manifest itself. Names and
    /// lengths rather than contents so seeding stays cheap on a package of
    /// sprites, and both rather than the manifest alone -- artwork can be
    /// replaced without a word of the manifest changing, which is exactly
    /// what happened.
    static func seedMarker(for package: URL) -> String {
        let fileManager = FileManager.default
        let entries = (try? fileManager.contentsOfDirectory(
            at: package,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        let listing = entries
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { url -> String in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return "\(url.lastPathComponent):\(size)"
            }
            .sorted()
            .joined(separator: "\n")
        let digest = SHA256.hash(data: Data(listing.utf8))
        return "bundled:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func marker(at package: URL) -> String? {
        try? String(
            contentsOf: package.appendingPathComponent(markerName),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func writeMarker(_ value: String, at package: URL) {
        try? value.write(
            to: package.appendingPathComponent(markerName),
            atomically: true,
            encoding: .utf8
        )
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
