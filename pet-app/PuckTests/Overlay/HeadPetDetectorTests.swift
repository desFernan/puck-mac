//
//  HeadPetDetectorTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Recognising a stroke over the pet's head, and — just as importantly — not
//  recognising anything else. Petting fires on plain cursor movement with no click to
//  confirm intent, so the false-positive cases below matter more than the
//  happy path.
//

import XCTest
@testable import Puck

final class HeadPetDetectorTests: XCTestCase {
    private var detector = HeadPetDetector()
    private var now: TimeInterval = 100

    override func setUp() {
        super.setUp()
        detector = HeadPetDetector()
        now = 100
    }

    /// One leg of a stroke: `distance` px in `direction`, in small steps like
    /// a real cursor, returning the last update seen.
    @discardableResult
    private func stroke(_ direction: CGFloat, distance: CGFloat = 30, overHead: Bool = true) -> HeadPetDetector.Update {
        var result = HeadPetDetector.Update.unchanged
        var moved: CGFloat = 0
        while moved < distance {
            now += 0.016
            x += direction * 10
            moved += 10
            let update = detector.cursorMoved(to: CGPoint(x: x, y: 50), overHead: overHead, now: now)
            if update != .unchanged { result = update }
        }
        return result
    }

    private var x: CGFloat = 0

    func test_rubbingBackAndForthOverTheHeadStartsPetting() {
        stroke(1)
        stroke(-1)
        stroke(1)
        let update = stroke(-1)

        XCTAssertEqual(update, .began)
        XCTAssertTrue(detector.isPetting)
    }

    // MARK: - Things that must NOT count as petting

    /// The cursor crossing the pet on its way somewhere else.
    func test_aSinglePassOverTheHeadIsNotPetting() {
        stroke(1, distance: 200)

        XCTAssertFalse(detector.isPetting)
    }

    /// One there-and-back is a wobble, not a stroke.
    func test_oneReversalIsNotPetting() {
        stroke(1)
        stroke(-1)

        XCTAssertFalse(detector.isPetting)
    }

    /// Hand tremor: plenty of reversals, no actual travel.
    func test_jitteringInPlaceIsNotPetting() {
        for step in 0..<40 {
            now += 0.016
            _ = detector.cursorMoved(to: CGPoint(x: step.isMultiple(of: 2) ? 100 : 102, y: 50), overHead: true, now: now)
        }

        XCTAssertFalse(detector.isPetting, "2px wiggles are not strokes")
    }

    /// Reversals spread out over a long time aren't one gesture.
    func test_slowReversalsFarApartDoNotAddUp() {
        for direction in [CGFloat(1), -1, 1, -1] {
            stroke(direction)
            now += HeadPetDetector.strokeWindow * 2
        }

        XCTAssertFalse(detector.isPetting)
    }

    /// The same motion over the pet's body/feet is not petting its head.
    func test_rubbingOffTheHeadIsNotPetting() {
        stroke(1, overHead: false)
        stroke(-1, overHead: false)
        stroke(1, overHead: false)
        stroke(-1, overHead: false)

        XCTAssertFalse(detector.isPetting)
    }

    // MARK: - Ending

    func test_pettingEndsWhenTheCursorGoesStill() {
        stroke(1); stroke(-1); stroke(1); stroke(-1)
        XCTAssertTrue(detector.isPetting)

        now += HeadPetDetector.idleTimeout + 0.1
        let update = detector.tick(now: now)

        XCTAssertEqual(update, .ended)
        XCTAssertFalse(detector.isPetting)
    }

    /// A brief pause mid-stroke shouldn't end it — hands do that.
    func test_aShortPauseDoesNotEndPetting() {
        stroke(1); stroke(-1); stroke(1); stroke(-1)

        now += HeadPetDetector.idleTimeout / 2
        XCTAssertEqual(detector.tick(now: now), .unchanged)
        XCTAssertTrue(detector.isPetting)
    }

    func test_pettingEndsWhenTheCursorLeavesTheHead() {
        stroke(1); stroke(-1); stroke(1); stroke(-1)

        let update = detector.cursorMoved(to: CGPoint(x: 999, y: 999), overHead: false, now: now)

        XCTAssertEqual(update, .ended)
        XCTAssertFalse(detector.isPetting)
    }

    /// Leaving and coming back has to earn the reversals again, or the pet
    /// gets re-petted by a cursor merely re-entering the head.
    func test_returningToTheHeadStartsFromScratch() {
        stroke(1); stroke(-1); stroke(1); stroke(-1)
        _ = detector.cursorMoved(to: CGPoint(x: 999, y: 999), overHead: false, now: now)

        stroke(1)
        stroke(-1)

        XCTAssertFalse(detector.isPetting)
    }

    /// `.began`/`.ended` are edges: the caller drives a state transition off
    /// them, so a repeat would restart the reaction every frame.
    func test_continuedStrokingReportsNoFurtherBegan() {
        stroke(1); stroke(-1); stroke(1); stroke(-1)

        for direction in [CGFloat(1), -1, 1, -1] {
            XCTAssertNotEqual(stroke(direction), .began, "began must fire once per stroke")
        }
        XCTAssertTrue(detector.isPetting)
    }

    func test_endingTwiceReportsEndedOnlyOnce() {
        stroke(1); stroke(-1); stroke(1); stroke(-1)
        now += HeadPetDetector.idleTimeout + 0.1
        XCTAssertEqual(detector.tick(now: now), .ended)

        now += 1
        XCTAssertEqual(detector.tick(now: now), .unchanged)
    }
}
