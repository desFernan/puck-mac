//
//  PendingPointTracker.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Tracks the single in-flight point_at request the pet is walking toward.
//
//  A point_at that arrives before a previous one has reached its target
//  redirects the walk (same as MoveTo's target being overwritten), but the
//  superseded request's caller was still waiting on its own onPointingStarted
//  callback -- silently dropping it left that tool_dispatch hanging until
//  ToolExecutor's 15s timeout instead of getting a reply. This class only
//  tracks state and reports what needs to happen; it has no side effects of
//  its own, so it's fully testable without RealityKit/AppKit.

import CoreGraphics
import Foundation

final class PendingPointTracker {
    private var pending: (frame: CGRect, holdSeconds: TimeInterval?, onStarted: () -> Void)?

    /// Registers a new pending point_at, returning the previous one's
    /// callback (if any) so the caller can invoke it -- it was superseded,
    /// not failed, but still needs a reply.
    ///
    /// - Parameter holdSeconds: how long this request wants the pointing held
    ///   for, carried here rather than on the delegate so a request that is
    ///   superseded mid-walk takes its own hold with it.
    func replace(frame: CGRect, holdSeconds: TimeInterval? = nil, onStarted: @escaping () -> Void) -> (() -> Void)? {
        let superseded = pending?.onStarted
        pending = (frame, holdSeconds, onStarted)
        return superseded
    }

    /// Called once Point actually starts. Returns the pending frame/callback
    /// and clears state, or nil if nothing is pending.
    func consumeIfPending() -> (frame: CGRect, holdSeconds: TimeInterval?, onStarted: () -> Void)? {
        defer { pending = nil }
        return pending
    }

    /// Called on tool_cancel/timeout. Unlike `replace`'s "superseded" case,
    /// this must NOT invoke the pending callback: ToolExecutor already
    /// replied .cancelled for this dispatch, so calling onStarted after would
    /// be stale, not a legitimate reply.
    func clearPending() {
        pending = nil
    }
}
