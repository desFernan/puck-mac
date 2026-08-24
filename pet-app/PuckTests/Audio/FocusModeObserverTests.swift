//
//  FocusModeObserverTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Only verifies the notification wiring itself (posting the known
//  notification name flips state and fires onChange). Whether macOS still
//  posts this notification for real Focus/DND changes on this OS version is
//  NOT verified here — see FocusModeObserver's doc comment.
//
//  These post through an injected, private NotificationCenter rather than
//  DistributedNotificationCenter.default(). The wiring under test is entirely
//  in-process; routing it through distnoted made the outcome depend on a
//  system daemon's delivery latency and on nothing else on the Mac posting
//  the same (macOS-owned) notification name mid-test, neither of which this
//  test has any stake in.
//

import XCTest
@testable import Puck

/// `@MainActor`: the type under test is -- it observes on `.main` and is
/// read by the app delegate and the frame loop.
@MainActor
final class FocusModeObserverTests: XCTestCase {
    private func post(to center: NotificationCenter) {
        center.post(name: FocusModeObserver.distributedNotificationName, object: nil)
    }

    func test_receivingNotification_togglesStateAndFiresOnChange() {
        let center = NotificationCenter()
        let observer = FocusModeObserver(center: center)
        let expectation = expectation(description: "onChange fired")
        var receivedValues: [Bool] = []

        observer.onChange = { value in
            receivedValues.append(value)
            expectation.fulfill()
        }
        observer.startObserving()
        defer { observer.stopObserving() }

        XCTAssertFalse(observer.isFocusActive)

        post(to: center)

        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(receivedValues, [true])
        XCTAssertTrue(observer.isFocusActive)
    }

    func test_secondNotification_togglesBack() {
        let center = NotificationCenter()
        let observer = FocusModeObserver(center: center)
        let expectation = expectation(description: "onChange fired twice")
        expectation.expectedFulfillmentCount = 2
        var receivedValues: [Bool] = []

        observer.onChange = { value in
            receivedValues.append(value)
            expectation.fulfill()
        }
        observer.startObserving()
        defer { observer.stopObserving() }

        post(to: center)
        post(to: center)

        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(receivedValues, [true, false])
        XCTAssertFalse(observer.isFocusActive)
    }

    func test_afterStopObserving_furtherNotificationsAreIgnored() {
        let center = NotificationCenter()
        let observer = FocusModeObserver(center: center)
        var callCount = 0
        observer.onChange = { _ in callCount += 1 }

        observer.startObserving()
        observer.stopObserving()
        post(to: center)

        // Delivery, if it happened at all, would be enqueued on the main
        // queue; draining it once is enough to catch a leaked observer.
        let drained = expectation(description: "main queue drained")
        OperationQueue.main.addOperation { drained.fulfill() }
        wait(for: [drained], timeout: 2)

        XCTAssertEqual(callCount, 0)
        XCTAssertFalse(observer.isFocusActive)
    }

    func test_notificationName_isTheDocumentedDoNotDisturbName() {
        XCTAssertEqual(
            FocusModeObserver.distributedNotificationName.rawValue,
            "com.apple.notificationcenterui.dndStatusChanged"
        )
    }

    func test_startAndStopObserving_doNotCrash() {
        let observer = FocusModeObserver()
        observer.startObserving()
        observer.stopObserving()
        observer.stopObserving() // idempotent
    }
}
