//
//  ScreenManager.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Tracks NSScreen list, responds to didChangeScreenParametersNotification
//

import AppKit

/// Keeps the current GlobalScreenSpace up to date as displays are
/// connected/disconnected/rearranged. Per GlobalScreenSpace.current()'s own
/// contract, a momentarily-empty screen list (e.g. mid-sleep) is ignored —
/// `current` keeps its last-known value rather than going stale/undefined.
/// `@MainActor`: NSScreen, and a notification delivered on `.main`. Every
/// caller -- the overlay controller, the app delegate, the frame loop -- is
/// already there.
@MainActor
final class ScreenManager {
    private(set) var current: GlobalScreenSpace
    nonisolated private let observer = NotificationTokens()

    /// Called with the new GlobalScreenSpace whenever the display
    /// configuration actually changes (not called for the initial value).
    var onChange: ((GlobalScreenSpace) -> Void)?

    init?() {
        guard let space = GlobalScreenSpace.current() else { return nil }
        current = space
    }

    func startObserving() {
        observer.observe(NSApplication.didChangeScreenParametersNotification, object: nil) { [weak self] _ in
            // `queue: .main` (NotificationTokens' default) is what makes this
            // true; a notification block cannot say so itself.
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Same as FocusModeObserver's: the notification centre keeps the block,
    /// so dropping this object is not the same as stopping it.
    deinit {
        stopObserving()
    }

    /// `nonisolated` so `deinit` may call it -- a deinit has no isolation
    /// whatever the type it belongs to.
    nonisolated func stopObserving() {
        observer.removeAll()
    }

    private func refresh() {
        guard let space = GlobalScreenSpace.current() else { return }
        current = space
        onChange?(space)
    }
}
