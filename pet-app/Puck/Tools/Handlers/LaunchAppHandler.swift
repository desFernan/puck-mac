//
//  LaunchAppHandler.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  NSWorkspace.openApplication -> returns pid, triggers the pet's MoveTo
//
//  After a successful launch the pet walks over to greet the new window —
//  the M-1 milestone's visible half ("펫이 해당 창으로 이동"). Finding that
//  window means waiting for it to appear in F4's list, which is bootstrap
//  knowledge, so it is delegated through `onAppLaunched`.

import AppKit

/// The three things the front-most retry needs from a running app. A protocol
/// only so the retry can be tested -- NSRunningApplication can't be faked, and
/// an unbounded retry loop is exactly the kind of bug worth pinning down.
protocol ActivatableApp: AnyObject {
    var isTerminated: Bool { get }
    var isActive: Bool { get }
    func activateAllWindows()
}

extension NSRunningApplication: ActivatableApp {
    func activateAllWindows() {
        activate(options: [.activateAllWindows])
    }
}

/// args: `{"app_name": "Safari"}` or `{"bundle_id": "com.apple.Safari"}`.
final class LaunchAppHandler: ToolHandler {
    let toolName = "launch_app"

    /// Called with the pid of a successfully launched app. The tool_result is
    /// sent independently of this — the agent shouldn't wait on the pet's walk.
    var onAppLaunched: ((pid_t) -> Void)?

    /// Fired the instant a launch is asked for, *before* the app is opened, so
    /// the pet can be seen doing something first. Ordering is the whole trick: a
    /// window that appears before the pet moves reads as the app opening on
    /// its own, with the pet wandering over afterwards.
    var onLaunchRequested: (() -> Void)?

    /// Schedules the front-most retry. Injectable so the retry logic is
    /// testable without waiting on a real clock.
    var scheduleAfter: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// NSWorkspace has no modern by-display-name lookup, so this is still
    /// `fullPath(forApplication:)` -- deprecated, with no replacement that
    /// takes a name. One call, in one place, and the warning gate
    /// (scripts/check-warnings.sh) names this line as the one it allows.
    private static func applicationURL(named appName: String) -> URL? {
        NSWorkspace.shared.fullPath(forApplication: appName).map(URL.init(fileURLWithPath:))
    }

    func execute(id _: String, args: JSONValue, completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard case .object(let fields) = args else {
            completion(.failure(.executionFailed("launch_app requires an args object")))
            return
        }

        let appURL: URL?
        if case .string(let bundleID) = fields["bundle_id"] {
            appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        } else if case .string(let appName) = fields["app_name"] {
            appURL = Self.applicationURL(named: appName)
        } else {
            appURL = nil
        }

        guard let appURL else {
            completion(.failure(.executionFailed("could not resolve app_name/bundle_id")))
            return
        }

        // The pet reacts before the app is even asked to open -- openApplication
        // itself takes a beat, and that beat is what the gesture fills.
        onLaunchRequested?()

        let configuration = NSWorkspace.OpenConfiguration()
        // Deliberately NOT letting the workspace raise it. The app must end up
        // in front, but
        // *when* is the point: raising it here would put the window up before
        // the pet has visibly done anything. bringToFront owns the timing.
        configuration.activates = false

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
            if let app {
                completion(.success(.object(["pid": .number(Double(app.processIdentifier))])))
                self.onAppLaunched?(app.processIdentifier)
                self.bringToFront(app)
            } else {
                completion(.failure(.executionFailed(error?.localizedDescription ?? "launch failed")))
            }
        }
    }

    /// `configuration.activates` alone is not enough in the two cases that
    /// matter most here:
    ///
    /// - The app was **already running**, possibly hidden or with its windows
    ///   behind everything. openApplication resolves to it without necessarily
    ///   raising it.
    /// - The app is **launching cold**, so at the moment it activates it has no
    ///   windows to raise yet, and whatever the user was looking at stays on
    ///   top.
    ///
    /// So this retries until the app reports itself active. Fire and forget:
    /// the tool_result has already gone back to the agent, because waiting on
    /// a window server race would just make the tool look slow.
    ///
    /// The first attempt waits a beat longer than the rest -- long enough for
    /// the pet's gesture to have started, so the window arriving reads as its
    /// doing rather than as a coincidence.
    func bringToFront(_ app: ActivatableApp, attemptsRemaining: Int = 10) {
        guard attemptsRemaining > 0, !app.isTerminated, !app.isActive else { return }
        let isFirstAttempt = attemptsRemaining == 10
        scheduleAfter(isFirstAttempt ? Self.activationLeadIn : Self.activationRetryInterval) { [weak self] in
            guard let self, !app.isTerminated else { return }
            app.activateAllWindows()
            self.bringToFront(app, attemptsRemaining: attemptsRemaining - 1)
        }
    }

    /// How long the pet gets on its own before the window comes up. Tuned by
    /// eye: below ~0.25s the two read as simultaneous and the causality is
    /// lost; past ~0.6s the app just feels slow to open.
    static let activationLeadIn: TimeInterval = 0.4

    /// 0.2s x 10 covers a cold launch of a heavy app without holding the pet's
    /// main queue busy for anything a user would notice.
    static let activationRetryInterval: TimeInterval = 0.2
}
