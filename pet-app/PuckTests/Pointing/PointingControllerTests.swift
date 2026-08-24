//
//  PointingControllerTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Release-after-8s-or-on-click logic, per plan/02_pet-app.md F10 ("기본
//  8초 후 또는 대상 클릭 감지 시 해제"), tested against a fake
//  ClickDetectorProviding instead of a real global event monitor.
//

import XCTest
import CoreGraphics
@testable import Puck

private final class FakeClickDetector: ClickDetectorProviding {
    var onClickInsideTarget: (() -> Void)?
    private(set) var startedWithFrame: CGRect?
    private(set) var stopCallCount = 0

    func startMonitoring(targetFrame: CGRect) { startedWithFrame = targetFrame }
    func stopMonitoring() { stopCallCount += 1 }
}

final class PointingControllerTests: XCTestCase {
    func test_beginPointing_startsClickMonitoringAtTargetFrame() {
        let clickDetector = FakeClickDetector()
        let controller = PointingController(clickDetector: clickDetector)
        let frame = CGRect(x: 10, y: 20, width: 30, height: 40)

        controller.beginPointing(targetFrame: frame)

        XCTAssertEqual(clickDetector.startedWithFrame, frame)
    }

    func test_tick_underTimeout_doesNotRelease() {
        let clickDetector = FakeClickDetector()
        let controller = PointingController(clickDetector: clickDetector)
        var released = false
        controller.onPointingReleased = { released = true }

        controller.beginPointing(targetFrame: .zero, timeout: 8)
        controller.tick(dt: 7.9)

        XCTAssertFalse(released)
        XCTAssertEqual(clickDetector.stopCallCount, 0)
    }

    func test_tick_reachingTimeout_releases() {
        let clickDetector = FakeClickDetector()
        let controller = PointingController(clickDetector: clickDetector)
        var released = false
        controller.onPointingReleased = { released = true }

        controller.beginPointing(targetFrame: .zero, timeout: 8)
        controller.tick(dt: 8)

        XCTAssertTrue(released)
        XCTAssertEqual(clickDetector.stopCallCount, 1)
    }

    func test_clickDetected_releasesEarly_beforeTimeout() {
        let clickDetector = FakeClickDetector()
        let controller = PointingController(clickDetector: clickDetector)
        var released = false
        controller.onPointingReleased = { released = true }

        controller.beginPointing(targetFrame: .zero, timeout: 8)
        controller.tick(dt: 1)
        clickDetector.onClickInsideTarget?()

        XCTAssertTrue(released)
        XCTAssertEqual(clickDetector.stopCallCount, 1)
    }

    func test_afterRelease_furtherTicksDoNotReleaseAgain() {
        let clickDetector = FakeClickDetector()
        let controller = PointingController(clickDetector: clickDetector)
        var releaseCount = 0
        controller.onPointingReleased = { releaseCount += 1 }

        controller.beginPointing(targetFrame: .zero, timeout: 8)
        controller.tick(dt: 8)
        controller.tick(dt: 100)

        XCTAssertEqual(releaseCount, 1)
        XCTAssertEqual(clickDetector.stopCallCount, 1)
    }

    /// A tour holds for a long time on purpose, so the run ending has to let
    /// go -- otherwise the pet stands pointing at code nobody is discussing.
    func test_releaseIfActive_stopsAnActiveHoldEarly() {
        let clickDetector = FakeClickDetector()
        let controller = PointingController(clickDetector: clickDetector)
        var released = false
        controller.onPointingReleased = { released = true }

        controller.beginPointing(targetFrame: .zero, timeout: 60)
        controller.releaseIfActive()

        XCTAssertTrue(released)
        XCTAssertEqual(clickDetector.stopCallCount, 1)
    }

    /// agent_done arrives whether or not the run pointed at anything, so the
    /// caller must not have to check first.
    func test_releaseIfActive_whenNothingIsPointing_isANoOp() {
        let clickDetector = FakeClickDetector()
        let controller = PointingController(clickDetector: clickDetector)
        var releaseCount = 0
        controller.onPointingReleased = { releaseCount += 1 }

        controller.releaseIfActive()

        XCTAssertEqual(releaseCount, 0)
        XCTAssertEqual(clickDetector.stopCallCount, 0)
    }
}
