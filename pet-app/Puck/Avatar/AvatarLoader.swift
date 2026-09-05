//
//  AvatarLoader.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Scans the Avatars directory + parses the manifest + validates required
//  clips (idle only, as of the 2026-07-29 2D switch).
//

import Foundation

enum AvatarLoaderError: Error, Equatable {
    case avatarNotFound(name: String)
    case manifestNotDecodable(underlying: String)
    /// idle is required because there's no fallback target for it — unlike
    /// recommendedClips, a manifest missing it is rejected outright rather
    /// than "successfully" loaded with a caller left to notice later.
    case missingRequiredClips([String])
    /// A manifest can decode successfully under a *future* schema version
    /// while meaning something different (fields reinterpreted, new required
    /// semantics) — silently trusting it as v1 would misload it with no error.
    case unsupportedSchemaVersion(Int)
    /// A package declaring a kind of avatar this build has no renderer for.
    ///
    /// `sprites` is the only one there is. The 3D renderer the `usdz` type
    /// named was removed in the 2026-07-29 2D switch and `video` was never
    /// built, but the type went on decoding -- so a package declaring either
    /// loaded successfully and then drew nothing at all, because SpriteAvatar
    /// went looking for a PNG per clip and a usdz package has none. An
    /// invisible pet with nothing in the log is the worst of the three
    /// possible answers; this is the second worst, and it says why.
    case unsupportedAvatarType(String)
}

/// Result of a manifest load: the parsed manifest, plus recommended clips
/// that are missing (idle-fallback still applies to those, with a startup
/// warning). Required clips (idle) are guaranteed present — `load` throws
/// instead of returning a result when they're missing.
struct AvatarLoadResult: Equatable {
    let manifest: AvatarManifest
    let missingRecommendedClips: [String]
}

enum AvatarLoader {
    /// The only manifest schema version (protocol section 6) this loader understands.
    static let supportedSchemaVersion = 1
    /// Clips that must exist — there's no fallback target if these are missing.
    /// 2026-07-29 2D switch: relaxed from [idle, walk] to idle alone, so a
    /// single base illustration is enough to run. walk moved to recommendedClips.
    static let requiredClips = ["idle"]
    /// Clips that fall back to idle if missing, but are still warned about at startup.
    static let recommendedClips = [
        "walk", "climb", "fall", "land", "point", "type", "listen", "react_click", "react_drag",
        "kick",
    ]

    /// Reads and loads ~/Library/Application Support/Puck/Avatars/{name}/manifest.json.
    static func load(avatarDirectory: URL) throws -> AvatarLoadResult {
        let manifestURL = avatarDirectory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw AvatarLoaderError.avatarNotFound(name: avatarDirectory.lastPathComponent)
        }
        return try load(manifestData: data)
    }

    /// Parses manifest.json bytes, rejects it if a required clip is missing,
    /// and computes which recommended clips are missing.
    static func load(manifestData: Data) throws -> AvatarLoadResult {
        let manifest: AvatarManifest
        do {
            manifest = try JSONDecoder().decode(AvatarManifest.self, from: manifestData)
        } catch {
            throw AvatarLoaderError.manifestNotDecodable(underlying: String(describing: error))
        }

        guard manifest.schemaVersion == supportedSchemaVersion else {
            throw AvatarLoaderError.unsupportedSchemaVersion(manifest.schemaVersion)
        }

        // Before the clip checks, not after: which files a package is expected
        // to carry follows from its type, so "idle is missing" is the wrong
        // thing to say about a package whose clips were never going to be
        // looked for as PNGs in the first place.
        guard manifest.type == .sprites else {
            throw AvatarLoaderError.unsupportedAvatarType(manifest.type.rawValue)
        }

        let missingRequired = requiredClips.filter { manifest.clips[$0] == nil }
        guard missingRequired.isEmpty else {
            throw AvatarLoaderError.missingRequiredClips(missingRequired)
        }

        let missingRecommended = recommendedClips.filter { manifest.clips[$0] == nil }
        return AvatarLoadResult(manifest: manifest, missingRecommendedClips: missingRecommended)
    }

    /// Returns the requested clip's file stem (e.g. "idle" for idle.png) if
    /// present in the manifest, otherwise falls back to idle's, otherwise nil
    /// if idle itself isn't a string-named file — see ClipReference's doc
    /// comment for why a manifest's clip values are file stems rather than
    /// animation names.
    static func resolvedClipName(for clip: String, in result: AvatarLoadResult) -> String? {
        if case .name(let name) = result.manifest.clips[clip] {
            return name
        }
        if case .name(let name) = result.manifest.clips["idle"] {
            return name
        }
        return nil
    }
}
