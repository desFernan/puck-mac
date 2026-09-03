//
//  AvatarManifestEditor.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Reads/writes the *currently installed* avatar's manifest.json -- backs
//  Settings' size slider and per-emotion image mapping (2026-07-29).
//
//  Deliberately separate from AvatarLoader: AvatarLoader's job is validating
//  a package is loadable at boot (required-clip enforcement); this only
//  needs to read/patch/write the manifest a Settings screen already trusts
//  to exist (the app is running against it right now).

import Foundation

enum AvatarManifestEditorError: Error {
    case manifestNotFound
    /// A custom emotion name (Settings' TextField, only whitespace-trimmed)
    /// containing "/" or made entirely of dots would let `"\(emotion).png"`
    /// land outside the avatar directory, or overwrite an unrelated file.
    case invalidEmotionName(String)
}

enum AvatarManifestEditor {
    /// Where AppDelegate loads the active avatar from -- `name` is
    /// `SettingsStore.selectedAvatarName`. Settings edits this same
    /// directory pet-app is actually running against.
    static func currentAvatarDirectory(named name: String) -> URL {
        AvatarCatalogue.avatarsDirectory.appendingPathComponent(name, isDirectory: true)
    }

    static func loadManifest(directory: URL) throws -> AvatarManifest {
        let url = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else {
            throw AvatarManifestEditorError.manifestNotFound
        }
        return try JSONDecoder().decode(AvatarManifest.self, from: data)
    }

    private static func save(_ manifest: AvatarManifest, directory: URL) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    /// Settings' size slider.
    @discardableResult
    static func updateScale(_ scale: Double, directory: URL) throws -> AvatarManifest {
        let existing = try loadManifest(directory: directory)
        let updated = AvatarManifest(
            schemaVersion: existing.schemaVersion,
            name: existing.name,
            type: existing.type,
            scale: scale,
            bounceIntensity: existing.bounceIntensity,
            hitbox: existing.hitbox,
            clips: existing.clips,
            emotions: existing.emotions,
            sounds: existing.sounds
        )
        try save(updated, directory: directory)
        return updated
    }

    /// Settings' emotion mapping: copies `sourceFile` in as `{emotion}.png`
    /// (overwriting any previous image for that key) and points
    /// manifest.emotions[emotion] at it.
    @discardableResult
    /// Replaces the avatar's base drawing.
    ///
    /// `idle` and nothing else: every other clip already falls back to it
    /// when a package does not name its own -- see
    /// AvatarLoader.resolvedClipName -- so one picture is a complete avatar,
    /// and this is the picture. Writing all the clips instead would make an
    /// avatar that cannot later be given a walk of its own without clearing
    /// them by hand.
    static func setBaseImage(sourceFile: URL, directory: URL) throws -> AvatarManifest {
        let existing = try loadManifest(directory: directory)

        let destination = directory.appendingPathComponent("idle.png")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: sourceFile, to: destination)

        var clips = existing.clips
        clips["idle"] = .name("idle")

        let updated = AvatarManifest(
            schemaVersion: existing.schemaVersion,
            name: existing.name,
            type: existing.type,
            scale: existing.scale,
            bounceIntensity: existing.bounceIntensity,
            hitbox: existing.hitbox,
            clips: clips,
            emotions: existing.emotions,
            sounds: existing.sounds
        )
        try save(updated, directory: directory)
        return updated
    }

    static func setEmotionImage(named emotion: String, sourceFile: URL, directory: URL) throws -> AvatarManifest {
        guard isValidEmotionName(emotion) else {
            throw AvatarManifestEditorError.invalidEmotionName(emotion)
        }
        let existing = try loadManifest(directory: directory)

        let destination = directory.appendingPathComponent("\(emotion).png")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: sourceFile, to: destination)

        var emotions = existing.emotions ?? [:]
        emotions[emotion] = .name(emotion)

        let updated = AvatarManifest(
            schemaVersion: existing.schemaVersion,
            name: existing.name,
            type: existing.type,
            scale: existing.scale,
            bounceIntensity: existing.bounceIntensity,
            hitbox: existing.hitbox,
            clips: existing.clips,
            emotions: emotions,
            sounds: existing.sounds
        )
        try save(updated, directory: directory)
        return updated
    }

    /// No path separators, and not made entirely of dots (rules out "." and
    /// the traversal case "..") -- an emotion name is a bare file-stem, never
    /// a path.
    static func isValidEmotionName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.allSatisfy { $0 == "." }
    }
}
