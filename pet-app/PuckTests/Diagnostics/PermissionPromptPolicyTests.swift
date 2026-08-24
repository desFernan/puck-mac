//
//  PermissionPromptPolicyTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Launch used to raise the Accessibility prompt every single time the
//  permission was missing, so anyone who dismissed it — or who was mid-way
//  through granting it — got the dialog again on the next launch, forever.
//  Asking is right; asking repeatedly is not.
//

import XCTest
@testable import Puck

final class PermissionPromptPolicyTests: XCTestCase {
    func test_promptsOnFirstLaunchWhenThePermissionIsMissing() {
        XCTAssertTrue(PermissionPromptPolicy.shouldPromptForAccessibility(isTrusted: false, hasAskedBefore: false))
    }

    func test_doesNotPromptAgainAfterAskingOnce() {
        XCTAssertFalse(
            PermissionPromptPolicy.shouldPromptForAccessibility(isTrusted: false, hasAskedBefore: true),
            "the user has already been shown the dialog; nagging every launch is what this fixes"
        )
    }

    func test_neverPromptsWhenTheGrantIsAlreadyThere() {
        XCTAssertFalse(PermissionPromptPolicy.shouldPromptForAccessibility(isTrusted: true, hasAskedBefore: false))
        XCTAssertFalse(PermissionPromptPolicy.shouldPromptForAccessibility(isTrusted: true, hasAskedBefore: true))
    }
}

final class SettingsStoreAccessibilityFlagTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "PuckTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_defaultsToNotHavingAsked() {
        XCTAssertFalse(SettingsStore(defaults: defaults).hasRequestedAccessibility)
    }

    /// The flag has to outlive the process, or every launch is a first launch
    /// and nothing changes.
    func test_persistsAcrossInstances() {
        SettingsStore(defaults: defaults).hasRequestedAccessibility = true

        XCTAssertTrue(SettingsStore(defaults: defaults).hasRequestedAccessibility)
    }
}
