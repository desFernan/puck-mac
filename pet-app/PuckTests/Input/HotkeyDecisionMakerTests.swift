//
//  HotkeyDecisionMakerTests.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Pure decision logic for GlobalHotkeyManager, including the case plan/
//  02_pet-app.md explicitly calls for by listing flagsChanged alongside
//  keyDown/keyUp: releasing the modifier (Option) before the key (Space)
//  during PTT hold must still end the hold.
//

import XCTest
import CoreGraphics
@testable import Puck

final class HotkeyDecisionMakerTests: XCTestCase {
    private let bindings = HotkeyBindings.defaults

    func test_keyDown_matchingPushToTalk_returnsPushToTalkDown() {
        let action = HotkeyDecisionMaker.decide(
            eventType: .keyDown, keyCode: 49, flags: [.maskAlternate],
            bindings: bindings, isPushToTalkActive: false
        )
        XCTAssertEqual(action, .pushToTalkDown)
    }

    func test_keyDown_matchingTextInput_returnsTextInputRequested() {
        let action = HotkeyDecisionMaker.decide(
            eventType: .keyDown, keyCode: 49, flags: [.maskAlternate, .maskShift],
            bindings: bindings, isPushToTalkActive: false
        )
        XCTAssertEqual(action, .textInputRequested)
    }

    func test_keyDown_matchingCharacterSummon_returnsCharacterSummonRequested() {
        let action = HotkeyDecisionMaker.decide(
            eventType: .keyDown, keyCode: 49, flags: [.maskAlternate, .maskCommand],
            bindings: bindings, isPushToTalkActive: false
        )
        XCTAssertEqual(action, .characterSummonRequested)
    }

    func test_keyDown_matchingPushToTalk_whileAlreadyActive_returnsNone() {
        // OS key-repeat re-sends keyDown for a physically held key. Without
        // this guard, each repeat re-fires pushToTalkDown and slides the
        // hold's start time forward, making genuine long holds measure as
        // under the minimum duration at release.
        let action = HotkeyDecisionMaker.decide(
            eventType: .keyDown, keyCode: 49, flags: [.maskAlternate],
            bindings: bindings, isPushToTalkActive: true
        )
        XCTAssertEqual(action, .none)
    }

    func test_keyDown_matchingToySummon1_returnsToySummon1Requested() {
        let action = HotkeyDecisionMaker.decide(
            eventType: .keyDown, keyCode: 18, flags: [.maskAlternate, .maskShift],
            bindings: bindings, isPushToTalkActive: false
        )
        XCTAssertEqual(action, .toySummon1Requested)
    }

    func test_keyDown_matchingToySummon2_returnsToySummon2Requested() {
        let action = HotkeyDecisionMaker.decide(
            eventType: .keyDown, keyCode: 19, flags: [.maskAlternate, .maskShift],
            bindings: bindings, isPushToTalkActive: false
        )
        XCTAssertEqual(action, .toySummon2Requested)
    }

    func test_keyDown_unrelatedKey_returnsNone() {
        let action = HotkeyDecisionMaker.decide(
            eventType: .keyDown, keyCode: 0, flags: [],
            bindings: bindings, isPushToTalkActive: false
        )
        XCTAssertEqual(action, .none)
    }

    func test_keyUp_ofPushToTalkKey_whileActive_returnsPushToTalkUp() {
        let action = HotkeyDecisionMaker.decide(
            eventType: .keyUp, keyCode: 49, flags: [.maskAlternate],
            bindings: bindings, isPushToTalkActive: true
        )
        XCTAssertEqual(action, .pushToTalkUp)
    }

    func test_keyUp_ofPushToTalkKey_whileNotActive_returnsNone() {
        // Guards against a stray/duplicate keyUp firing a second "up" callback.
        let action = HotkeyDecisionMaker.decide(
            eventType: .keyUp, keyCode: 49, flags: [],
            bindings: bindings, isPushToTalkActive: false
        )
        XCTAssertEqual(action, .none)
    }

    func test_flagsChanged_releasingModifierBeforeKey_endsHold() {
        // User released Option while still holding Space -> no keyUp for Space
        // yet, but PTT must still end (this is exactly why the plan lists
        // flagsChanged alongside keyDown/keyUp).
        let action = HotkeyDecisionMaker.decide(
            eventType: .flagsChanged, keyCode: 49, flags: [],
            bindings: bindings, isPushToTalkActive: true
        )
        XCTAssertEqual(action, .pushToTalkUp)
    }

    func test_flagsChanged_modifierStillHeld_whileActive_returnsNone() {
        let action = HotkeyDecisionMaker.decide(
            eventType: .flagsChanged, keyCode: 49, flags: [.maskAlternate],
            bindings: bindings, isPushToTalkActive: true
        )
        XCTAssertEqual(action, .none)
    }

    func test_flagsChanged_whileNotActive_returnsNone() {
        let action = HotkeyDecisionMaker.decide(
            eventType: .flagsChanged, keyCode: 49, flags: [.maskCommand],
            bindings: bindings, isPushToTalkActive: false
        )
        XCTAssertEqual(action, .none)
    }
}
