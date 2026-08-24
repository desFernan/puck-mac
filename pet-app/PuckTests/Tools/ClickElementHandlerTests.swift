//
//  ClickElementHandlerTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Args parsing only -- the actual CGEvent click synthesis is real system
//  input injection and isn't unit tested (same trust level as
//  AccessibilityPermission/MicrophonePermission).
//

import XCTest
import CoreGraphics
@testable import Puck

final class ClickElementHandlerTests: XCTestCase {
    func test_missingFrame_failsWithExecutionFailed() {
        let handler = ClickElementHandler()

        let expectation = expectation(description: "completion called")
        handler.execute(id: "test", args: .object([:])) { result in
            switch result {
            case .success:
                XCTFail("expected failure")
            case .failure(let error):
                XCTAssertEqual(error, .executionFailed("click_element requires a frame {x,y,width,height}"))
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }
}

final class JSONValueExtractFrameTests: XCTestCase {
    func test_extractsFrame_fromWellFormedArgs() {
        let args = JSONValue.object([
            "frame": .object([
                "x": .number(1), "y": .number(2), "width": .number(3), "height": .number(4),
            ]),
        ])

        XCTAssertEqual(args.extractFrame(), CGRect(x: 1, y: 2, width: 3, height: 4))
    }

    func test_returnsNil_whenFrameKeyMissing() {
        XCTAssertNil(JSONValue.object([:]).extractFrame())
    }

    func test_returnsNil_whenFrameFieldsIncomplete() {
        let args = JSONValue.object(["frame": .object(["x": .number(1)])])
        XCTAssertNil(args.extractFrame())
    }
}
