//
//  MusicApps.swift
//  Puck
//
//  Asking a music app what it is playing, and telling it what to do.
//
//  AppleScript, for the reason NowPlaying's header gives: the private
//  framework everything used to call for this stopped answering third parties
//  on macOS 26. The scripts are here rather than spread through the view so
//  there is one place that knows Music's vocabulary differs from Spotify's --
//  positions in seconds against milliseconds, `player position` against
//  `player position`, and the same idea spelled two ways.
//
//  Nothing here runs on the main thread's critical path: `read` is called on
//  a timer while the panel is open and takes a few milliseconds, which is
//  several frames if it were run inline.
//

import AppKit
import Foundation

enum MusicApps {
    /// The apps that are running, in the order they should be asked.
    ///
    /// Running, not installed: launching somebody's music player because a
    /// panel opened would be a rude way to find out nothing is playing.
    static func runningSources() -> [NowPlaying.Source] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return NowPlaying.Source.musicApps.filter { source in
            source.bundleIdentifier.map(running.contains) ?? false
        }
    }

    /// The first running app that says it is playing something, or the first
    /// that answers at all.
    ///
    /// Playing beats paused: with Music paused in the background and Spotify
    /// playing, the one making noise is the one the panel is about.
    static func read() -> NowPlaying? {
        var firstAnswer: NowPlaying?
        for source in runningSources() {
            guard let track = read(from: source) else { continue }
            if track.isPlaying { return track }
            if firstAnswer == nil { firstAnswer = track }
        }
        return firstAnswer
    }

    static func read(from source: NowPlaying.Source) -> NowPlaying? {
        guard let raw = run(script(for: source)) else { return nil }
        return parse(raw, source: source)
    }

    // MARK: - Transport

    enum Command: String {
        case playPause = "playpause"
        case next = "next track"
        case previous = "previous track"

        /// The same instruction as a keystroke, for anything that cannot be
        /// told outright.
        var systemCommand: MediaRemoteReader.Command {
            switch self {
            case .playPause: return .playPause
            case .next: return .next
            case .previous: return .previous
            }
        }

        var mediaKey: MediaKeys.Key {
            switch self {
            case .playPause: return .playPause
            case .next: return .next
            case .previous: return .previous
            }
        }
    }

    static func send(_ command: Command, to source: NowPlaying.Source) {
        _ = run("tell application \"\(source.applicationName)\" to \(command.rawValue)")
    }

    // MARK: - The scripts

    /// One line per field, so the answer is split rather than parsed.
    ///
    /// A track with no artist or album is legal and common (a podcast, a
    /// voice memo), so every field is asked for defensively -- an error in
    /// the middle of the script would lose the fields after it as well.
    static func script(for source: NowPlaying.Source) -> String {
        // Spotify reports its position in seconds like Music does, but its
        // duration in milliseconds. Divided here so both arrive in seconds
        // and nothing downstream has to know which app answered.
        let duration = source == .spotify ? "((duration of t) / 1000)" : "(duration of t)"
        return """
        tell application "\(source.applicationName)"
            if it is not running then return ""
            try
                set t to current track
            on error
                return ""
            end try
            set out to ""
            try
                set out to out & (name of t)
            end try
            set out to out & linefeed
            try
                set out to out & (artist of t)
            end try
            set out to out & linefeed
            try
                set out to out & (album of t)
            end try
            set out to out & linefeed & (player state as text)
            set out to out & linefeed & (player position as text)
            set out to out & linefeed & (\(duration) as text)
            return out
        end tell
        """
    }

    /// Six lines: title, artist, album, state, position, duration.
    ///
    /// Returns nil for anything shorter rather than filling in blanks -- a
    /// half-read answer is a panel showing half a song.
    static func parse(_ raw: String, source: NowPlaying.Source) -> NowPlaying? {
        let lines = raw.components(separatedBy: "\n")
        guard lines.count >= 6 else { return nil }
        let title = lines[0].trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return NowPlaying(
            title: title,
            artist: lines[1].trimmingCharacters(in: .whitespaces),
            album: lines[2].trimmingCharacters(in: .whitespaces),
            // Music says "playing"/"paused"; Spotify says the same. Anything
            // else is a state nobody is listening to.
            isPlaying: lines[3].trimmingCharacters(in: .whitespaces).lowercased().contains("playing"),
            position: TimeInterval(lines[4].trimmingCharacters(in: .whitespaces)) ?? 0,
            duration: TimeInterval(lines[5].trimmingCharacters(in: .whitespaces)) ?? 0,
            source: source
        )
    }

    static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let value = NSAppleScript(source: source)?.executeAndReturnError(&error)
        // An error here is the ordinary case, not a fault: the app quit
        // mid-script, or Automation has not been granted. Either way there is
        // nothing playing as far as the panel is concerned.
        guard error == nil else { return nil }
        return value?.stringValue
    }
}

extension NowPlaying.Source {
    /// Nil for a browser, which is identified by prefix rather than by one
    /// identifier -- see `Browser.bundlePrefix`.
    var bundleIdentifier: String? {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        case .browser: return nil
        case .system(let identifier, _): return identifier
        }
    }
}

// MARK: - Artwork

extension MusicApps {
    /// Where Music is asked to put a cover.
    ///
    /// A file, because Music hands artwork over as raw image data and
    /// AppleScript's bridge turns anything that is not text into something
    /// lossy on the way back. Writing it and reading the bytes ourselves is
    /// the shortest path that keeps the image intact.
    ///
    /// A fresh name each time rather than one path reused: skipping through
    /// tracks starts a read before the last has finished, and two of them
    /// sharing a path means one reads the other's bytes and the panel shows
    /// the wrong cover.
    static func artworkFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("puck-artwork-\(UUID().uuidString)")
    }

    /// The cover, or nil -- which is ordinary. A podcast, a stream, or a
    /// track that simply has no art all land here.
    static func artwork(for source: NowPlaying.Source) -> Data? {
        switch source {
        // A tab title is all a browser gives up; there is no cover behind
        // it. The system route brings its own artwork with the track, so it
        // never reaches here either.
        case .browser, .system:
            return nil
        case .spotify:
            // Spotify keeps its covers on the web and hands out the address,
            // which is less work than moving the bytes through AppleScript.
            guard let raw = run(spotifyArtworkScript()),
                  let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.scheme == "https"
            else { return nil }
            return try? Data(contentsOf: url)
        case .music:
            let file = artworkFile()
            guard run(musicArtworkScript(writingTo: file)) != nil else {
                try? FileManager.default.removeItem(at: file)
                return nil
            }
            defer { try? FileManager.default.removeItem(at: file) }
            return try? Data(contentsOf: file)
        }
    }

    static func spotifyArtworkScript() -> String {
        """
        tell application "Spotify"
            if it is not running then return ""
            try
                return artwork url of current track
            on error
                return ""
            end try
        end tell
        """
    }

    static func musicArtworkScript(writingTo file: URL) -> String {
        """
        tell application "Music"
            if it is not running then return ""
            try
                set d to raw data of artwork 1 of current track
            on error
                return ""
            end try
        end tell
        set f to open for access POSIX file "\(file.path)" with write permission
        try
            set eof f to 0
            write d to f
        end try
        close access f
        return "ok"
        """
    }
}
