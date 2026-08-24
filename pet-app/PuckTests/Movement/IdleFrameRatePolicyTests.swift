//
//  IdleFrameRatePolicyTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Locks the current 2D heartbeat budget: 30 Hz while active and 15 Hz after
//  sustained idle, with immediate restoration when activity resumes.
//

import XCTest
@testable import Puck

final class IdleFrameRatePolicyTests: XCTestCase {
    func test_defaultRatesStayInsideThe2DUpdateBudget() {
        XCTAssertEqual(FrameClock.activeFramesPerSecond, 30)
        XCTAssertEqual(FrameClock.idleFramesPerSecond, 15)
    }

    func test_runsAtFullRateWhileTheStateIsNotIdle() {
        var policy = IdleFrameRatePolicy()

        XCTAssertEqual(policy.framesPerSecond(idle: false, dt: 60), FrameClock.activeFramesPerSecond)
    }

    func test_staysAtFullRateUntilTheIdleThreshold() {
        var policy = IdleFrameRatePolicy(threshold: 30)

        _ = policy.framesPerSecond(idle: true, dt: 29)
        XCTAssertEqual(policy.framesPerSecond(idle: true, dt: 0.5), FrameClock.activeFramesPerSecond)
    }

    func test_downshiftsOncePastTheThreshold() {
        var policy = IdleFrameRatePolicy(threshold: 30)

        _ = policy.framesPerSecond(idle: true, dt: 29)
        XCTAssertEqual(policy.framesPerSecond(idle: true, dt: 2), FrameClock.idleFramesPerSecond)
    }

    /// The pet has to react immediately when something happens — coming back
    /// up to speed a second later would show as a visible stutter.
    func test_leavingIdleRestoresFullRateAtOnce() {
        var policy = IdleFrameRatePolicy(threshold: 30)
        _ = policy.framesPerSecond(idle: true, dt: 40)

        XCTAssertEqual(policy.framesPerSecond(idle: false, dt: 0.016), FrameClock.activeFramesPerSecond)
    }

    func test_idleTimerRestartsAfterActivity() {
        var policy = IdleFrameRatePolicy(threshold: 30)
        _ = policy.framesPerSecond(idle: true, dt: 40)
        _ = policy.framesPerSecond(idle: false, dt: 0.016)

        XCTAssertEqual(
            policy.framesPerSecond(idle: true, dt: 5),
            FrameClock.activeFramesPerSecond,
            "only 5s idle since the last activity"
        )
    }
}
