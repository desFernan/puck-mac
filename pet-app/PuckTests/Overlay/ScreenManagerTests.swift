//
//  ScreenManagerTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  Smoke coverage only — the interesting coordinate logic already lives in
//  (and is fully tested by) GlobalScreenSpaceTests. Actually changing display
//  configuration to exercise didChangeScreenParametersNotification isn't
//  something a unit test can do, so this just confirms the real machine
//  running the test has at least one screen and start/stop don't crash.
//

import XCTest
@testable import Puck

/// `@MainActor`: NSScreen and a `.main` notification, same as the type
/// under test.
@MainActor
final class ScreenManagerTests: XCTestCase {
    func test_initSucceeds_onARealMachineWithAtLeastOneScreen() throws {
        let manager = try XCTUnwrap(ScreenManager())
        XCTAssertFalse(manager.current.appKitFrames.isEmpty)
    }

    func test_startAndStopObserving_doNotCrash() throws {
        let manager = try XCTUnwrap(ScreenManager())
        manager.startObserving()
        manager.stopObserving()
        manager.stopObserving() // idempotent
    }
}
