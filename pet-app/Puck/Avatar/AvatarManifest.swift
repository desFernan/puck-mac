//
//  AvatarManifest.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  manifest.json Codable model (mirrors protocol repo section 6 schema).
//

/// A value in the clips table.
///
/// For `type: usdz`, `.name(String)` is the file stem of a **single-animation**
/// usdz living alongside manifest.json (e.g. "idle" -> Avatars/{name}/idle.usdz)
/// — NOT an animation name to look up inside one shared model. RealityKit
/// effectively only plays a usdz's first animation regardless of how many
/// `availableAnimations` entries it reports, so one avatar with 10 named clips
/// baked into a single usdz does not work; each clip needs its own file. See
/// the avatar package spec for the full external-creator requirements.
///
/// `type: sprites` reuses the same file-stem convention. `type: video` uses
/// a {"in":sec,"out":sec} time range instead (`.timeRange`).
enum ClipReference: Equatable {
    case name(String)
    case timeRange(in: Double, out: Double)
}

extension ClipReference: Codable {
    private enum CodingKeys: String, CodingKey {
        case `in`, out
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let start = try? container.decode(Double.self, forKey: .in),
           let end = try? container.decode(Double.self, forKey: .out) {
            self = .timeRange(in: start, out: end)
            return
        }
        let single = try decoder.singleValueContainer()
        self = .name(try single.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .name(let name):
            var container = encoder.singleValueContainer()
            try container.encode(name)
        case .timeRange(let start, let end):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(start, forKey: .in)
            try container.encode(end, forKey: .out)
        }
    }
}

struct AvatarManifest: Equatable, Codable {
    enum AvatarType: String, Codable {
        case usdz
        case video
        case sprites
    }

    struct Hitbox: Equatable, Codable {
        let width: Double
        let height: Double
    }

    let schemaVersion: Int
    let name: String
    let type: AvatarType
    let scale: Double
    /// 2026-07-29 2D switch, sprites-only: 0.0-1.0 multiplier for the
    /// procedural squash-and-stretch "bounce" motion pet-app applies on top
    /// of a static illustration (no animation frames to play). nil means
    /// pet-app's own default; has no effect for usdz/video avatars.
    let bounceIntensity: Double?
    let hitbox: Hitbox
    let clips: [String: ClipReference]
    /// Optional, same stem-dictionary shape as `clips`, keyed by emotion name
    /// (e.g. "happy"). Swapped to on a matching socket event; absent entirely
    /// is fine for a base-image-only avatar.
    let emotions: [String: ClipReference]?
    let sounds: [String: String]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case bounceIntensity = "bounce_intensity"
        case name, type, scale, hitbox, clips, emotions, sounds
    }

    /// Written out rather than synthesised so `scale` and `sounds` may be left
    /// out of the file.
    ///
    /// Both have an obvious answer when absent -- draw it at the size it was
    /// drawn, play nothing -- and requiring them made the smallest working
    /// avatar two lines of boilerplate longer than it needed to be. Someone
    /// putting one drawing in a folder should not have to write `"scale": 1.0`
    /// and `"sounds": {}` to be told their character is valid.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(AvatarType.self, forKey: .type)
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        bounceIntensity = try container.decodeIfPresent(Double.self, forKey: .bounceIntensity)
        hitbox = try container.decode(Hitbox.self, forKey: .hitbox)
        clips = try container.decode([String: ClipReference].self, forKey: .clips)
        emotions = try container.decodeIfPresent([String: ClipReference].self, forKey: .emotions)
        sounds = try container.decodeIfPresent([String: String].self, forKey: .sounds) ?? [:]
    }

    init(
        schemaVersion: Int,
        name: String,
        type: AvatarType,
        scale: Double,
        bounceIntensity: Double?,
        hitbox: Hitbox,
        clips: [String: ClipReference],
        emotions: [String: ClipReference]?,
        sounds: [String: String]
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.type = type
        self.scale = scale
        self.bounceIntensity = bounceIntensity
        self.hitbox = hitbox
        self.clips = clips
        self.emotions = emotions
        self.sounds = sounds
    }
}
