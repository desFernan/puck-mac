//
//  PetGestureRecognizerTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Turns raw mouse events over the character into the two gestures the
//  transition table cares about: "캐릭터 클릭 -> ReactClick" and "캐릭터
//  드래그/드롭 -> ReactDrag(커서 추종) -> Fall".
//

import XCTest
@testable import Puck

final class PetGestureRecognizerTests: XCTestCase {
    func test_pressAndReleaseInPlace_isATap() {
        var recognizer = PetGestureRecognizer()

        XCTAssertNil(recognizer.mouseDown(at: CGPoint(x: 100, y: 100)))
        XCTAssertEqual(recognizer.mouseUp(at: CGPoint(x: 100, y: 100)), .tapped)
    }

    /// A hand shifting a pixel or two while clicking is still a click, not a
    /// drag — otherwise the pet gets yanked on every tap.
    func test_tinyMovementWhileClicking_isStillATap() {
        var recognizer = PetGestureRecognizer()

        _ = recognizer.mouseDown(at: CGPoint(x: 100, y: 100))
        XCTAssertNil(recognizer.mouseDragged(to: CGPoint(x: 102, y: 101)))
        XCTAssertEqual(recognizer.mouseUp(at: CGPoint(x: 102, y: 101)), .tapped)
    }

    func test_movingPastTheThreshold_startsADrag() {
        var recognizer = PetGestureRecognizer()

        _ = recognizer.mouseDown(at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(recognizer.mouseDragged(to: CGPoint(x: 140, y: 100)), .dragBegan(CGPoint(x: 140, y: 100)))
    }

    func test_dragBeginsOnlyOnce_thenReportsMovement() {
        var recognizer = PetGestureRecognizer()

        _ = recognizer.mouseDown(at: CGPoint(x: 100, y: 100))
        _ = recognizer.mouseDragged(to: CGPoint(x: 140, y: 100))

        XCTAssertEqual(recognizer.mouseDragged(to: CGPoint(x: 160, y: 120)), .dragMoved(CGPoint(x: 160, y: 120)))
    }

    func test_releasingAfterADrag_endsTheDragRatherThanTapping() {
        var recognizer = PetGestureRecognizer()

        _ = recognizer.mouseDown(at: CGPoint(x: 100, y: 100))
        _ = recognizer.mouseDragged(to: CGPoint(x: 200, y: 200))

        XCTAssertEqual(recognizer.mouseUp(at: CGPoint(x: 200, y: 200)), .dragEnded)
    }

    /// Events can arrive without a preceding press (the cursor entered the
    /// hitbox mid-drag of something else); they must not be mistaken for
    /// interaction with the pet.
    func test_movementWithoutAPress_isIgnored() {
        var recognizer = PetGestureRecognizer()

        XCTAssertNil(recognizer.mouseDragged(to: CGPoint(x: 200, y: 200)))
        XCTAssertNil(recognizer.mouseUp(at: CGPoint(x: 200, y: 200)))
    }

    func test_aSecondGestureStartsClean() {
        var recognizer = PetGestureRecognizer()

        _ = recognizer.mouseDown(at: .zero)
        _ = recognizer.mouseDragged(to: CGPoint(x: 300, y: 0))
        _ = recognizer.mouseUp(at: CGPoint(x: 300, y: 0))

        _ = recognizer.mouseDown(at: CGPoint(x: 300, y: 0))
        XCTAssertEqual(recognizer.mouseUp(at: CGPoint(x: 300, y: 0)), .tapped, "the previous drag must not leak")
    }

    // MARK: - Double-tap ("petting" interaction, 2026-07-29)

    func test_twoQuickTapsCloseTogether_isADoubleTap() {
        var currentTime: TimeInterval = 0
        var recognizer = PetGestureRecognizer(now: { currentTime })

        _ = recognizer.mouseDown(at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(recognizer.mouseUp(at: CGPoint(x: 100, y: 100)), .tapped)

        currentTime += 0.2
        _ = recognizer.mouseDown(at: CGPoint(x: 102, y: 101))
        XCTAssertEqual(recognizer.mouseUp(at: CGPoint(x: 102, y: 101)), .doubleTapped)
    }

    func test_twoTapsTooFarApartInTime_areTwoSeparateTaps() {
        var currentTime: TimeInterval = 0
        var recognizer = PetGestureRecognizer(now: { currentTime })

        _ = recognizer.mouseDown(at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(recognizer.mouseUp(at: CGPoint(x: 100, y: 100)), .tapped)

        currentTime += 1.0 // well past the double-tap window
        _ = recognizer.mouseDown(at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(recognizer.mouseUp(at: CGPoint(x: 100, y: 100)), .tapped)
    }

    func test_twoTapsTooFarApartInSpace_areTwoSeparateTaps() {
        var currentTime: TimeInterval = 0
        var recognizer = PetGestureRecognizer(now: { currentTime })

        _ = recognizer.mouseDown(at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(recognizer.mouseUp(at: CGPoint(x: 100, y: 100)), .tapped)

        currentTime += 0.1
        _ = recognizer.mouseDown(at: CGPoint(x: 300, y: 300))
        XCTAssertEqual(recognizer.mouseUp(at: CGPoint(x: 300, y: 300)), .tapped)
    }

    /// The double-tap is consumed once it fires, so a third quick tap starts
    /// a fresh single/double cycle rather than chaining forever.
    func test_thirdQuickTap_afterADoubleTap_isASingleTapAgain() {
        var currentTime: TimeInterval = 0
        var recognizer = PetGestureRecognizer(now: { currentTime })

        _ = recognizer.mouseDown(at: .zero)
        _ = recognizer.mouseUp(at: .zero)
        currentTime += 0.1
        _ = recognizer.mouseDown(at: .zero)
        XCTAssertEqual(recognizer.mouseUp(at: .zero), .doubleTapped)

        currentTime += 0.1
        _ = recognizer.mouseDown(at: .zero)
        XCTAssertEqual(recognizer.mouseUp(at: .zero), .tapped)
    }

    /// Only a completed tap should seed the double-tap window -- a drag
    /// ending shouldn't make the next tap register as a double.
    func test_dragEnding_doesNotCountTowardADoubleTap() {
        var currentTime: TimeInterval = 0
        var recognizer = PetGestureRecognizer(now: { currentTime })

        _ = recognizer.mouseDown(at: .zero)
        _ = recognizer.mouseDragged(to: CGPoint(x: 200, y: 0))
        XCTAssertEqual(recognizer.mouseUp(at: CGPoint(x: 200, y: 0)), .dragEnded)

        currentTime += 0.1
        _ = recognizer.mouseDown(at: CGPoint(x: 200, y: 0))
        XCTAssertEqual(recognizer.mouseUp(at: CGPoint(x: 200, y: 0)), .tapped)
    }
}
