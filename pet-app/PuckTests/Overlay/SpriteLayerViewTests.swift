//
//  SpriteLayerViewTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Smoke coverage for the 2026-07-29 2D switch's CALayer-backed replacement
//  for PetARView -- see SpriteLayerView's own doc comment for why this
//  doesn't need RealityKit's alpha-halo mitigation dance at all.
//

import XCTest
import AppKit
import QuartzCore
@testable import Puck

final class SpriteLayerViewTests: XCTestCase {
    func test_isFlipped_soTopLeftOriginMatchesGlobalScreenSpace() {
        let view = SpriteLayerView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertTrue(view.isFlipped)
    }

    private func makeWindowedView() -> (NSWindow, SpriteLayerView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let view = SpriteLayerView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        window.contentView = view
        return (window, view)
    }

    /// contentLayer is added by hand, so AppKit never hands it the window's
    /// scale the way it does the view's own backing layer -- it stays at 1.0,
    /// and every sprite parented into it inherits that. On a 2x display the
    /// pet then rasterizes at half its physical resolution and gets upscaled:
    /// soft edges, and motion that stair-steps on the coarser pixel grid
    /// instead of advancing smoothly.
    func test_contentLayer_usesTheWindowsBackingScaleFactor() {
        let (window, view) = makeWindowedView()

        XCTAssertEqual(view.contentLayer.contentsScale, window.backingScaleFactor)
    }

    /// Moving between a Retina and a non-Retina display fires
    /// viewDidChangeBackingProperties; a sprite already parented in has to be
    /// re-scaled too, not just the container it hangs from.
    func test_backingPropertiesChange_rescalesExistingSublayers() {
        let (_, view) = makeWindowedView()
        let sprite = CALayer()
        sprite.contentsScale = 1
        view.contentLayer.addSublayer(sprite)

        view.viewDidChangeBackingProperties()

        XCTAssertEqual(sprite.contentsScale, view.contentLayer.contentsScale)
        XCTAssertGreaterThan(sprite.contentsScale, 0)
    }

    func test_initDoesNotCrash_andParentsContentLayerUnderTheViewsLayer() {
        let view = SpriteLayerView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertTrue(view.wantsLayer)
        XCTAssertTrue(view.layer?.sublayers?.contains(view.contentLayer) ?? false)
    }
}
