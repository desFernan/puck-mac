//
//  SidebarFilterTests.swift
//  PuckTests
//
//  The sidebar only ever grows -- one section per workspace, one row per
//  chat, nothing archived. This is what the filter field has to get right.
//

import XCTest
@testable import Puck

final class SidebarFilterTests: XCTestCase {
    func test_anEmptyQuery_keepsEverything() {
        XCTAssertTrue(SidebarFilter.matchesWorkspace("", name: "Puck", projectPath: nil))
        XCTAssertTrue(SidebarFilter.matchesSession("   ", title: "무엇이든"))
        XCTAssertFalse(SidebarFilter.isActive("  "))
    }

    func test_aChatIsFoundByItsTitle() {
        XCTAssertTrue(SidebarFilter.matchesSession("island", title: "Island shape"))
        XCTAssertFalse(SidebarFilter.matchesSession("island", title: "Toy physics"))
    }

    func test_matching_ignoresCase() {
        XCTAssertTrue(SidebarFilter.matchesSession("ISLAND", title: "island shape"))
    }

    /// Someone typing a project's name is asking for that project, so the
    /// workspace matching keeps all of its chats rather than only the ones
    /// that happen to repeat the name.
    func test_aWorkspaceIsFoundByItsNameOrItsProject() {
        XCTAssertTrue(SidebarFilter.matchesWorkspace("puck", name: "Puck", projectPath: nil))
        XCTAssertTrue(SidebarFilter.matchesWorkspace("speaki", name: "Puck", projectPath: "/Users/x/Speaki-e/puck"))
        XCTAssertFalse(SidebarFilter.matchesWorkspace("zzz", name: "Puck", projectPath: "/Users/x/puck"))
    }

    func test_koreanTitles_areMatched() {
        XCTAssertTrue(SidebarFilter.matchesSession("어항", title: "어항 크기 조절"))
        XCTAssertFalse(SidebarFilter.matchesSession("어항", title: "장난감 물리"))
    }
}
