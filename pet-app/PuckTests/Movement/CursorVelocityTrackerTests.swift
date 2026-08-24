//
//  CursorVelocityTrackerTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The shared "how hard was that flick" measurement behind both the pet's
//  throw and the toy's, since the toy can be grabbed and thrown the same
//  way the pet can.
//

import XCTest
@testable import Puck

final class CursorVelocityTrackerTests: XCTestCase {
    private func swipe(_ tracker: inout CursorVelocityTracker, speed: CGFloat, seconds: TimeInterval, dt: TimeInterval = 1.0 / 60) {
        var elapsed: TimeInterval = 0
        var x: CGFloat = tracker.velocity == .zero ? 0 : 0
        while elapsed < seconds {
            x += speed * CGFloat(dt)
            tracker.track(to: CGPoint(x: x, y: 0), dt: dt)
            elapsed += dt
        }
    }

    func test_measuresASteadySwipesSpeed() {
        var tracker = CursorVelocityTracker()

        swipe(&tracker, speed: 800, seconds: 0.5)

        XCTAssertEqual(tracker.velocity.x, 800, accuracy: 20)
    }

    func test_startsAtZero() {
        XCTAssertEqual(CursorVelocityTracker().velocity, .zero)
    }

    /// One stalled frame mid-drag must not decide the throw -- that is the
    /// whole reason this is smoothed rather than a raw frame delta.
    func test_aSingleStalledFrameBarelyMovesTheAverage() {
        var tracker = CursorVelocityTracker()
        swipe(&tracker, speed: 800, seconds: 0.5)
        let before = tracker.velocity.x

        // Same position twice: the cursor didn't move this frame.
        tracker.track(to: CGPoint(x: 0, y: 0), dt: 0)

        XCTAssertEqual(tracker.velocity.x, before, "a zero-dt sample must be ignored entirely")
    }

    /// Holding still before letting go should drop the speed, so a
    /// deliberate placement isn't a throw.
    func test_holdingStillDecaysTowardZero() {
        var tracker = CursorVelocityTracker()
        swipe(&tracker, speed: 800, seconds: 0.5)

        let still = CGPoint(x: 1000, y: 0)
        for _ in 0..<60 {
            tracker.track(to: still, dt: 1.0 / 60)
        }

        XCTAssertEqual(tracker.velocity.x, 0, accuracy: 5)
    }

    /// Frame-rate independence: the same gesture at a different sampling rate
    /// has to measure the same speed.
    func test_theSameSwipeMeasuresTheSameAtAnySampleRate() {
        var fast = CursorVelocityTracker()
        var slow = CursorVelocityTracker()

        swipe(&fast, speed: 600, seconds: 0.5, dt: 1.0 / 120)
        swipe(&slow, speed: 600, seconds: 0.5, dt: 1.0 / 30)

        XCTAssertEqual(fast.velocity.x, slow.velocity.x, accuracy: 20)
    }

    func test_resetClearsTheHistory() {
        var tracker = CursorVelocityTracker()
        swipe(&tracker, speed: 800, seconds: 0.5)

        tracker.reset()

        XCTAssertEqual(tracker.velocity, .zero, "the previous throw's speed must not leak into the next grab")
    }
}
