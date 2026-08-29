//
//  MediaRemoteReader.swift
//  Puck
//
//  What the machine is playing, whatever is playing it.
//
//  macOS knows -- Control Centre shows it, for a browser tab as readily as
//  for Music -- but the framework that answers the question stopped answering
//  third parties in macOS 15.4. It does not fail either, it returns an empty
//  dictionary, which is why this is not simply "call MediaRemote".
//
//  The way through is a vendored adapter run inside `/usr/bin/perl`, whose
//  code signing identity is `com.apple.perl`, and processes signed as
//  `com.apple.*` may still ask. See Vendor/MediaRemoteAdapter/README.md.
//
//  Everything here shells out and blocks, so none of it belongs on the main
//  thread; NowPlayingStore already reads on a background task.
//

import AppKit
import Foundation

enum MediaRemoteReader {
    /// The vendored adapter, or nil if it is not in the bundle -- which is a
    /// state worth handling rather than crashing on, since the panel has a
    /// second way to find out what Music and Spotify are doing.
    static var adapter: (script: URL, framework: URL)? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let folder = resources.appendingPathComponent("MediaRemoteAdapter", isDirectory: true)
        let script = folder.appendingPathComponent("mediaremote-adapter.pl")
        let framework = folder.appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: framework.path)
        else { return nil }
        return (script, framework)
    }

    /// What is playing anywhere on the machine, or nil when the adapter is
    /// absent, the OS has closed the route, or nothing is playing.
    static func read() -> (track: NowPlaying, artwork: Data?)? {
        guard let output = run(["get"]), let payload = Payload(json: output) else { return nil }
        return payload.nowPlaying().map { ($0, payload.artwork) }
    }

    /// The commands the adapter takes, by the number it wants them as.
    enum Command: Int {
        case playPause = 2
        case next = 4
        case previous = 5
    }

    static func send(_ command: Command) {
        _ = run(["send", String(command.rawValue)])
    }

    private static func run(_ arguments: [String]) -> Data? {
        guard let adapter else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [adapter.script.path, adapter.framework.path] + arguments
        let out = Pipe()
        process.standardOutput = out
        // Swallowed: the adapter is chatty about a machine playing nothing,
        // and none of it is actionable.
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }

    /// The adapter's JSON, as much of it as the panel has a use for.
    struct Payload {
        let title: String
        let artist: String
        let album: String
        let playing: Bool
        /// Where the playhead was when the player last said anything about
        /// it -- which is not the same as where it is now. See `position`.
        let elapsed: TimeInterval
        /// When it said it. Nil for a player that reports no clock.
        let measuredAt: Date?
        let rate: Double
        let duration: TimeInterval
        let bundleIdentifier: String
        let artwork: Data?

        init?(json: Data) {
            guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
            else { return nil }
            title = root["title"] as? String ?? ""
            artist = root["artist"] as? String ?? ""
            album = root["album"] as? String ?? ""
            playing = root["playing"] as? Bool ?? false
            elapsed = root["elapsedTime"] as? Double ?? 0
            measuredAt = (root["timestamp"] as? String).flatMap(Self.date)
            rate = root["playbackRate"] as? Double ?? 1
            duration = root["duration"] as? Double ?? 0
            bundleIdentifier = root["bundleIdentifier"] as? String ?? ""
            artwork = (root["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }
        }

        /// Where the playhead actually is.
        ///
        /// A player reports its position once, when something changes, and
        /// then says nothing until something changes again -- a browser
        /// playing a video sends one message at the moment it starts and
        /// leaves `elapsedTime` at whatever it was. Asking again a minute
        /// later gets the same number and the same timestamp, which is why
        /// the progress bar sat still through a whole song.
        ///
        /// So the answer is the reported position plus however long ago it
        /// was reported, at whatever speed it is running. A paused player is
        /// already where it says it is.
        func position(now: Date = Date()) -> TimeInterval {
            guard playing, let measuredAt else { return max(0, elapsed) }
            let since = now.timeIntervalSince(measuredAt)
            // A clock that reads backwards is a machine whose time changed
            // under us, not a track playing in reverse.
            let advanced = elapsed + max(0, since) * rate
            // Never past the end: a stream that overruns its stated length
            // should sit at the end rather than draw a bar past full.
            guard duration > 0 else { return max(0, advanced) }
            return min(max(0, advanced), duration)
        }

        static func date(_ text: String) -> Date? {
            // Two formatters because the adapter sends whole seconds for some
            // players and fractional for others, and one parser rejects the
            // shape it was not built for.
            for options in [[ISO8601DateFormatter.Options.withInternetDateTime,
                             .withFractionalSeconds],
                            [.withInternetDateTime]] {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = ISO8601DateFormatter.Options(options)
                if let date = formatter.date(from: text) { return date }
            }
            return nil
        }

        func nowPlaying(now: Date = Date()) -> NowPlaying? {
            // A payload with no title is a player that is registered but idle
            // -- a browser tab that once played something, most often. There
            // is nothing to show for it.
            guard !title.isEmpty else { return nil }
            return NowPlaying(
                title: title,
                artist: artist,
                album: album,
                isPlaying: playing,
                position: position(now: now),
                duration: duration,
                source: .system(bundleIdentifier: bundleIdentifier, name: Self.appName(bundleIdentifier))
            )
        }

        /// The player's name as a person would say it, falling back to the
        /// last part of its identifier for something that is not installed
        /// under a name we can look up.
        static func appName(_ bundleIdentifier: String) -> String {
            guard !bundleIdentifier.isEmpty else { return "" }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: "")
            }
            return bundleIdentifier.components(separatedBy: ".").last ?? bundleIdentifier
        }
    }
}
