//
//  AvatarImportValidator.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Import-menu validator: checks manifest schema + clip existence, reports missing items
//
//  Checks manifest schema/required-clip-keys (via AvatarLoader) plus the
//  file-per-clip layout from docs/avatar-spec.md: each clip's {name}.png
//  (sprites, 2026-07-29's primary type) or {name}.usdz (legacy) must actually
//  exist in the package directory and fit the size budget. Does NOT check
//  image dimensions or usdz mesh height/scale/loop pose-matching — that needs
//  a real fixture to verify against, and isn't wired up yet (see docs/avatar-spec.md).

import Foundation

enum AvatarImportValidator {
    /// Per-clip file size budget. Generous for both PNG sprites (each just a
    /// static image, typically well under this) and the legacy usdz path
    /// (only the mesh-carrying clip holds real geometry/textures there).
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
    /// (manifest not decodable, unsupported schema version, missing required
    /// clip *keys*) before doing the file-per-clip disk checks this type adds.
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
            // 2026-07-29 2D switch: sprites clips are PNG files, not usdz.
            let fileExtension = manifest.type == .sprites ? "png" : "usdz"
            guard let url = AvatarPackagePath.fileURL(
                in: packageDirectory,
                relativePath: "\(fileName).\(fileExtension)"
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
