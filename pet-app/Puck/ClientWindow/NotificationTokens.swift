//
//  NotificationTokens.swift
//  Puck
//
//  Notification observers that unregister themselves when they are dropped.
//
//  The reason this exists rather than each owner keeping its own array: the
//  owners here are main-actor views and coordinators, and `deinit` is
//  nonisolated whatever the type it belongs to. Reaching the view's own
//  observers from there is something the compiler objects to and Swift 6
//  refuses outright -- a real rule, not a formality, since a deinit can run
//  on whichever thread released the last reference.
//
//  A plain object held by the view sidesteps it honestly: nothing about it is
//  isolated, it is released exactly when the view is, and its own deinit is
//  free to do the unregistering.
//

import Foundation

/// `Sendable` for real rather than by assertion: the array is only ever
/// touched under `lock`. That matters because the owners are main-actor
/// types whose `deinit` is not, so the last release can come from anywhere.
final class NotificationTokens: @unchecked Sendable {
    private let center: NotificationCenter
    private let lock = NSLock()
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter = .default) {
        self.center = center
    }

    /// Starts one observation and keeps its token. `queue` is the caller's
    /// choice for the same reason it always was -- a block delivered on
    /// `.main` is what lets these callers touch main-actor state.
    func observe(
        _ name: Notification.Name,
        object: Any?,
        queue: OperationQueue? = .main,
        using block: @escaping @Sendable (Notification) -> Void
    ) {
        let token = center.addObserver(forName: name, object: object, queue: queue, using: block)
        lock.lock()
        tokens.append(token)
        lock.unlock()
    }

    /// Stops everything observed so far. Called when the thing being watched
    /// is replaced -- a view moving to a different window -- rather than only
    /// at the end.
    func removeAll() {
        // Unregistered outside the lock: removeObserver goes into the
        // notification centre, and holding a lock across a call into
        // somebody else's code is how deadlocks are made.
        lock.lock()
        let taken = tokens
        tokens = []
        lock.unlock()
        taken.forEach(center.removeObserver)
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return tokens.isEmpty
    }

    deinit {
        tokens.forEach(center.removeObserver)
    }
}
