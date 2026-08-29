//
//  HotkeyBindings.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Default bindings (PTT/text input/character summon) + user config + conflict detection
//

import CoreGraphics

/// A key combo: a virtual key code (CGKeyCode; 49 = Space) plus modifier flags.
struct HotkeyBinding: Equatable {
    let keyCode: CGKeyCode
    let modifierFlags: CGEventFlags

    /// Real CGEvents carry extra flag bits (e.g. .maskNonCoalesced) unrelated
    /// to the modifier combo the user actually pressed — only compare these.
    static let relevantModifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    func matches(keyCode: CGKeyCode, modifierFlags: CGEventFlags) -> Bool {
        self.keyCode == keyCode
            && modifierFlags.intersection(Self.relevantModifierMask)
                == self.modifierFlags.intersection(Self.relevantModifierMask)
    }
}

/// The three configurable hotkeys (F6). Conflict checking exists because
/// these are user-remappable — "충돌 검사" (conflict checking) is required in
/// the key-capture UI.
struct HotkeyBindings: Equatable {
    var pushToTalk: HotkeyBinding
    var textInput: HotkeyBinding
    var characterSummon: HotkeyBinding
    var toySummon1: HotkeyBinding
    var toySummon2: HotkeyBinding

    /// Space = keyCode 49. PTT = Option+Space (hold), text input =
    /// Option+Shift+Space, character summon = Option+Cmd+Space. Toy summons
    /// mirror ToyCatalogue.all's fixed order: keyCode 18/19 ("1"/"2") +
    /// Option+Shift summon toy[0]/toy[1].
    static let defaults = HotkeyBindings(
        pushToTalk: HotkeyBinding(keyCode: 49, modifierFlags: [.maskAlternate]),
        textInput: HotkeyBinding(keyCode: 49, modifierFlags: [.maskAlternate, .maskShift]),
        characterSummon: HotkeyBinding(keyCode: 49, modifierFlags: [.maskAlternate, .maskCommand]),
        toySummon1: HotkeyBinding(keyCode: 18, modifierFlags: [.maskAlternate, .maskShift]),
        toySummon2: HotkeyBinding(keyCode: 19, modifierFlags: [.maskAlternate, .maskShift])
    )

    /// Pairs of binding names that collide (same key + relevant modifiers).
    func conflicts() -> [(String, String)] {
        let all: [(name: String, binding: HotkeyBinding)] = [
            ("pushToTalk", pushToTalk),
            ("textInput", textInput),
            ("characterSummon", characterSummon),
            ("toySummon1", toySummon1),
            ("toySummon2", toySummon2),
        ]

        var found: [(String, String)] = []
        for i in all.indices {
            for j in all.indices where j > i {
                if all[i].binding.matches(keyCode: all[j].binding.keyCode, modifierFlags: all[j].binding.modifierFlags) {
                    found.append((all[i].name, all[j].name))
                }
            }
        }
        return found
    }
}
