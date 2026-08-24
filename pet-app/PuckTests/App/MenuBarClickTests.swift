//
//  MenuBarClickTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//

import XCTest
@testable import Puck

final class MenuBarClickTests: XCTestCase {
    func test_rightMouseUp_showsThePanel() {
        XCTAssertEqual(MenuBarClick(eventType: .rightMouseUp), .showPanel)
    }

    func test_leftMouseUp_opensTheClient() {
        XCTAssertEqual(MenuBarClick(eventType: .leftMouseUp), .openClient)
    }

    func test_noEvent_defaultsToOpeningTheClient() {
        XCTAssertEqual(MenuBarClick(eventType: nil), .openClient)
    }
}
