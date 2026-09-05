//
//  AvatarImportValidator.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Import-menu validator: checks manifest schema + clip existence, reports missing items
//
//  Checks manifest schema/type/required-clip-keys (via AvatarLoader) plus the
//  file-per-clip package layout: each clip's {name}.png must actually exist in
//  the package directory and fit the size budget. Does NOT check image
//  dimensions — that needs a real fixture to verify against, and isn't wired
//  up yet.

import Foundation

enum AvatarImportValidator {
    /// Per-clip file size budget. Generous for a PNG sprite, which is one
    /// static image and typically well under this.
    static let maxClipFileSizeBytes = 4 * 1024 * 1024

    struct Report: Equatable {
        let manifest: AvatarManifest
        /// Required clip files missing from disk — fatal; AvatarManagementView should refuse import.
        let missingRequiredClipFiles: [String]
        /// Recommended clip files missing from disk — non-fatal, falls back to idle at runtime.
        let missingRecommendedClipFiles: [String]
        /// Present but over the size budget — non-fatal, the budget is a "recommended" guideline.
        let oversizedClipFiles: [String]

        var isValid: Bool { missingRequiredClipFiles.isEmpty }
    }

    private enum ClipFileStatus: Equatable {
        case ok
        case missing
        case oversized
    }

    /// Validates a package directory. Throws whatever AvatarLoader.load throws
    /// (manifest not decodable, unsupported schema version, an avatar type
    /// this build cannot draw, missing required clip *keys*) before doing the
    /// file-per-clip disk checks this type adds.
    static func validate(packageDirectory: URL) throws -> Report {
        let loadResult = try AvatarLoader.load(avatarDirectory: packageDirectory)
        return report(for: loadResult, packageDirectory: packageDirectory)
    }

    static func report(for loadResult: AvatarLoadResult, packageDirectory: URL) -> Report {
        let manifest = loadResult.manifest

        func status(for clip: String) -> ClipFileStatus {
            guard case .name(let fileName) = manifest.clips[clip] else {
                return .missing
            }
            // One PNG per clip: AvatarLoader has already refused every other
            // kind of package, so there is only the one extension to look for.
            guard let url = AvatarPackagePath.fileURL(
                in: packageDirectory,
                relativePath: "\(fileName).png"
            ) else {
                // Reported as missing rather than ok: nothing inside the
                // package answers to that name, which is what the report is
                // about.
                return .missing
            }
            guard
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                let size = attributes[.size] as? Int
            else {
                return .missing
            }
            return size > maxClipFileSizeBytes ? .oversized : .ok
        }

        let missingRequired = AvatarLoader.requiredClips.filter { status(for: $0) == .missing }
        let missingRecommended = AvatarLoader.recommendedClips.filter { status(for: $0) == .missing }
        let oversized = (AvatarLoader.requiredClips + AvatarLoader.recommendedClips)
            .filter { status(for: $0) == .oversized }

        return Report(
            manifest: manifest,
            missingRequiredClipFiles: missingRequired,
            missingRecommendedClipFiles: missingRecommended,
            oversizedClipFiles: oversized
        )
    }
}
