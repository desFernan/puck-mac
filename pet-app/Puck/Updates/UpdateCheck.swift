//
//  UpdateCheck.swift
//  Puck
//
//  Whether there is a newer Puck than this one, and how to tell.
//
//  The app is downloaded as a .dmg from GitHub Releases and dragged into
//  Applications, which means nothing ever tells you a new one exists. A pet
//  that has been running since March is a pet running March's bugs, and its
//  owner has no way of knowing.
//
//  Deliberately not an updater. Nothing here downloads, replaces or restarts
//  anything: the image is signed ad-hoc, so an app that swapped itself out
//  would be an app that installs an unverifiable binary over itself while the
//  user watches. It reads the releases index, compares two version numbers,
//  and offers a link. The dragging stays the user's.
//
//  Pure, and separate from the fetching, because the whole of what can go
//  wrong here is arithmetic: is 0.10.0 newer than 0.9.0 (yes), is a
//  pre-release an update (no), is the tag "v0.2.1" the same version as
//  "0.2.1" (yes).
//

import Foundation

/// A version as three numbers, which is all this compares.
///
/// `Comparable` by part rather than by string: "0.10.0" sorts *before*
/// "0.9.0" as text, so a string comparison stops offering updates exactly
/// when a project reaches its tenth minor release.
struct AppVersion: Comparable, Equatable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    /// Parses "1.2.3", "v1.2.3", "1.2" and "1".
    ///
    /// Anything after the numbers is dropped -- "1.2.3-beta.1" is the same
    /// version as "1.2.3" here, and whether a pre-release should be offered
    /// at all is `Release.isOfferable`'s business, not the number's.
    init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "v" || trimmed.first == "V" { trimmed.removeFirst() }
        let numbers = trimmed.prefix { $0.isNumber || $0 == "." }
        let parts = numbers.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard let first = parts.first, let major = first else { return nil }
        // A missing part is zero, not a refusal: "0.3" is a version somebody
        // will tag one day, and it means 0.3.0.
        self.major = major
        minor = parts.count > 1 ? (parts[1] ?? 0) : 0
        patch = parts.count > 2 ? (parts[2] ?? 0) : 0
    }

    /// This build's own version, from the bundle -- the same value
    /// `MARKETING_VERSION` sets in project.yml.
    static func current(bundle: Bundle = .main) -> AppVersion? {
        (bundle.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }
}

/// One published release, as much of it as this needs.
struct Release: Equatable {
    let version: AppVersion
    /// What to call it on screen -- the release's own name when it has one,
    /// and the version otherwise.
    let name: String
    /// The page to open. The release itself, not the .dmg: the download is
    /// one click further on, and a browser is a better place to receive a
    /// 76MB file than an app that cannot show progress.
    let url: URL

    /// Drafts and pre-releases are not offered. A draft is not published at
    /// all, and somebody running a stable build did not ask to be moved onto
    /// a beta by a notice they cannot decline.
    static func isOfferable(_ json: [String: Any]) -> Bool {
        (json["draft"] as? Bool) != true && (json["prerelease"] as? Bool) != true
    }

    /// The newest offerable release in a GitHub releases payload.
    ///
    /// Takes the list endpoint's array or the `/latest` endpoint's single
    /// object, because they differ only in the wrapping -- and takes the
    /// newest by *version* rather than by position, since "latest" is
    /// whatever was published last, which is not the same thing the week
    /// somebody patches an old branch.
    static func newest(in payload: Data) -> Release? {
        let json = try? JSONSerialization.jsonObject(with: payload)
        let entries: [[String: Any]]
        if let many = json as? [[String: Any]] {
            entries = many
        } else if let one = json as? [String: Any] {
            entries = [one]
        } else {
            return nil
        }
        return entries
            .filter(isOfferable)
            .compactMap(from)
            .max { $0.version < $1.version }
    }

    private static func from(_ json: [String: Any]) -> Release? {
        guard let tag = json["tag_name"] as? String,
              let version = AppVersion(tag),
              let link = json["html_url"] as? String,
              let url = URL(string: link)
        else { return nil }
        let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Release(
            version: version,
            name: (name?.isEmpty == false) ? name! : version.description,
            url: url
        )
    }
}

/// When to look, and what to make of what came back.
enum UpdateCheck {
    /// The releases of the repository this app is built from.
    static let releasesURL = URL(string: "https://api.github.com/repos/desFernan/puck-mac/releases?per_page=10")!
    /// Where somebody is sent when the check itself could not run.
    static let releasesPage = URL(string: "https://github.com/desFernan/puck-mac/releases")!

    /// A day. Releases are weeks apart and the answer is the same all day, so
    /// anything finer is asking GitHub a question nobody's answer changes.
    static let interval: TimeInterval = 24 * 60 * 60

    /// Whether to ask again.
    ///
    /// Never checked means yes -- the first launch after an install is when
    /// somebody most wants to know they are already behind, which happens
    /// whenever a link has been sitting in a chat for a month.
    static func isDue(lastCheckedAt: Date?, now: Date, interval: TimeInterval = interval) -> Bool {
        guard let lastCheckedAt else { return true }
        // A clock that went backwards -- a machine that woke in another
        // timezone, or a date somebody set by hand -- would otherwise put the
        // next check arbitrarily far into the future.
        guard lastCheckedAt <= now else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= interval
    }

    /// The release worth telling somebody about, out of everything that came
    /// back.
    ///
    /// Nil when the newest published release is this version or older, which
    /// is the ordinary answer and the one that must stay silent. Also nil for
    /// a version already turned down: saying it again every day is how a
    /// notice becomes something people learn to dismiss without reading.
    static func offer(
        payload: Data,
        current: AppVersion?,
        skipping skipped: String? = nil
    ) -> Release? {
        guard let current, let newest = Release.newest(in: payload), newest.version > current else { return nil }
        if let skipped, AppVersion(skipped) == newest.version { return nil }
        return newest
    }
}
