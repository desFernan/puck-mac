//
//  AvatarManifest.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  manifest.json Codable model (mirrors protocol repo section 6 schema).
//

/// A value in the clips table.
///
/// `.name(String)` is a file stem beside manifest.json, one file per clip:
/// "idle" means Avatars/{name}/idle.png. A stem rather than an animation name
/// inside one shared model, which is what the 3D renderer this format was
/// written for could not have made work -- it played only a model's first
/// animation however many it declared -- and what the sprite renderer that
/// replaced it kept.
///
/// `.timeRange` is the other shape the format allows, `{"in":sec,"out":sec}`,
/// for a kind of avatar that is one file played in pieces. Nothing draws one
/// today: `AvatarLoader` accepts `type: sprites` alone, and a sprite has no
/// timeline to cut up. It decodes so a package written for a renderer this
/// build does not have is refused by name rather than as bad JSON.
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
    /// What is supposed to draw the character.
    ///
    /// `sprites` is the only one this build has a renderer for -- see
    /// `AvatarLoaderError.unsupportedAvatarType`. The other two are kept
    /// because a package on somebody's disk may still declare them, and
    /// decoding one is what lets the loader say so.
    enum AvatarType: String, Codable {
        /// The 3D renderer, removed in the 2026-07-29 2D switch.
        case usdz
        /// Never built.
        case video
        /// One PNG per clip. The only kind that draws.
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
    /// 2026-07-29 2D switch: 0.0-1.0 multiplier for the procedural
    /// squash-and-stretch "bounce" motion pet-app applies on top of a static
    /// illustration (no animation frames to play). nil means pet-app's own
    /// default.
    let bounceIntensity: Double?
    let hitbox: Hitbox
    let clips: [String: ClipReference]
    /// Optional, same stem-dictionary shape as `clips`, keyed by emotion name
    /// (e.g. "happy"). Swapped to on a matching socket event; absent entirely
    /// is fine for a base-image-only avatar.
    let emotions: [String: ClipReference]?
    let sounds: [String: String]
    /// What this character says, keyed by the moment -- see AvatarLines for
    /// the names and for why only the pet's own speech can be replaced.
    /// Absent entirely is the ordinary case: the app's own wording is used
    /// for every line a package does not carry.
    let lines: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case bounceIntensity = "bounce_intensity"
        case name, type, scale, hitbox, clips, emotions, sounds, lines
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
        lines = try container.decodeIfPresent([String: String].self, forKey: .lines)
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
        sounds: [String: String],
        lines: [String: String]? = nil
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
        self.lines = lines
    }
}
