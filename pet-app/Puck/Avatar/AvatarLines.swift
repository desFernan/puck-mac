//
//  AvatarLines.swift
//  Puck
//
//  What this particular character says.
//
//  An avatar package can already change how the pet looks and sounds -- one
//  drawing per state, sixteen faces, a sound per event. What it could not
//  change is the one thing that is most obviously a personality: the words.
//  Every line the pet speaks is in `Strings`, so every character ever
//  installed sulked about being muted in exactly the same sentence.
//
//  Only the pet's *own* speech. Not the settings window, not an error, not
//  anything the app says as itself -- a package that could rewrite "권한이
//  없습니다" could lie to the person who installed it about what the app is
//  doing. What is here is the handful of lines the character says out loud,
//  and the fallback is the app's own for every one it does not carry.
//
//  Read from the manifest at load and held, rather than read per line: the
//  pet speaks from a frame callback and a mute toggle, and neither is a place
//  to open a file.
//

import Foundation

/// The lines a package may replace, named so a manifest can list them.
///
/// A closed set rather than "any key": these are the moments the app knows
/// how to produce, and a package listing something else has misunderstood
/// rather than extended it. Spelled in the manifest exactly as written here.
enum AvatarLine: String, CaseIterable {
    /// Muted from the menu bar, and the pet is not pleased.
    case muted
    /// A tool needs a permission the app does not have, and the pet is about
    /// to point at the dialog.
    case permissionNeeded
    /// Push-to-talk was held with no speech-recognition permission.
    case voicePermissionNeeded
    /// The chat window is not running, so what was typed has nowhere to go.
    case clientOffline
    /// A run finished while the window was behind something else. Takes the
    /// run's own summary as `%1$@` -- a package that wants to say nothing
    /// about the result can leave the placeholder out.
    case runFinished
    /// A run stopped for an approval, said with the request as `%1$@`.
    case approvalNeeded

    /// The app's own wording, used for every line a package does not carry.
    var fallback: String {
        switch self {
        case .muted: return Strings.text(.bubbleMutedComplaint)
        case .permissionNeeded: return Strings.text(.permissionNeededBubble)
        case .voicePermissionNeeded: return Strings.text(.voicePermissionNeeded)
        case .clientOffline: return Strings.text(.bubbleClientOffline)
        // These two are the summary itself today. A package that wants to
        // wrap it -- "다 했어요! %1$@" -- can; one that does not gets what the
        // pet already said.
        case .runFinished, .approvalNeeded: return "%1$@"
        }
    }
}

/// One package's lines.
struct AvatarLines: Equatable {
    private let lines: [String: String]

    init(_ lines: [String: String] = [:]) {
        self.lines = lines
    }

    /// The app's own wording throughout. What is used until a package is
    /// loaded, and for a package that carries none.
    static let none = AvatarLines()

    /// What to say, with `arguments` substituted for `%1$@` and so on.
    ///
    /// A package's line is used only when it is present and not blank: an
    /// empty string in a manifest is somebody clearing a field, not somebody
    /// asking the pet to say nothing -- and a pet with an empty bubble looks
    /// broken rather than quiet.
    func text(_ line: AvatarLine, _ arguments: String...) -> String {
        let template = lines[line.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = (template?.isEmpty == false ? template! : line.fallback)
        guard !arguments.isEmpty else { return chosen }
        return String(format: chosen, arguments: arguments)
    }

    /// Reads the `lines` table out of a manifest, keeping only the names the
    /// app knows.
    ///
    /// An unknown name is dropped rather than refused: a package written for
    /// a later version of the app should still work in this one, and the
    /// alternative is an avatar that will not load because it knows a word
    /// this build does not.
    static func from(manifest lines: [String: String]?) -> AvatarLines {
        guard let lines else { return .none }
        let known = Set(AvatarLine.allCases.map(\.rawValue))
        return AvatarLines(lines.filter { known.contains($0.key) })
    }
}
