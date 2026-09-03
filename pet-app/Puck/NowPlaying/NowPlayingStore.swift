//
//  NowPlayingStore.swift
//  Puck
//
//  Keeps the panel's idea of what is playing up to date, and its lyrics with
//  it.
//
//  Polled rather than subscribed, because Automation offers nothing to
//  subscribe to -- and only while the panel is open, since a music app asked
//  for its state every second forever is a cost nobody agreed to for a panel
//  nobody is looking at.
//
//  `@MainActor`: it publishes to a SwiftUI view. The reading happens off it.
//

import AppKit
import Foundation
import SwiftUI

@MainActor
final class NowPlayingStore: ObservableObject {
    @Published private(set) var track: NowPlaying?
    @Published private(set) var lyrics: SyncedLyrics?
    @Published private(set) var artwork: NSImage?

    /// Injected so tests can answer without a music app or a network.
    /// Answers with the cover too when whatever answered had one, which the
    /// system route does: fetching it separately would be a second shell-out
    /// for a picture already in hand.
    var read: () -> (track: NowPlaying, artwork: Data?)? = { NowPlayingReader.read() }
    var fetchLyrics: (NowPlaying) async -> SyncedLyrics? = { await LyricsClient().lyrics(for: $0) }
    var fetchArtwork: (NowPlaying) -> NSImage? = { track in
        MusicApps.artwork(for: track.source).flatMap(NSImage.init(data:))
    }

    /// How often the player is asked, while the panel is open. A second is
    /// enough for a progress bar and a lyric line to look live.
    nonisolated static let interval: TimeInterval = 1

    /// And while it is shut. The shut notch shows a thumbnail and whether
    /// anything is playing -- neither of which changes between songs -- so
    /// asking every second for it would be paying an open panel's price all
    /// day for something nobody is reading.
    nonisolated static let idleInterval: TimeInterval = 4

    /// Which of the two is running, so a change of pace restarts the timer
    /// rather than being noticed on the next tick or not at all.
    private var currentInterval: TimeInterval?

    private var timer: Timer?
    private var lyricsTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    /// Which read is the current one.
    ///
    /// Reading happens off the main thread, so two of them can be in flight
    /// at once -- a tick and the panel opening, say -- and they do not
    /// necessarily come back in the order they went out. Without this, an
    /// older read landing second reinstalls the song before last, and the
    /// panel goes backwards.
    private var generation = 0

    /// The line being sung, if there are words and the song is playing.
    var currentLyric: String? {
        guard let track, let lyrics else { return nil }
        return lyrics.line(at: track.position)?.text
    }

    func start(every seconds: TimeInterval = NowPlayingStore.interval) {
        guard currentInterval != seconds else { return }
        self.timer?.invalidate()
        currentInterval = seconds
        refresh()
        let timer = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // `.common`, so the panel keeps counting while a menu is open or the
        // pointer is dragging something.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        currentInterval = nil
        lyricsTask?.cancel()
        lyricsTask = nil
        artworkTask?.cancel()
        artworkTask = nil
    }

    /// Tells whichever app answered to do something, then reads back sooner
    /// than the next tick so the button feels connected to the music.
    func send(_ command: MusicApps.Command) {
        guard let source = track?.source else { return }
        Task.detached(priority: .userInitiated) {
            switch source {
            case .system:
                // Whatever is playing, told through the same route it was
                // found on.
                MediaRemoteReader.send(command.systemCommand)
            case .browser:
                // A browser takes no orders, only keystrokes.
                MediaKeys.send(command.mediaKey)
            case .music, .spotify:
                MusicApps.send(command, to: source)
            }
            // Long enough for the app to have acted. Asking instantly gets
            // the state from before the button was pressed.
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run { self.refresh() }
        }
    }

    /// Reads once, now, rather than waiting for the next tick.
    ///
    /// Not private: the panel calls it the moment it opens, so the first
    /// thing shown is what is playing rather than a second of nothing.
    func refresh() {
        // Off the main thread: AppleScript takes a few milliseconds, which is
        // several frames of the pet if it were run inline.
        generation += 1
        let mine = generation
        let read = read
        Task.detached(priority: .utility) {
            let answer = read()
            await MainActor.run {
                guard mine == self.generation else { return }
                self.apply(answer?.track, cover: answer?.artwork)
            }
        }
    }

    private func apply(_ new: NowPlaying?, cover: Data?) {
        let changed = !(new?.isSameTrack(as: track) ?? (new == nil && track == nil))
        track = new
        guard changed else { return }
        // A new song, so the words and the cover that were up belong to the
        // old one.
        lyrics = nil
        artwork = nil
        lyricsTask?.cancel()
        artworkTask?.cancel()
        guard let new, !new.title.isEmpty else { return }
        // Already in hand, so there is nothing to go and fetch.
        if let cover, let image = NSImage(data: cover) {
            artwork = image
            return
        }
        artworkTask = Task { [fetchArtwork] in
            let image = await Task.detached(priority: .utility) { fetchArtwork(new) }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard new.isSameTrack(as: self.track) else { return }
                self.artwork = image
            }
        }
        lyricsTask = Task { [fetchLyrics] in
            let found = await fetchLyrics(new)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // Checked again on arrival: the song can change while the
                // index is being asked, and words from the previous one
                // appearing over the new one is worse than none.
                guard new.isSameTrack(as: self.track) else { return }
                self.lyrics = found
            }
        }
    }
}
