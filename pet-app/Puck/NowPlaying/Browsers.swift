//
//  Browsers.swift
//  Puck
//
//  Reading what a browser is playing, which it will not tell you.
//
//  A browser knows -- the page fills in the Media Session API and macOS shows
//  it in Control Centre -- but nothing third parties can call gets at it. The
//  system's own now-playing service needs an entitlement Apple does not hand
//  out, and running JavaScript in a tab over Apple Events needs the browser
//  launched with a flag nobody's browser is launched with.
//
//  So it is done the long way round: CoreAudio says which browser is making a
//  sound, and AppleScript reads that browser's front tab title. It is the
//  active tab rather than the audible one, because no browser exposes which
//  tab is audible; when somebody plays a video and then switches tabs the
//  title goes stale. That is worth it to have the thing appear at all, and it
//  is why a browser never claims a position or a duration -- what is known is
//  a name, not a playhead.
//

import Foundation

struct Browser: Equatable, Hashable {
    /// How AppleScript addresses it.
    let applicationName: String
    /// Matched by prefix, so a browser's renderer helper counts as the
    /// browser: they carry identifiers like `<parent>.helper.Renderer`, and
    /// which of the two CoreAudio reports varies.
    let bundlePrefix: String
    /// WebKit and Chromium spell the same question differently.
    let isWebKit: Bool

    static let all: [Browser] = [
        Browser(applicationName: "Safari", bundlePrefix: "com.apple.Safari", isWebKit: true),
        // Arc before Dia: both answer to `company.thebrowser.`, and Arc's
        // own identifier is the longer one, so the looser prefix must come
        // second or it swallows the more specific match.
        Browser(applicationName: "Arc", bundlePrefix: "company.thebrowser.Browser", isWebKit: false),
        Browser(applicationName: "Dia", bundlePrefix: "company.thebrowser.", isWebKit: false),
        Browser(applicationName: "Google Chrome", bundlePrefix: "com.google.Chrome", isWebKit: false),
        Browser(applicationName: "Brave Browser", bundlePrefix: "com.brave.Browser", isWebKit: false),
        Browser(applicationName: "Microsoft Edge", bundlePrefix: "com.microsoft.edgemac", isWebKit: false),
    ]

    /// The first browser that is currently making a sound.
    ///
    /// Narrowed to browsers that are actually running first, because the
    /// sound does not always come from the browser's own process and its
    /// helper's identifier is not always unique to it: Dia's renderer
    /// answers to `company.thebrowser.browser.helper`, which is also what
    /// Arc's would be. Matching on that alone picks whichever is listed
    /// first, and then asks an app that is not open what it is playing.
    ///
    /// Two of them installed, running, and sharing a helper identifier is
    /// still ambiguous, and the first listed wins. That is rare enough to
    /// live with, and the cost is a title from the wrong browser rather
    /// than nothing at all.
    static func makingSound(among bundles: Set<String>, running: Set<String>) -> Browser? {
        all
            .filter { browser in running.contains { browser.owns($0) } }
            .first { browser in bundles.contains { browser.owns($0) } }
    }

    /// Whether a process identifier belongs to this browser.
    ///
    /// Case-insensitive, because a browser does not spell its helpers the way
    /// it spells itself: Arc is `company.thebrowser.Browser` and its renderer
    /// is `company.thebrowser.browser.helper`, and a case-sensitive match
    /// puts the helper with whichever browser has the looser prefix.
    func owns(_ bundleIdentifier: String) -> Bool {
        bundleIdentifier.lowercased().hasPrefix(bundlePrefix.lowercased())
    }

    var titleScript: String {
        let tab = isWebKit
            ? "name of current tab of front window"
            : "title of active tab of front window"
        return """
        tell application "\(applicationName)"
            if it is not running then return ""
            try
                return \(tab)
            on error
                return ""
            end try
        end tell
        """
    }
}

enum BrowserTitle {
    /// The page title as something worth putting under an album cover.
    ///
    /// Browser tab titles carry a lot that is not the name of what is
    /// playing: an unread count the tab bar puts in front, and the site's own
    /// name after it. Both are stripped, and what is left is split on a dash
    /// when it looks like "artist - title", which is how most music pages
    /// write it.
    ///
    /// Returns nil when nothing is left worth showing, so an empty tab or a
    /// browser that answered with nothing does not put a blank line in the
    /// panel.
    static func parse(_ raw: String) -> (title: String, artist: String)? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // "(3) something" -- the unread or notification count a tab bar
        // prepends. Only when it really is digits in brackets at the front.
        if let match = text.range(of: "^\\([0-9]+\\)\\s*", options: .regularExpression) {
            text.removeSubrange(match)
        }

        for suffix in siteSuffixes where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
            break
        }
        // Dashes as well as spaces: stripping a site name off a title that
        // was only ever the site name leaves the separator behind, and a
        // panel showing "-" is worse than one showing nothing.
        text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-|·")))
        guard !text.isEmpty else { return nil }
        // The site's own front page, which is a tab somebody left open
        // rather than something playing.
        guard !siteNames.contains(text.lowercased()) else { return nil }

        // "Artist - Title", the way most music pages write it. Split on the
        // first dash only: titles have dashes in them too, and the artist is
        // the part in front.
        if let dash = text.range(of: " - ") {
            let artist = String(text[..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
            let title = String(text[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !artist.isEmpty, !title.isEmpty {
                return (title, artist)
            }
        }
        return (text, "")
    }

    /// What sites append to every page title. Longest first, so "- YouTube
    /// Music" is not left as " Music" by matching "- YouTube".
    /// The same sites on their own, for a tab that is only the site.
    private static let siteNames = Set(
        siteSuffixes.map {
            $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "-|"))).lowercased()
        }
    )

    private static let siteSuffixes = [
        " - YouTube Music",
        " | Spotify",
        " - YouTube",
        " | SoundCloud",
        " - SoundCloud",
        " | Apple Music",
        " - Twitch",
        " - Netflix",
        " - Vimeo",
    ]
}
