//
//  CompanionAppLauncherTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//

import XCTest
@testable import Puck

final class CompanionAppLauncherTests: XCTestCase {
    func test_launchIfNeeded_doesNothing_whenAlreadyRunning() {
        var launchedIds: [String] = []
        CompanionAppLauncher.launchIfNeeded(
            bundleIdentifier: "com.speaki-e.PuckClient",
            isRunning: { _ in true },
            launch: { launchedIds.append($0) }
        )
        XCTAssertTrue(launchedIds.isEmpty)
    }

    func test_launchIfNeeded_launches_whenNotRunning() {
        var launchedIds: [String] = []
        CompanionAppLauncher.launchIfNeeded(
            bundleIdentifier: "com.speaki-e.PuckClient",
            isRunning: { _ in false },
            launch: { launchedIds.append($0) }
        )
        XCTAssertEqual(launchedIds, ["com.speaki-e.PuckClient"])
    }
}
