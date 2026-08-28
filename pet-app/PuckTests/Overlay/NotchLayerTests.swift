//
//  NotchLayerTests.swift
//  PuckTests
//
//  The shape of a housing painted on a display that has not got one.
//

import XCTest
@testable import Puck

@MainActor
final class NotchLayerTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 185, height: 32)

    /// A real housing is already black plastic; painting over it would be a
    /// black rectangle drawn behind a black rectangle.
    func test_aRealHousingIsNotPainted() {
        XCTAssertNil(NotchLayer.make(for: ScreenNotch(rect: rect, isVirtual: false)))
        XCTAssertNotNil(NotchLayer.make(for: ScreenNotch(rect: rect, isVirtual: true)))
    }

    /// It fills its own rect exactly -- the pet's ceiling is worked out from
    /// that rect, so a shape that did not match it would have the pet
    /// stopping somewhere the black does not reach.
    func test_theShapeFillsTheRectItIsGiven() {
        let box = NotchLayer.path(in: rect).boundingBox

        XCTAssertEqual(box.minX, rect.minX, accuracy: 0.5)
        XCTAssertEqual(box.maxX, rect.maxX, accuracy: 0.5)
        XCTAssertEqual(box.minY, rect.minY, accuracy: 0.5)
        XCTAssertEqual(box.maxY, rect.maxY, accuracy: 0.5)
    }

    /// The layer is positioned where the notch is, and carries a shape.
    func test_theLayerSitsWhereTheHousingIs() throws {
        let notch = ScreenNotch(rect: CGRect(x: 663, y: 0, width: 185, height: 32), isVirtual: true)

        let layer = try XCTUnwrap(NotchLayer.make(for: notch))

        XCTAssertEqual(layer.frame, notch.rect)
        XCTAssertNotNil(layer.path)
        XCTAssertLessThan(layer.zPosition, 0, "the pet comes out from under it, not behind it")
    }

    /// A housing shallower than it is wide still rounds, and never so much
    /// that the two corners meet in the middle.
    func test_theRoundingNeverSwallowsTheShape() {
        let squat = CGRect(x: 0, y: 0, width: 20, height: 200)
        let box = NotchLayer.path(in: squat).boundingBox

        XCTAssertEqual(box.width, squat.width, accuracy: 0.5)
        XCTAssertEqual(box.height, squat.height, accuracy: 0.5)
    }
}
