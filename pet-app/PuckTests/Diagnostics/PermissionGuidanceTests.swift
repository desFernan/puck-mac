//
//  PermissionGuidanceTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  When the pet should go and ask for a permission, and when it should stay
//  out of the way.
//

import XCTest
@testable import Puck

final class PermissionGuidanceTests: XCTestCase {
    private let granted: (PermissionGuidance.Permission) -> Bool = { _ in true }
    private let denied: (PermissionGuidance.Permission) -> Bool = { _ in false }

    func test_toolsThatReachIntoOtherApps_needAccessibility() {
        XCTAssertEqual(PermissionGuidance.permission(requiredBy: "find_ui_element"), .accessibility)
        XCTAssertEqual(PermissionGuidance.permission(requiredBy: "click_element"), .accessibility)
    }

    /// Pointing is the pet walking across its own overlay. It has to keep
    /// working without Accessibility, because it is the documented fallback
    /// for the system dialogs Accessibility can't touch.
    func test_pointingNeedsNothing() {
        XCTAssertNil(PermissionGuidance.permission(requiredBy: "point_at"))
    }

    func test_toolsWithNoPermissionOfTheirOwn() {
        for tool in ["launch_app", "run_shell", "run_applescript", "list_running_apps", "get_frontmost_window"] {
            XCTAssertNil(PermissionGuidance.permission(requiredBy: tool), "\(tool) should not ask for a permission")
        }
    }

    func test_guidesWhenTheNeededPermissionIsMissing() {
        XCTAssertEqual(PermissionGuidance.shouldGuide(tool: "find_ui_element", isGranted: denied), .accessibility)
    }

    /// permission_denied can come back for reasons a prompt cannot fix. Being
    /// walked through granting something already granted is worse than
    /// silence.
    func test_doesNotGuideWhenThePermissionIsAlreadyGranted() {
        XCTAssertNil(PermissionGuidance.shouldGuide(tool: "find_ui_element", isGranted: granted))
    }

    func test_doesNotGuideForAToolThatNeedsNoPermission() {
        XCTAssertNil(PermissionGuidance.shouldGuide(tool: "run_shell", isGranted: denied))
    }
}

final class ClickElementPermissionTests: XCTestCase {
    /// Without Accessibility, CGEvent.post is a no-op -- so reporting success
    /// made the agent tell the user it had clicked something it hadn't.
    func test_withoutAccessibility_failsInsteadOfReportingAClickThatNeverHappened() {
        let handler = ClickElementHandler()
        handler.isAccessibilityTrusted = { false }
        let frame = JSONValue.object([
            "frame": .object(["x": .number(10), "y": .number(20), "width": .number(30), "height": .number(40)]),
        ])

        // A box rather than a captured var: a handler's completion is
        // `@Sendable`, because a handler answers from wherever its work
        // finished.
        let result = UncheckedBox<Result<JSONValue?, ToolExecutionError>?>(nil)
        handler.execute(id: "test", args: frame) { result.value = $0 }

        guard case .failure(let error) = result.value else {
            return XCTFail("expected a failure, got \(String(describing: result.value))")
        }
        XCTAssertEqual(error, .permissionDenied)
    }

    /// A malformed call is still a malformed call, whatever the TCC state --
    /// and it must not be reported as a permission problem, or the pet would
    /// go and ask for a permission that was never the obstacle.
    func test_missingFrameIsStillAnArgumentError_notAPermissionOne() {
        let handler = ClickElementHandler()
        handler.isAccessibilityTrusted = { false }

        let result = UncheckedBox<Result<JSONValue?, ToolExecutionError>?>(nil)
        handler.execute(id: "test", args: .object([:])) { result.value = $0 }

        guard case .failure(let error) = result.value else {
            return XCTFail("expected a failure, got \(String(describing: result.value))")
        }
        XCTAssertNotEqual(error, .permissionDenied)
    }
}
