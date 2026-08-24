//
//  RunAppleScriptHandlerTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Argument validation + a real (harmless) script execution.
//

import XCTest
@testable import Puck

final class RunAppleScriptHandlerTests: XCTestCase {
    func test_missingScript_failsWithExecutionFailed() {
        let handler = RunAppleScriptHandler()

        let expectation = expectation(description: "completion called")
        handler.execute(id: "test", args: .object([:])) { result in
            switch result {
            case .success:
                XCTFail("expected failure")
            case .failure(let error):
                XCTAssertEqual(error, .executionFailed("run_applescript requires a script string"))
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func test_validScript_returnsItsStringResult() {
        let handler = RunAppleScriptHandler()

        let expectation = expectation(description: "completion called")
        handler.execute(id: "test", args: .object(["script": .string("return \"hello\"")])) { result in
            switch result {
            case .success(let data):
                XCTAssertEqual(data, .string("hello"))
            case .failure(let error):
                XCTFail("expected success, got \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }
}
