//
//  FocusModeObserver.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Detects macOS Focus (Do Not Disturb) -> optional auto-mute
//
//  macOS has no public, documented API for third-party apps to query Focus
//  status. This listens for the long-observed (but unofficial, undocumented,
//  version-dependent) distributed notification some menu-bar utilities rely
//  on for the older Do Not Disturb feature; there is no reliable way to
//  query the *current* status at startup, so `isFocusActive` starts at
//  false and only updates from notifications seen after `startObserving()`.
//  Whether this notification still fires at all after macOS 12's Focus
//  overhaul hasn't been verified against a real device with Focus toggled —
//  that verification needs a human actually testing it. This is exactly why
//  F5's spec calls auto-mute-on-Focus an *option*, not a requirement; it
//  defaults to off and should stay off until someone confirms detection
//  actually works on the target macOS version.

import Foundation

/// `@MainActor`: a distributed notification observed on `.main`, read by the
/// app delegate and the frame loop, which are both there already.
@MainActor
final class FocusModeObserver {
    static let distributedNotificationName = Notification.Name("com.apple.notificationcenterui.dndStatusChanged")

    private(set) var isFocusActive = false
    /// Called with the new value whenever a status-change notification arrives.
    var onChange: ((Bool) -> Void)?

    /// DistributedNotificationCenter in the app; injectable so tests can
    /// exercise this wiring over a private, in-process NotificationCenter.
    /// The distributed centre is a cross-process daemon (distnoted) shared
    /// with the whole machine: delivery latency is unbounded, and the name
    /// above is one macOS itself posts, so a test that posts through it is
    /// racing both the daemon and anything else on the Mac that toggles
    /// Focus while it runs.
    /// Observed through this rather than through the centre directly, so the
    /// registration is dropped when this object is -- see NotificationTokens.
    /// Built from the injected centre, which is the whole point of injecting
    /// one: a test posts through its own rather than through distnoted.
    nonisolated private let observerToken: NotificationTokens

    init(center: NotificationCenter = DistributedNotificationCenter.default()) {
        observerToken = NotificationTokens(center: center)
    }

    func startObserving() {
        observerToken.observe(Self.distributedNotificationName, object: nil) { [weak self] notification in
            // `queue: .main` (NotificationTokens' default) is what makes this
            // true; a notification block cannot say so itself.
            // Nothing from the notification crosses: see handleNotification.
            MainActor.assumeIsolated { self?.handleNotification() }
        }
    }

    /// A block observer is kept by the notification centre, not by this
    /// object, so one that is simply dropped goes on being registered and
    /// firing into a closure whose `self` is gone. Same reason
    /// WindowListWatcher and ClickDetector stop themselves.
    deinit {
        stopObserving()
    }

    /// `nonisolated` so `deinit` may call it: a deinit has no isolation
    /// whatever the type it belongs to, and NotificationTokens has none of
    /// its own to conflict with.
    nonisolated func stopObserving() {
        observerToken.removeAll()
    }

    /// Takes no payload, on purpose: the legacy notification's userInfo
    /// doesn't reliably carry the new status across macOS versions, so this
    /// flips state on each notification rather than trusting an unstable
    /// shape -- and a Notification is not Sendable, so not needing it is also
    /// what keeps the hop to the main actor clean.
    private func handleNotification() {
        // A toggle, and it is a guess: the notification's payload does not
        // reliably carry the new status across macOS versions, and there is
        // no public API to read Focus back, so this counts changes from an
        // assumed-off baseline. Launching while Focus is already on therefore
        // starts inverted for that session. Its blast radius is bounded on
        // purpose -- the only consumer may add muting and never remove it
        // (see the auto-mute wiring in AppDelegate+OverlayAvatar) -- so the
        // worst case is a quiet pet rather than a noisy one during Focus.
        isFocusActive.toggle()
        onChange?(isFocusActive)
    }
}
