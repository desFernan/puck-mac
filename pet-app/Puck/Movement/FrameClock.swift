//
//  FrameClock.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Drives CharacterController.update(dt:) — the FSM's per-frame heartbeat.
//
//  Without this nothing calls update(dt:) at all, which silently disables
//  everything time-based: IdleState's WanderScheduler never fires (the pet
//  never wanders) and PointingController's 8s release never elapses (the pet
//  points forever unless the target happens to get clicked).
//

import Foundation

/// The pure dt-computation half: turns a monotonic clock reading into the
/// elapsed time since the previous frame. Kept separate from the Timer so the
/// interesting behavior (clamping, first frame, non-monotonic samples) is
/// testable without a run loop.
struct FrameTicker {
    /// Longest dt a single frame may report. A stalled run loop (modal
    /// tracking, a long synchronous load) otherwise hands the FSM one enormous
    /// step, teleporting a constant-velocity MoveTo and firing every timer at
    /// once. Discarded time is dropped, not carried over.
    let maxDelta: TimeInterval

    private var lastSample: TimeInterval?

    init(maxDelta: TimeInterval = 0.25) {
        self.maxDelta = maxDelta
    }

    /// Returns the clamped time since the previous sample, or nil when there
    /// is nothing to measure against (first frame, or time went backwards).
    mutating func delta(now: TimeInterval) -> TimeInterval? {
        defer { lastSample = now }
        guard let last = lastSample, now > last else { return nil }
        return min(now - last, maxDelta)
    }

    mutating func reset() {
        lastSample = nil
    }
}

/// Timer + FrameTicker. Thin by design — the logic lives in FrameTicker.
/// `@MainActor`: it drives the frame loop, and everything the frame loop
/// touches is AppKit.
@MainActor
final class FrameClock {
    /// The 2D renderer needs a continuous heartbeat for movement, toy physics,
    /// and time-based behaviors, but it does not need the old 60 Hz 3D loop.
    /// Active work is capped at 30 Hz and long idle periods run at 15 Hz.
    nonisolated static let activeFramesPerSecond: Double = 30
    nonisolated static let idleFramesPerSecond: Double = 15

    var onTick: ((TimeInterval) -> Void)?

    private var timer: Timer?
    private var ticker = FrameTicker()
    private let now: () -> TimeInterval
    private(set) var framesPerSecond: Double

    init(
        framesPerSecond: Double = FrameClock.activeFramesPerSecond,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.framesPerSecond = framesPerSecond
        self.now = now
    }

    func start() {
        ticker.reset()
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Changing the rate restarts the timer but keeps the ticker running, so
    /// the frame spanning the change reports its real elapsed time.
    func setFramesPerSecond(_ fps: Double) {
        guard fps > 0, fps != framesPerSecond else { return }
        framesPerSecond = fps
        if timer != nil {
            schedule()
        }
    }

    private func schedule() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / framesPerSecond, repeats: true) { [weak self] _ in
            // Added to RunLoop.main just below, which is what makes this
            // true; a Timer block cannot say so in its signature.
            MainActor.assumeIsolated {
                guard let self, let dt = self.ticker.delta(now: self.now()) else { return }
                self.onTick?(dt)
            }
        }
        // .common so the pet keeps animating while a menu is open or a window
        // is being resized — the same reason WindowListWatcher uses it.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
