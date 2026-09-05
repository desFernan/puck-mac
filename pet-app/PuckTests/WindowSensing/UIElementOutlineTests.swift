//
//  UIElementOutlineTests.swift
//  PuckTests
//
//  An app's accessibility tree, written out so a model can read it.
//
//  Against the same `AXNode` protocol the search uses, so a whole tree can be
//  built in a test without a running app.
//

import CoreGraphics
import XCTest
@testable import Puck

/// A node built by hand. The real one is an AXUIElement; this is the same
/// four questions answered from memory.
private struct FakeNode: AXNode {
    var role: String?
    var title: String?
    var frame: CGRect?
    var isEnabled: Bool?
    var children: [FakeNode] = []

    var childNodes: [AXNode] { children }
}

private func node(
    _ role: String?,
    _ title: String? = nil,
    frame: CGRect? = CGRect(x: 0, y: 0, width: 100, height: 20),
    enabled: Bool? = nil,
    _ children: [FakeNode] = []
) -> FakeNode {
    FakeNode(role: role, title: title, frame: frame, isEnabled: enabled, children: children)
}

final class UIElementOutlineTests: XCTestCase {
    func test_aLineCarriesRoleTitleAndFrame() {
        let line = UIElementOutline.line(
            depth: 1,
            role: "AXButton",
            title: "저장",
            frame: CGRect(x: 12, y: 34, width: 80, height: 24),
            isEnabled: true
        )

        XCTAssertEqual(line, "  AXButton \"저장\" [12 34 80 24]")
    }

    /// The frame is the whole point of the line: point_at and click_element
    /// both take one, so a line here can be used without another lookup.
    func test_theFrameIsTheOneOtherToolsTake() {
        let tree = node("AXWindow", "설정", frame: CGRect(x: 0, y: 0, width: 400, height: 300), [
            node("AXButton", "켜기", frame: CGRect(x: 10, y: 20, width: 60, height: 24)),
        ])

        let text = UIElementOutline.describe(tree)

        XCTAssertTrue(text.contains("[10 20 60 24]"), text)
    }

    /// A disabled control is said to be disabled, because the model would
    /// otherwise click it and report success.
    func test_aDisabledControlSaysSo() {
        let text = UIElementOutline.describe(node("AXButton", "저장", enabled: false))

        XCTAssertTrue(text.contains("(disabled)"), text)
    }

    /// Layout scaffolding is walked through but not printed: a tree that is
    /// nine tenths AXGroup is one nobody can read.
    func test_scaffoldingIsWalkedThroughRatherThanPrinted() {
        let tree = node("AXWindow", "창", [
            node("AXGroup", nil, [
                node("AXGroup", nil, [
                    node("AXButton", "안쪽 버튼"),
                ]),
            ]),
        ])

        let text = UIElementOutline.describe(tree)
        let lines = text.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 2, text)
        XCTAssertTrue(lines[0].contains("AXWindow"))
        XCTAssertTrue(lines[1].contains("안쪽 버튼"))
        XCTAssertTrue(lines[1].hasPrefix("  "), "the button is one level under the window it is in")
    }

    /// A group with a name is worth a line -- that is how a section of a
    /// settings pane identifies itself.
    func test_anamedGroupIsWorthPrinting() {
        XCTAssertTrue(UIElementOutline.isWorthPrinting(
            role: "AXGroup", title: "일반", frame: CGRect(x: 0, y: 0, width: 10, height: 10)
        ))
        XCTAssertFalse(UIElementOutline.isWorthPrinting(
            role: "AXGroup", title: nil, frame: CGRect(x: 0, y: 0, width: 10, height: 10)
        ))
    }

    /// Something with no size is not on screen, whatever it claims to be.
    func test_somethingWithNoSizeIsNotPrinted() {
        XCTAssertFalse(UIElementOutline.isWorthPrinting(
            role: "AXButton", title: "숨겨진", frame: CGRect(x: 0, y: 0, width: 0, height: 0)
        ))
        XCTAssertFalse(UIElementOutline.isWorthPrinting(role: "AXButton", title: "프레임 없음", frame: nil))
    }

    /// One element must not be able to spend the whole budget: an
    /// AXStaticText's title can be a paragraph.
    func test_aVeryLongTitleIsCutShort() {
        let line = UIElementOutline.line(
            depth: 0,
            role: "AXStaticText",
            title: String(repeating: "가", count: 500),
            frame: nil,
            isEnabled: nil
        )

        XCTAssertLessThan(line.count, 120, line)
        XCTAssertTrue(line.hasSuffix("…\""), line)
    }

    /// Whitespace in a title is collapsed, so one element stays one line.
    func test_aTitleWithNewlinesStaysOneLine() {
        let line = UIElementOutline.line(
            depth: 0, role: "AXStaticText", title: "첫 줄\n둘째 줄", frame: nil, isEnabled: nil
        )

        XCTAssertFalse(line.contains("\n"))
        XCTAssertTrue(line.contains("첫 줄 둘째 줄"), line)
    }

    /// A Safari window is thousands of elements and all of it would go into
    /// the model's context, so the list stops and says it stopped.
    func test_aHugeTreeIsCappedAndSaysSo() {
        let many = (0..<500).map { node("AXButton", "버튼 \($0)") }
        let tree = node("AXWindow", "창", many)

        let text = UIElementOutline.describe(tree, limit: 20)
        let lines = text.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 21, "twenty elements and the line saying there are more")
        XCTAssertTrue(lines.last?.contains("find_ui_element") ?? false, "it has to say what to do next")
    }

    /// An app that takes too long is stopped rather than hanging the tool,
    /// and the answer says which of the two happened.
    func test_anAppThatIsTooSlowIsStoppedAndSaysSo() {
        var clock: TimeInterval = 0
        let tree = node("AXWindow", "창", (0..<50).map { node("AXButton", "버튼 \($0)") })

        let text = UIElementOutline.describe(tree, budget: 1, now: {
            clock += 0.3
            return clock
        })

        XCTAssertTrue(text.contains("too long"), text)
    }

    /// An app with no readable tree at all -- a game, a canvas -- produces
    /// nothing, which the handler turns into "nothing there" rather than an
    /// error.
    func test_anUnreadableAppProducesNothing() {
        XCTAssertTrue(UIElementOutline.describe(node(nil, nil, frame: nil)).isEmpty)
    }
}
