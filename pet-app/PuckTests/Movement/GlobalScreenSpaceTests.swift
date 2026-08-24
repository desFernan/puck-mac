//
//  GlobalScreenSpaceTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Coordinate-space normalization (AppKit bottom-left origin <-> top-left,
//  Y-down normalized space) per plan/02_pet-app.md section 3. Also covers a
//  code-review finding on commit 57615a8 (#10): an empty screen list must not
//  silently produce bogus (sign-flipped) coordinates.
//

import XCTest
import CoreGraphics
@testable import Puck

final class GlobalScreenSpaceTests: XCTestCase {
    func test_singleScreen_normalizesTopLeftAndBottomLeft() throws {
        // AppKit: origin (0,0) is the screen's bottom-left, Y increases upward. One 1920x1080 screen.
        let space = try XCTUnwrap(GlobalScreenSpace(appKitFrames: [CGRect(x: 0, y: 0, width: 1920, height: 1080)]))

        // AppKit bottom-left (0,0) -> normalized coordinate is the bottom of the screen (y = height)
        XCTAssertEqual(space.normalized(fromAppKit: CGPoint(x: 0, y: 0)), CGPoint(x: 0, y: 1080))
        // AppKit top-left (0,1080) -> normalized origin (0,0)
        XCTAssertEqual(space.normalized(fromAppKit: CGPoint(x: 0, y: 1080)), CGPoint(x: 0, y: 0))
    }

    func test_singleScreen_normalizedScreenFrameCoversWholeScreen() throws {
        let space = try XCTUnwrap(GlobalScreenSpace(appKitFrames: [CGRect(x: 0, y: 0, width: 1920, height: 1080)]))

        XCTAssertEqual(space.normalizedScreenFrames, [CGRect(x: 0, y: 0, width: 1920, height: 1080)])
        XCTAssertEqual(space.bounds, CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    func test_sideBySideDisplays_sameHeight_boundsSpanBoth() throws {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let secondary = CGRect(x: 1920, y: 0, width: 1920, height: 1080) // to the right of primary in AppKit
        let space = try XCTUnwrap(GlobalScreenSpace(appKitFrames: [primary, secondary]))

        XCTAssertEqual(
            space.normalizedScreenFrames,
            [
                CGRect(x: 0, y: 0, width: 1920, height: 1080),
                CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            ]
        )
        XCTAssertEqual(space.bounds, CGRect(x: 0, y: 0, width: 3840, height: 1080))
    }

    func test_secondaryDisplayAbovePrimary_hasNegativeNormalizedY() throws {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        // AppKit y=1080 sits right above the primary screen's top edge -> physically "above" it
        let secondary = CGRect(x: 0, y: 1080, width: 1280, height: 800)
        let space = try XCTUnwrap(GlobalScreenSpace(appKitFrames: [primary, secondary]))

        // In the normalized (Y-down) space, a screen physically "above" primary has negative Y
        XCTAssertEqual(space.normalizedScreenFrames[1], CGRect(x: 0, y: -800, width: 1280, height: 800))
    }

    func test_appKitPoint_isInverseOfNormalized() throws {
        let space = try XCTUnwrap(GlobalScreenSpace(appKitFrames: [CGRect(x: 0, y: 0, width: 1920, height: 1080)]))
        let original = CGPoint(x: 400, y: 300)

        let roundTripped = space.appKitPoint(fromNormalized: space.normalized(fromAppKit: original))

        XCTAssertEqual(roundTripped, original)
    }

    // MARK: - #10: empty screen list

    func test_emptyAppKitFrames_failsToInitialize() {
        XCTAssertNil(GlobalScreenSpace(appKitFrames: []))
    }
}
