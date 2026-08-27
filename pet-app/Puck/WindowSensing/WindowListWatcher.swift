//
//  WindowListWatcher.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  CGWindowListCopyWindowInfo polling (10/15Hz) + NSWorkspace notification handling
//

import AppKit
import CoreGraphics

/// Polls the on-screen window list and keeps `windows` (front-to-back Z order,
/// already filtered to layer-0 app windows) up to date. How often it asks is
/// WindowPollPolicy's decision, driven by `isPetActive`; an NSWorkspace
/// app-activate/launch/terminate notification triggers an immediate refresh
/// plus `burstDuration` seconds at the burst rate.
/// `@MainActor`: a Timer on the main run loop plus NSWorkspace
/// notifications delivered on `.main`, read every frame by the character
/// controller -- which runs on the main thread because it moves an NSWindow.
@MainActor
final class WindowListWatcher {
    static let burstDuration: TimeInterval = 3

    /// Whether the pet is doing something that reads the window list. Set by
    /// the frame loop; false means it is sitting still, which is when asking
    /// the system for every window on screen ten times a second stops paying
    /// for itself -- see WindowPollPolicy.
    var isPetActive = true

    private var pollPolicy = WindowPollPolicy()
    /// What the timer is currently set to, so a rate that has not changed
    /// does not tear the timer down and build it again every tick.
    private var currentHz: Double?

    private(set) var windows: [WindowInfo] = []

    private let selfPID: pid_t
    private let minimumSize: CGSize
    /// `nonisolated(unsafe)` so `stop()` can be called from `deinit`, which
    /// is nonisolated whatever this class is. Written and read on the main
    /// thread everywhere else; a timer left running past its owner is the
    /// failure this deinit exists to prevent, and it is worse than the one
    /// the annotation gives up.
    nonisolated(unsafe) private var pollTimer: Timer?
    /// Monotonic (ProcessInfo.systemUptime), not Date() — a wall-clock jump from
    /// NTP sync or waking from sleep must not affect when the burst window ends.
    private var burstEndUptime: TimeInterval?
    /// The workspace centre, not the default one: app activate/launch/quit
    /// are posted there and nowhere else.
    nonisolated private let observerTokens = NotificationTokens(center: NSWorkspace.shared.notificationCenter)

    init(
        selfPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        minimumSize: CGSize = CGSize(width: 40, height: 40)
    ) {
        self.selfPID = selfPID
        self.minimumSize = minimumSize
    }

    func start() {
        refresh()
        scheduleTimer(hz: WindowPollPolicy.activeHz)

        let names: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            observerTokens.observe(name, object: nil) { [weak self] _ in
                // `queue: .main` (NotificationTokens' default) is what makes
                // this true; a notification block cannot say so itself.
                MainActor.assumeIsolated { self?.triggerBurst() }
            }
        }
    }

    /// A watcher that is simply dropped leaves its timer on the run loop and
    /// its observers on the workspace centre -- both of which the run loop
    /// and the centre keep alive, so "nobody refers to it any more" is not
    /// the same as "it stopped".
    deinit {
        stop()
    }

    /// `nonisolated` so `deinit` may call it -- see `pollTimer`. Everything
    /// it touches either has no isolation of its own (the tokens) or is the
    /// timer this class alone owns.
    nonisolated func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        observerTokens.removeAll()
    }

    private func triggerBurst() {
        burstEndUptime = ProcessInfo.processInfo.systemUptime + Self.burstDuration
        scheduleTimer(hz: WindowPollPolicy.burstHz)
        refresh()
    }

    private func scheduleTimer(hz: Double) {
        guard hz != currentHz else { return }
        currentHz = hz
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / hz, repeats: true) { [weak self] _ in
            // Added to RunLoop.main just below, which is what makes this
            // true; a Timer block cannot say so in its signature.
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common (not the default add(timer:forMode:) mode) so polling doesn't
        // pause while the user has a menu open or a modal/tracking loop is active.
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func tick() {
        refresh()
        let now = ProcessInfo.processInfo.systemUptime
        if let end = burstEndUptime, now >= end {
            burstEndUptime = nil
        }
        // Rescheduled from the tick rather than from the frame loop: the
        // interval this decides is this timer's own, so the only moment it
        // can change without a wasted poll is when one has just happened.
        // `dt` is the interval that actually elapsed, which is the rate that
        // was in force -- not the one about to be.
        scheduleTimer(hz: pollPolicy.hertz(
            resting: !isPetActive,
            bursting: burstEndUptime != nil,
            dt: 1.0 / (currentHz ?? WindowPollPolicy.activeHz)
        ))
    }

    /// The list as of right now, for a caller that cannot wait for the next
    /// tick.
    ///
    /// The poll rate drops while the pet rests, which is fine for the pet --
    /// it is not reading the list -- and not fine for a tool asked "which
    /// window is frontmost" at that moment. Activating a window posts a
    /// notification and bursts, so the common case is already covered; this
    /// is for the rest.
    @discardableResult
    func windowsNow() -> [WindowInfo] {
        refresh()
        return windows
    }

    private func refresh() {
        windows = Self.filter(Self.fetchRawWindowList(), excludingPID: selfPID, minimumSize: minimumSize)
    }

    /// Pure filtering step, independently testable from the live window list:
    /// keeps only normal app windows (layer 0), excludes this process's own
    /// windows, and drops anything smaller than `minimumSize`. Z-order
    /// (input array order) is preserved.
    nonisolated static func filter(_ windows: [WindowInfo], excludingPID selfPID: pid_t, minimumSize: CGSize) -> [WindowInfo] {
        windows.filter { window in
            window.layer == 0
                && window.ownerPID != selfPID
                && window.frame.width >= minimumSize.width
                && window.frame.height >= minimumSize.height
        }
    }

    /// Live CGWindowListCopyWindowInfo fetch, parsed into WindowInfo, already in
    /// front-to-back Z order. Not unit tested — it depends on real on-screen
    /// windows; keep this a thin, trusted parsing layer and put logic in `filter`.
    nonisolated private static func fetchRawWindowList() -> [WindowInfo] {
        guard
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: AnyObject]]
        else {
            return []
        }

        return list.compactMap { entry in
            guard
                let windowID = entry[kCGWindowNumber as String] as? CGWindowID,
                let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                let layer = entry[kCGWindowLayer as String] as? Int,
                let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else {
                return nil
            }

            return WindowInfo(
                windowID: windowID,
                ownerPID: ownerPID,
                ownerName: entry[kCGWindowOwnerName as String] as? String,
                title: entry[kCGWindowName as String] as? String,
                layer: layer,
                frame: frame
            )
        }
    }
}
