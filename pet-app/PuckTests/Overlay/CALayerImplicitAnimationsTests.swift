//
//  CALayerImplicitAnimationsTests.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
//  disableImplicitAnimations() must disable every property Puck assigns
//  by hand every frame -- a property left off the list keeps CALayer's
//  default ~0.25s implicit fade, which reads as smoothing/lag bugs.
//

import QuartzCore
import XCTest
@testable import Puck

final class CALayerImplicitAnimationsTests: XCTestCase {
    private let handDrivenProperties = [
        "position", "transform", "contents", "bounds", "hidden", "opacity", "backgroundColor",
    ]

    func test_disablesImplicitAnimations_forEveryHandDrivenProperty() {
        let layer = CALayer()
        layer.disableImplicitAnimations()

        for property in handDrivenProperties {
            XCTAssertTrue(layer.actions?[property] is NSNull, "\(property) should have its implicit animation disabled")
        }
    }

    // The bug this reproduces: SpriteAvatar.applyTint sets tintLayer.backgroundColor
    // every frame during .spin's rainbow tint. Without "backgroundColor" disabled,
    // each assignment restarts CALayer's default fade instead of jumping straight
    // to the new hue.
    func test_backgroundColor_isHandDriven() {
        let layer = CALayer()
        layer.disableImplicitAnimations()

        XCTAssertTrue(layer.actions?["backgroundColor"] is NSNull)
    }
}
