//
//  ToyBoxTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Several toys out at once: toggling them on/off, which one the cursor
//  grabs, and which one the pet is currently playing with.
//

import XCTest
import QuartzCore
@testable import Puck

final class ToyBoxTests: XCTestCase {
    private let pumpkin = ToyCatalogue.pumpkin
    private let wand = ToyCatalogue.wand

    private func makeBox() -> (ToyBox, CALayer) {
        let parent = CALayer()
        return (ToyBox(parent: parent), parent)
    }

    // MARK: - Toggling

    func test_toggle_putsAToyOut() {
        let (box, parent) = makeBox()

        let isOut = box.toggle(pumpkin, at: CGPoint(x: 200, y: 100))

        XCTAssertTrue(isOut)
        XCTAssertTrue(box.isOut(pumpkin))
        XCTAssertEqual(box.all.count, 1)
        XCTAssertEqual(parent.sublayers?.count, 1)
    }

    func test_toggleAgain_takesTheSameToyAway() {
        let (box, parent) = makeBox()
        box.toggle(pumpkin, at: CGPoint(x: 200, y: 100))

        let isOut = box.toggle(pumpkin, at: CGPoint(x: 300, y: 100))

        XCTAssertFalse(isOut)
        XCTAssertFalse(box.isOut(pumpkin))
        XCTAssertTrue(box.all.isEmpty)
        // The layer has to go with it, or an invisible toy keeps being drawn.
        XCTAssertTrue(parent.sublayers?.isEmpty ?? true)
    }

    func test_severalToysCanBeOutAtOnce() {
        let (box, _) = makeBox()

        box.toggle(pumpkin, at: CGPoint(x: 100, y: 100))
        box.toggle(wand, at: CGPoint(x: 400, y: 100))

        XCTAssertEqual(box.outToyNames, [pumpkin.name, wand.name])
        XCTAssertEqual(box.all.count, 2)
    }

    func test_toggingOneOffLeavesTheOtherOut() {
        let (box, _) = makeBox()
        box.toggle(pumpkin, at: CGPoint(x: 100, y: 100))
        box.toggle(wand, at: CGPoint(x: 400, y: 100))

        box.toggle(pumpkin, at: CGPoint(x: 100, y: 100))

        XCTAssertEqual(box.outToyNames, [wand.name])
    }

    /// Spawn is separate from toggle so the menu can toggle while anything
    /// else (a future "fetch the toy back" path) can reposition without
    /// accidentally removing it.
    func test_spawn_onAToyAlreadyOut_movesItInsteadOfAddingASecond() {
        let (box, _) = makeBox()
        box.spawn(pumpkin, at: CGPoint(x: 100, y: 100))

        box.spawn(pumpkin, at: CGPoint(x: 700, y: 100))

        XCTAssertEqual(box.all.count, 1)
        XCTAssertEqual(box.controller(for: pumpkin)?.state?.position, CGPoint(x: 700, y: 100))
    }

    // MARK: - What the pet is playing with

    func test_focus_remembersWhatWasPlayedWithLast() {
        let (box, _) = makeBox()
        box.spawn(pumpkin, at: CGPoint(x: 100, y: 100))

        box.focus(box.controller(for: pumpkin))

        XCTAssertTrue(box.focused === box.controller(for: pumpkin))
        XCTAssertEqual(box.lastPlayedName, pumpkin.name)
    }

    func test_clearFocus_keepsTheLastPlayedName() {
        // The name has to outlive the focus: it is what stops the pet picking
        // the same toy again on the very next draw.
        let (box, _) = makeBox()
        box.spawn(pumpkin, at: CGPoint(x: 100, y: 100))
        box.focus(box.controller(for: pumpkin))

        box.clearFocus()

        XCTAssertNil(box.focused)
        XCTAssertEqual(box.lastPlayedName, pumpkin.name)
    }

    func test_removingTheFocusedToy_dropsTheFocus() {
        // Otherwise the pet keeps playing with something that no longer exists.
        let (box, _) = makeBox()
        box.spawn(pumpkin, at: CGPoint(x: 100, y: 100))
        box.focus(box.controller(for: pumpkin))

        box.remove(pumpkin)

        XCTAssertNil(box.focused)
    }

    func test_removingAnotherToy_leavesTheFocusAlone() {
        let (box, _) = makeBox()
        box.spawn(pumpkin, at: CGPoint(x: 100, y: 100))
        box.spawn(wand, at: CGPoint(x: 400, y: 100))
        box.focus(box.controller(for: pumpkin))

        box.remove(wand)

        XCTAssertTrue(box.focused === box.controller(for: pumpkin))
    }

    // MARK: - Cursor

    func test_hitTest_prefersTheToyPutOutMostRecently() {
        // They are drawn in spawn order, so the newest is on top and is what
        // the user sees themselves grabbing.
        let (box, _) = makeBox()
        let shared = CGPoint(x: 300, y: 200)
        box.spawn(pumpkin, at: shared)
        box.spawn(wand, at: shared)

        let grabbed = box.hitTest(shared, tolerance: 8)

        XCTAssertTrue(grabbed === box.controller(for: wand))
    }

    func test_hitTest_awayFromEveryToy_findsNothing() {
        let (box, _) = makeBox()
        box.spawn(pumpkin, at: CGPoint(x: 300, y: 200))

        XCTAssertNil(box.hitTest(CGPoint(x: 900, y: 200), tolerance: 8))
    }

    func test_hitTest_ignoresAToyThatHasBeenTakenAway() {
        let (box, _) = makeBox()
        let position = CGPoint(x: 300, y: 200)
        box.spawn(pumpkin, at: position)
        box.remove(pumpkin)

        XCTAssertNil(box.hitTest(position, tolerance: 8))
    }

    // MARK: - Size and reparenting

    func test_updateScale_appliesToEveryToyOut() {
        let (box, _) = makeBox()
        box.spawn(pumpkin, at: CGPoint(x: 100, y: 100))
        box.spawn(wand, at: CGPoint(x: 400, y: 100))
        let before = box.all.map(\.layer.bounds.height)

        box.updateScale(2)

        for (controller, height) in zip(box.all, before) {
            XCTAssertEqual(controller.layer.bounds.height, height * 2, accuracy: 0.001)
        }
    }

    func test_updateScale_alsoAppliesToToysPutOutLater() throws {
        // The slider is a setting; a toy fetched after it moved must not come
        // back at the old size.
        let (box, _) = makeBox()
        box.updateScale(2)

        box.spawn(pumpkin, at: CGPoint(x: 100, y: 100))

        let height = try XCTUnwrap(box.controller(for: pumpkin)?.layer.bounds.height)
        XCTAssertEqual(height, BallController.fallbackSize.height * 2, accuracy: 0.001)
    }

    func test_reparent_movesEveryToyToTheNewLayer() {
        // Display changes rebuild the sprite layer; every toy has to follow or
        // it is left drawn on an orphaned one.
        let (box, oldParent) = makeBox()
        box.spawn(pumpkin, at: CGPoint(x: 100, y: 100))
        box.spawn(wand, at: CGPoint(x: 400, y: 100))
        let newParent = CALayer()

        box.reparent(to: newParent)

        XCTAssertEqual(newParent.sublayers?.count, 2)
        XCTAssertTrue(oldParent.sublayers?.isEmpty ?? true)
    }

    // MARK: - Landing

    func test_onLanded_reportsWhichToyLanded() {
        // With one toy the caller could assume; with several it cannot.
        let (box, _) = makeBox()
        box.spawn(pumpkin, at: CGPoint(x: 100, y: 495))
        var landed: [String] = []
        box.onLanded = { toy, _ in landed.append(toy.name) }

        box.tickAll(dt: 0.1, landingY: { _ in 500 }, roamableArea: { _ in CGRect(x: 0, y: 0, width: 1000, height: 600) })

        XCTAssertEqual(landed, [pumpkin.name])
    }

    func test_tickAll_ticksEveryToyOut() {
        let (box, _) = makeBox()
        box.spawn(pumpkin, at: CGPoint(x: 100, y: 0))
        box.spawn(wand, at: CGPoint(x: 400, y: 0))

        box.tickAll(dt: 0.1, landingY: { _ in 500 }, roamableArea: { _ in CGRect(x: 0, y: 0, width: 1000, height: 600) })

        for controller in box.all {
            XCTAssertGreaterThan(controller.state?.position.y ?? 0, 0)
        }
    }

    func test_candidates_describeEveryToyOutForTheInterestPolicy() {
        let (box, _) = makeBox()
        box.spawn(pumpkin, at: CGPoint(x: 100, y: 495))
        box.tickAll(dt: 0.5, landingY: { _ in 500 }, roamableArea: { _ in CGRect(x: 0, y: 0, width: 1000, height: 600) })
        box.spawn(wand, at: CGPoint(x: 400, y: 0)) // still falling

        let candidates = box.candidates

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.first { $0.name == pumpkin.name }?.isResting, true)
        XCTAssertEqual(candidates.first { $0.name == wand.name }?.isResting, false)
    }
}
