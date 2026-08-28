//
//  TrackTime.swift
//  Puck
//
//  Seconds as a clock reads them.
//
//  Its own file rather than a formatter in the view because the awkward cases
//  -- a stream that reports no length, a position a music app briefly reports
//  as negative while it seeks -- are worth pinning down in tests rather than
//  discovering as "-1:-3" under the progress bar.
//

import Foundation

enum TrackTime {
    /// `m:ss`, or `h:mm:ss` once there is an hour to show.
    ///
    /// Anything below zero reads as zero: a music app can report a negative
    /// position for a frame while it seeks, and that is not worth showing.
    static func text(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
