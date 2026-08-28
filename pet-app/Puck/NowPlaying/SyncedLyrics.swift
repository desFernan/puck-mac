//
//  SyncedLyrics.swift
//  Puck
//
//  Lyrics with a timestamp on every line, and which line is the current one.
//
//  LRC is the format every lyric source hands out: one line per line of the
//  song, each prefixed with the time it starts. Parsing it is fiddly in ways
//  worth pinning rather than trusting -- the timestamps come in two shapes,
//  a line can carry several of them (a chorus repeated at four points in the
//  song is written once), and the file is not reliably in order.
//
//  Pure, and the lookup runs on every frame the panel is open, so it is a
//  binary search rather than a scan.
//

import Foundation

struct SyncedLyrics: Equatable {
    struct Line: Equatable {
        /// Seconds from the start of the track.
        let time: TimeInterval
        let text: String
    }

    /// In time order, which is not the order they necessarily arrived in.
    let lines: [Line]

    var isEmpty: Bool { lines.isEmpty }

    /// The line being sung at `time`, or nil before the first one.
    ///
    /// The last line at or before the time, not the nearest: a line stays up
    /// until the next one starts, which is what makes the words on screen
    /// match the words being sung rather than flicking to the next line
    /// halfway through the current one.
    func line(at time: TimeInterval) -> Line? {
        guard !lines.isEmpty, time >= lines[0].time else { return nil }
        var low = 0
        var high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].time <= time { low = mid } else { high = mid - 1 }
        }
        return lines[low]
    }

    /// Parses an LRC file.
    ///
    /// Timestamps are `[mm:ss.xx]` or `[mm:ss]`, and a line may carry more
    /// than one -- a chorus sung four times is written once with four stamps.
    /// Lines with no timestamp are the file's metadata (`[ar:...]`,
    /// `[ti:...]`) and are dropped rather than shown, since a title card
    /// appearing mid-song reads as the wrong lyric.
    static func parse(_ lrc: String) -> SyncedLyrics {
        var parsed: [Line] = []
        for raw in lrc.split(separator: "\n", omittingEmptySubsequences: false) {
            var rest = Substring(raw)
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let seconds = self.seconds(fromTag: tag) { times.append(seconds) }
                rest = rest[rest.index(after: close)...]
            }
            guard !times.isEmpty else { continue }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times { parsed.append(Line(time: time, text: text)) }
        }
        // Sorted here rather than trusted: an LRC with several timestamps on
        // one line is already out of order by construction.
        return SyncedLyrics(lines: parsed.sorted { $0.time < $1.time })
    }

    /// `mm:ss`, `mm:ss.xx` or `mm:ss.xxx`. Anything else is metadata.
    private static func seconds(fromTag tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2,
              let minutes = Int(parts[0]),
              let seconds = Double(parts[1].replacingOccurrences(of: ",", with: "."))
        else {
            return nil
        }
        return TimeInterval(minutes) * 60 + seconds
    }
}
