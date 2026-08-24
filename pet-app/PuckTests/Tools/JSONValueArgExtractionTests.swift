//
//  JSONValueArgExtractionTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Shared JSONValue arg-extraction helpers used across tool handlers.
//

import XCTest
import CoreGraphics
@testable import Puck

final class JSONValueArgExtractionTests: XCTestCase {
    func test_extractString_returnsValue_whenKeyIsAString() {
        let args = JSONValue.object(["command": .string("ls -la")])
        XCTAssertEqual(args.extractString(key: "command"), "ls -la")
    }

    func test_extractString_returnsNil_whenKeyMissing() {
        let args = JSONValue.object([:])
        XCTAssertNil(args.extractString(key: "command"))
    }

    func test_extractString_returnsNil_whenKeyIsWrongType() {
        let args = JSONValue.object(["command": .number(42)])
        XCTAssertNil(args.extractString(key: "command"))
    }

    func test_extractString_returnsNil_whenArgsIsNotAnObject() {
        let args = JSONValue.string("not an object")
        XCTAssertNil(args.extractString(key: "command"))
    }

    func test_extractFrame_returnsValue_whenFieldsPresent() {
        let args = JSONValue.object([
            "frame": .object(["x": .number(1), "y": .number(2), "width": .number(3), "height": .number(4)]),
        ])
        XCTAssertEqual(args.extractFrame(), CGRect(x: 1, y: 2, width: 3, height: 4))
    }

    // A NaN/Infinity frame reaches MoveToState.target unguarded and
    // permanently wedges the pet (MovementSolver's arrival check never
    // becomes true) -- extractPID already guards this same class of
    // malformed-number input, extractFrame must too.
    func test_extractFrame_returnsNil_whenAFieldIsNotFinite() {
        let args = JSONValue.object([
            "frame": .object(["x": .number(.nan), "y": .number(2), "width": .number(3), "height": .number(4)]),
        ])
        XCTAssertNil(args.extractFrame())
    }

    func test_extractFrame_returnsNil_whenAFieldIsInfinite() {
        let args = JSONValue.object([
            "frame": .object(["x": .number(1), "y": .number(2), "width": .number(.infinity), "height": .number(4)]),
        ])
        XCTAssertNil(args.extractFrame())
    }

    func test_extractPID_returnsValue_whenKeyIsANumber() {
        let args = JSONValue.object(["pid": .number(501)])
        XCTAssertEqual(args.extractPID(), 501)
    }

    func test_extractPID_returnsNil_whenKeyMissing() {
        XCTAssertNil(JSONValue.object([:]).extractPID())
    }

    // pid_t is Int32 on Darwin -- Int32(Double) traps (crashes the whole
    // process) for non-finite or out-of-Int32-range values. An arbitrary
    // find_ui_element dispatch can send any JSON number here, so this must
    // degrade to nil rather than crash the agent.
    func test_extractPID_returnsNil_ratherThanCrashing_whenValueExceedsInt32Range() {
        let args = JSONValue.object(["pid": .number(1e20)])
        XCTAssertNil(args.extractPID())
    }

    func test_extractPID_returnsNil_ratherThanCrashing_whenValueIsNegativeAndOutOfRange() {
        let args = JSONValue.object(["pid": .number(-1e20)])
        XCTAssertNil(args.extractPID())
    }

    func test_extractPID_returnsNil_ratherThanCrashing_whenValueIsNotFinite() {
        let args = JSONValue.object(["pid": .number(Double.infinity)])
        XCTAssertNil(args.extractPID())
    }
}
