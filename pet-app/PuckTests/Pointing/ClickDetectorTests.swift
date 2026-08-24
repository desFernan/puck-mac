//
//  ClickDetectorTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Pure hit test: plan/02_pet-app.md F10 ("클릭 감지: 전역 클릭 모니터로 클릭
//  좌표의 대상 frame 포함 여부 확인").
//

import XCTest
import CoreGraphics
@testable import Puck

final class ClickDetectorTests: XCTestCase {
    private let targetFrame = CGRect(x: 100, y: 100, width: 50, height: 50)

    func test_clickInsideFrame_isDetected() {
        XCTAssertTrue(ClickDetector.isClick(at: CGPoint(x: 125, y: 125), insideTargetFrame: targetFrame))
    }

    func test_clickOutsideFrame_isNotDetected() {
        XCTAssertFalse(ClickDetector.isClick(at: CGPoint(x: 0, y: 0), insideTargetFrame: targetFrame))
    }
}

final class ClickDetectorCoordinateSpaceTests: XCTestCase {
    // targetFrame arrives from point_at/UIElementInspector in global Quartz
    // coordinates (top-left origin, Y-down) -- protocol section 4. A real
    // click comes back from NSEvent.mouseLocation in AppKit's global space
    // (bottom-left origin, Y-up). Both must be converted into the same space
    // before comparing, or genuine clicks on the target are missed.
    private let targetFrame = CGRect(x: 100, y: 100, width: 50, height: 50) // Quartz space
    private let primaryScreenHeight: CGFloat = 1000

    func test_aRealClickOnTheTarget_isDetected_despiteDifferingCoordinateSpaces() {
        // Quartz point (125, 125) -- inside targetFrame -- is the same screen
        // location as AppKit point (125, 1000 - 125) = (125, 875).
        let detector = ClickDetector(
            mouseLocationProvider: { CGPoint(x: 125, y: 875) },
            screenSpaceProvider: { GlobalScreenSpace(appKitFrames: [CGRect(x: 0, y: 0, width: 1000, height: self.primaryScreenHeight)]) }
        )
        var detected = false
        detector.onClickInsideTarget = { detected = true }
        detector.startMonitoring(targetFrame: targetFrame)

        detector.handleClick()

        XCTAssertTrue(detected)
    }

    func test_aRealClickAwayFromTheTarget_isNotDetected() {
        // AppKit (0, 1000) -> Quartz (0, 0) -- outside targetFrame.
        let detector = ClickDetector(
            mouseLocationProvider: { CGPoint(x: 0, y: 1000) },
            screenSpaceProvider: { GlobalScreenSpace(appKitFrames: [CGRect(x: 0, y: 0, width: 1000, height: self.primaryScreenHeight)]) }
        )
        var detected = false
        detector.onClickInsideTarget = { detected = true }
        detector.startMonitoring(targetFrame: targetFrame)

        detector.handleClick()

        XCTAssertFalse(detected)
    }
}
