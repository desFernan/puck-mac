//
//  LyricsClient.swift
//  Puck
//
//  Where the words come from.
//
//  LRCLIB: a public lyrics index, no key, no account, and the one every
//  player of this kind uses. Two requests deep -- an exact lookup by artist,
//  title and length, and a search when that misses, which it does often. The
//  exact endpoint wants the recording's duration to match within a couple of
//  seconds, so a different master or a remaster answers 404 while the search
//  finds it.
//
//  A track with no lyrics is the ordinary case, not a failure. Plenty of
//  music is not in the index at all -- the first track tried while building
//  this was not -- and an instrumental never will be. The panel shows the
//  song either way.
//

import Foundation

struct LyricsClient {
    /// Injected so the tests answer without a network, and so a slow index
    /// cannot hold a panel open waiting.
    var data: (URL) async throws -> Data = { url in
        var request = URLRequest(url: url)
        // Short: this is decoration on a panel that is open while somebody
        // hovers, and words that arrive after they have looked away are
        // words nobody reads.
        request.timeoutInterval = 6
        // LRCLIB asks that clients identify themselves.
        request.setValue("Puck (https://github.com/desFernan/puck-mac)", forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: request).0
    }

    static let host = "https://lrclib.net"

    /// The synced lyrics for a track, or nil when the index has none.
    func lyrics(for track: NowPlaying) async -> SyncedLyrics? {
        if let exact = try? await lyrics(at: Self.exactURL(for: track)), !exact.isEmpty {
            return exact
        }
        // The exact endpoint matches on duration, so a remaster or a
        // different master answers 404 for a song the index certainly has.
        guard let searchURL = Self.searchURL(for: track) else { return nil }
        return try? await lyrics(at: searchURL)
    }

    private func lyrics(at url: URL?) async throws -> SyncedLyrics? {
        guard let url else { return nil }
        let payload = try await data(url)
        guard let synced = Self.firstSyncedLyrics(in: payload) else { return nil }
        let parsed = SyncedLyrics.parse(synced)
        return parsed.isEmpty ? nil : parsed
    }

    /// The `syncedLyrics` of a single record, or of the first search result
    /// that has any.
    ///
    /// Both endpoints are handled here because they differ only in whether
    /// the answer is wrapped in an array, and a result with only plain
    /// lyrics is no use to a panel that shows one line at a time.
    static func firstSyncedLyrics(in payload: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: payload)
        if let one = json as? [String: Any] {
            return one["syncedLyrics"] as? String
        }
        if let many = json as? [[String: Any]] {
            return many.compactMap { $0["syncedLyrics"] as? String }.first { !$0.isEmpty }
        }
        return nil
    }

    static func exactURL(for track: NowPlaying) -> URL? {
        var components = URLComponents(string: "\(host)/api/get")
        components?.queryItems = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: track.title),
            // Rounded: the index stores whole seconds, and a fractional one
            // matches nothing.
            URLQueryItem(name: "duration", value: "\(Int(track.duration.rounded()))"),
        ]
        return components?.url
    }

    static func searchURL(for track: NowPlaying) -> URL? {
        var components = URLComponents(string: "\(host)/api/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        return components?.url
    }
}
