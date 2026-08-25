//
//  ClientStatusBarView.swift
//  Puck
//
//  Design system v2 (2026-08-14) -- a persistent thin status bar, new UI
//  Reports the active workspace's *editor/project*
//  status -- deliberately not called "connection", since that term means
//  the pet-app<->workspace bridge socket elsewhere in this codebase and
//  this bar doesn't observe that.
//

import SwiftUI

/// Pure mapping, hoisted out of the view body so it's testable without
/// hosting a SwiftUI view.
func dotStatus(for availability: EditorAvailability) -> DotStatus {
    switch availability {
    case .noProject: return .idle
    case .ready: return .success
    case .unavailable: return .error
    }
}

/// The same three states in words. The dot is a colour and nothing else, so
/// this is the whole of what a screen reader can be told about it -- and
/// `.unavailable` in particular is a failure that otherwise has no voice.
func dotDescription(for availability: EditorAvailability) -> String {
    switch availability {
    case .noProject: return Strings.text(.a11yProjectNone)
    case .ready: return Strings.text(.a11yProjectReady)
    case .unavailable: return Strings.text(.a11yProjectUnavailable)
    }
}

/// `/Users/x/dev/p` -> `~/dev/p`. Only at a path boundary, so `/Users/xyz`
/// isn't mangled by a home of `/Users/x`.
func abbreviatedPath(_ path: String, home: String) -> String {
    if path == home { return "~" }
    guard path.hasPrefix(home + "/") else { return path }
    return "~" + path.dropFirst(home.count)
}

struct ClientStatusBarView: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    let workspace: ClientWorkspace?
    let availability: EditorAvailability
    let palette: ClientPalette
    /// What the project's repository is doing: the branch, and how much has
    /// changed on it. nil when there is no project, or it is not a repository
    /// -- in which case the footer says nothing rather than saying "none".
    var git: GitStatus?

    /// Loaded fresh rather than threaded in from a store: this is the same
    /// config AgentSettingsView reads directly (AgentConfiguration.load()),
    /// and the model name changing means either a rebuild or an .env edit --
    /// neither of which this view needs to observe live.
    private var model: String {
        let configuration = AgentConfiguration.load()
        // The CLI provider has no model of ours to name -- ACP carries no
        // model field -- so `model` is empty there and the row showed an icon
        // with nothing beside it. What is actually running is the CLI.
        guard configuration.model.isEmpty else { return configuration.model }
        return configuration.codingAgent.displayName
    }

    // Matches ClientWindowStore.casualSessionTitle -- the default
    // workspace's own name, not an English placeholder. Every string beside
    // it on screen is Korean, so an English one would read as a gap.
    private var projectLabel: String {
        guard let projectPath = workspace?.projectPath else { return workspace?.displayName ?? Strings.text(.chatCasualSession) }
        return abbreviatedPath(projectPath, home: NSHomeDirectory())
    }

    var body: some View {
        HStack(spacing: ClientTheme.Metrics.spacingMedium) {
            HStack(spacing: ClientTheme.Metrics.spacingSmall) {
                StatusDotView(
                    status: dotStatus(for: availability),
                    palette: palette,
                    label: dotDescription(for: availability)
                )
                Text(projectLabel)
            }
            if let branch = git?.branch {
                separator
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                        .accessibilityHidden(true)
                    Text(branch)
                    // Only when there is something to say. A footer that
                    // reads "0 changed, 0 ahead" on every clean repository is
                    // a footer people stop reading.
                    if let summary = changeSummary {
                        Text(summary)
                            .foregroundStyle(palette.textSecondary.opacity(0.7))
                    }
                }
            }
            separator
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 9))
                    .accessibilityHidden(true)
                Text(model)
            }
            Spacer(minLength: ClientTheme.Metrics.spacingMedium)
            // Trailing, the way a status bar puts what is true of the app
            // rather than of the file: this side is the same whichever
            // workspace is open.
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 9))
                    .accessibilityHidden(true)
                Text(Localization.shared.language.rawValue.uppercased())
            }
        }
        .font(ClientTheme.Typography.caption.monospacedDigit())
        .foregroundStyle(palette.textSecondary)
        .lineLimit(1)
        .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
        .frame(height: 28)
        // The window's own ground rather than a raised surface: a footer that
        // is lighter than everything above it reads as a drawer stuck to the
        // bottom. The hairline is what separates it.
        .background(palette.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.surfaceBorder.opacity(0.6))
                .frame(height: 1)
        }
    }

    /// "3 files +40 -12", or nothing at all on a clean tree. Written as
    /// git's own shorthand rather than a sentence: this is a status bar, and
    /// the people reading it read diffs.
    private var changeSummary: String? {
        guard let git, !git.files.isEmpty else { return nil }
        var parts = ["\(git.files.count)"]
        if git.addedLines > 0 { parts.append("+\(git.addedLines)") }
        if git.deletedLines > 0 { parts.append("-\(git.deletedLines)") }
        if git.ahead > 0 { parts.append("↑\(git.ahead)") }
        if git.behind > 0 { parts.append("↓\(git.behind)") }
        return parts.joined(separator: " ")
    }

    /// A dot rather than a rule. At 24pt the old 1x10 bar was a third of the
    /// row's height and read as a divider between two halves; this reads as
    /// punctuation between two facts.
    private var separator: some View {
        Circle()
            .fill(palette.textSecondary.opacity(0.35))
            .frame(width: 2, height: 2)
    }
}
