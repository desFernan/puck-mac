//
//  NowPlaying.swift
//  Puck
//
//  What is playing, as the notch panel needs it.
//
//  Read by asking the music app rather than the system.
//  `MediaRemote` -- the private framework every notch utility used to call
//  for this -- stopped answering third parties on recent macOS: on 26.5 the
//  call simply never returns. Automation is the supported way left, it needs
//  no entitlement Apple does not hand out, and it is what Reprise settled on
//  for the same reason. The cost is a permission prompt the first time, and
//  that only the apps we know how to ask are covered.
//

import Foundation

struct NowPlaying: Equatable {
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
    /// Seconds into the track, and its length. Both are needed to find a
    /// lyric: the position says which line, and the duration is part of how
    /// a lyric source is asked for the right recording.
    let position: TimeInterval
    let duration: TimeInterval

    /// Which app it came from, so the transport controls talk to the same
    /// one that answered.
    let source: Source

    enum Source: Equatable {
        case music
        case spotify
        /// Anything playing in a browser, found by catching it making a
        /// sound and reading its front tab. Only used when the system route
        /// is unavailable -- see NowPlayingReader.
        case browser(Browser)
        /// Whatever the system says is playing, whichever app that is.
        /// Carries the app so the panel can name it and the transport can
        /// reach it.
        case system(bundleIdentifier: String, name: String)

        /// The apps that can be asked outright what they are playing, in the
        /// order they should be asked. A browser is not among them -- it has
        /// to be caught making a sound first, which is a different question.
        static let musicApps: [Source] = [.music, .spotify]

        /// The app's name as AppleScript addresses it.
        var applicationName: String {
            switch self {
            case .music: return "Music"
            case .spotify: return "Spotify"
            case .browser(let browser): return browser.applicationName
            case .system(_, let name): return name
            }
        }

        /// Whether it can be asked for a playhead. A browser cannot, so the
        /// panel knows not to draw a progress bar it would have to invent.
        var reportsPosition: Bool {
            if case .browser = self { return false }
            return true
        }

        /// Whether the panel should say where this came from. Worth saying
        /// for anything but the two apps asked by name, because the whole
        /// point of the system route is that it could be anything.
        var isWorthNaming: Bool {
            switch self {
            case .music, .spotify: return false
            case .browser, .system: return true
            }
        }
    }

    /// How far through, 0 to 1. Zero-length rather than a divide by zero:
    /// a track that reports no duration is a live stream or a bad answer,
    /// and a progress bar for it should be empty rather than full.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// Whether this is the same recording as `other`, ignoring where the
    /// needle is.
    ///
    /// What decides whether the lyrics have to be fetched again. Comparing
    /// the whole value would refetch on every tick, since the position
    /// changes every time it is read.
    func isSameTrack(as other: NowPlaying?) -> Bool {
        guard let other else { return false }
        return title == other.title && artist == other.artist && album == other.album
    }
}
