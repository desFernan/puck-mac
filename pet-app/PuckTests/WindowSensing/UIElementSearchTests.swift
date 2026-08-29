//
//  UIElementSearchTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The traversal half of F4 level 2, tested against a fake tree so it needs
//  no live app and no Accessibility permission. F4:
//  "AXUIElementCreateApplication(pid) 트리 DFS (깊이 제한 + 타임아웃 필수)".
//

import XCTest
@testable import Puck

/// A hand-built accessibility tree.
private final class FakeNode: AXNode {
    let role: String?
    let title: String?
    let frame: CGRect?
    let isEnabled: Bool?
    private let children: [FakeNode]
    /// How many times this node's children were asked for — proves the
    /// traversal stopped rather than walking the whole tree.
    private(set) var childAccessCount = 0

    init(
        role: String? = "AXGroup",
        title: String? = nil,
        frame: CGRect? = CGRect(x: 0, y: 0, width: 10, height: 10),
        isEnabled: Bool? = true,
        children: [FakeNode] = []
    ) {
        self.role = role
        self.title = title
        self.frame = frame
        self.isEnabled = isEnabled
        self.children = children
    }

    var childNodes: [AXNode] {
        childAccessCount += 1
        return children
    }
}

final class UIElementSearchTests: XCTestCase {
    private func button(_ title: String, x: CGFloat = 0) -> FakeNode {
        FakeNode(role: "AXButton", title: title, frame: CGRect(x: x, y: 50, width: 80, height: 24))
    }

    func test_findsAButtonByRoleAndTitleSubstring() throws {
        let tree = FakeNode(children: [
            FakeNode(children: [button("Cancel"), button("카메라 허용", x: 200)]),
        ])

        let match = UIElementSearch.firstMatch(
            in: tree,
            query: .init(role: "AXButton", titleContains: "카메라"),
            maxDepth: 10,
            budget: 1
        )

        XCTAssertEqual(match?.title, "카메라 허용")
        XCTAssertEqual(match?.role, "AXButton")
        XCTAssertEqual(match?.frame, CGRect(x: 200, y: 50, width: 80, height: 24))
    }

    func test_titleMatchIsCaseInsensitive() {
        let tree = FakeNode(children: [button("Allow Camera")])

        let match = UIElementSearch.firstMatch(
            in: tree, query: .init(role: nil, titleContains: "camera"), maxDepth: 10, budget: 1
        )

        XCTAssertEqual(match?.title, "Allow Camera")
    }

    func test_roleAloneMatchesTheFirstOfThatRole() {
        let tree = FakeNode(children: [FakeNode(role: "AXStaticText", title: "hello"), button("OK")])

        let match = UIElementSearch.firstMatch(
            in: tree, query: .init(role: "AXButton", titleContains: nil), maxDepth: 10, budget: 1
        )

        XCTAssertEqual(match?.title, "OK")
    }

    func test_noMatchReturnsNil() {
        let tree = FakeNode(children: [button("OK")])

        XCTAssertNil(UIElementSearch.firstMatch(
            in: tree, query: .init(role: "AXSlider", titleContains: nil), maxDepth: 10, budget: 1
        ))
    }

    /// A real AX tree can be enormous or even cyclic; the plan makes the depth
    /// limit mandatory for exactly that reason.
    func test_stopsAtTheDepthLimit() {
        // Depth 0 = root, target sits at depth 3.
        let deep = FakeNode(children: [FakeNode(children: [FakeNode(children: [button("Deep")])])])

        XCTAssertNil(
            UIElementSearch.firstMatch(in: deep, query: .init(role: "AXButton", titleContains: nil), maxDepth: 2, budget: 1),
            "the button is deeper than the limit"
        )
        XCTAssertNotNil(
            UIElementSearch.firstMatch(in: deep, query: .init(role: "AXButton", titleContains: nil), maxDepth: 3, budget: 1)
        )
    }

    /// An unresponsive app can make each AX attribute read block; the search
    /// must give up rather than hang the tool call.
    func test_stopsWhenTheTimeBudgetIsExhausted() {
        let tree = FakeNode(children: (0..<50).map { _ in FakeNode(children: [button("OK")]) })

        let match = UIElementSearch.firstMatch(
            in: tree, query: .init(role: "AXButton", titleContains: nil), maxDepth: 10, budget: 0
        )

        XCTAssertNil(match, "no time to look at all")
    }

    func test_elementsWithoutAFrameAreSkipped() {
        let noFrame = FakeNode(role: "AXButton", title: "OK", frame: nil)
        let withFrame = button("OK", x: 300)
        let tree = FakeNode(children: [noFrame, withFrame])

        let match = UIElementSearch.firstMatch(
            in: tree, query: .init(role: "AXButton", titleContains: nil), maxDepth: 10, budget: 1
        )

        XCTAssertEqual(match?.frame?.origin.x, 300, "an element with no position can't be pointed at")
    }

    func test_reportsWhetherTheElementIsEnabled() throws {
        let disabled = FakeNode(role: "AXButton", title: "OK", isEnabled: false)
        let match = UIElementSearch.firstMatch(
            in: FakeNode(children: [disabled]), query: .init(role: "AXButton", titleContains: nil), maxDepth: 10, budget: 1
        )

        XCTAssertEqual(match?.isEnabled, false)
    }
}
