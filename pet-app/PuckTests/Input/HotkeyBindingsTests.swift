//
//  HotkeyBindingsTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Default bindings + conflict detection, per plan/02_pet-app.md F6
//  (PTT = Option+Space hold, text input = Option+Shift+Space,
//  character summon = Option+Cmd+Space).
//

import XCTest
import CoreGraphics
@testable import Puck

final class HotkeyBindingTests: XCTestCase {
    func test_matches_sameKeyCodeAndModifiers_isTrue() {
        let binding = HotkeyBinding(keyCode: 49, modifierFlags: [.maskAlternate])
        XCTAssertTrue(binding.matches(keyCode: 49, modifierFlags: [.maskAlternate]))
    }

    func test_matches_differentKeyCode_isFalse() {
        let binding = HotkeyBinding(keyCode: 49, modifierFlags: [.maskAlternate])
        XCTAssertFalse(binding.matches(keyCode: 50, modifierFlags: [.maskAlternate]))
    }

    func test_matches_differentModifiers_isFalse() {
        let binding = HotkeyBinding(keyCode: 49, modifierFlags: [.maskAlternate])
        XCTAssertFalse(binding.matches(keyCode: 49, modifierFlags: [.maskAlternate, .maskShift]))
    }

    func test_matches_ignoresIrrelevantFlagBits() {
        // Real CGEvents often carry extra flags (e.g. .maskNonCoalesced /
        // .maskNumericPad) unrelated to the modifier combo the user pressed.
        let binding = HotkeyBinding(keyCode: 49, modifierFlags: [.maskAlternate])
        let realEventFlags: CGEventFlags = [.maskAlternate, .maskNonCoalesced]

        XCTAssertTrue(binding.matches(keyCode: 49, modifierFlags: realEventFlags))
    }
}

final class HotkeyBindingsTests: XCTestCase {
    func test_defaults_matchThePlanSpec() {
        let defaults = HotkeyBindings.defaults

        XCTAssertTrue(defaults.pushToTalk.matches(keyCode: 49, modifierFlags: [.maskAlternate]))
        XCTAssertTrue(defaults.textInput.matches(keyCode: 49, modifierFlags: [.maskAlternate, .maskShift]))
        XCTAssertTrue(defaults.characterSummon.matches(keyCode: 49, modifierFlags: [.maskAlternate, .maskCommand]))
    }

    func test_defaults_toySummons_areOptionShiftOneAndTwo() {
        // keyCode 18 = "1", 19 = "2" -- Option+Shift+1 summons toy[0]
        // (pumpkin), Option+Shift+2 summons toy[1] (wand).
        let defaults = HotkeyBindings.defaults

        XCTAssertTrue(defaults.toySummon1.matches(keyCode: 18, modifierFlags: [.maskAlternate, .maskShift]))
        XCTAssertTrue(defaults.toySummon2.matches(keyCode: 19, modifierFlags: [.maskAlternate, .maskShift]))
    }

    func test_defaults_haveNoConflicts() {
        XCTAssertTrue(HotkeyBindings.defaults.conflicts().isEmpty)
    }

    func test_conflicts_detectsIdenticalBindings() {
        var bindings = HotkeyBindings.defaults
        bindings.textInput = bindings.pushToTalk // user misconfigures two actions to the same combo

        let conflicts = bindings.conflicts()

        XCTAssertEqual(conflicts.count, 1)
        XCTAssertTrue(conflicts[0] == ("pushToTalk", "textInput") || conflicts[0] == ("textInput", "pushToTalk"))
    }
}
