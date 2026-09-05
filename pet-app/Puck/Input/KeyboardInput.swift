//
//  KeyboardInput.swift
//  Puck
//
//  Typing, and pressing a key, as the agent asks for them.
//
//  `click_element` could already press a button, and there was no way to put
//  a character anywhere -- so "이 창에 이거 붙여넣어줘" or answering a text
//  field ended in run_shell and AppleScript, which is a much larger privilege
//  for a much smaller act.
//
//  The name-to-key table is the part worth testing and the part easy to get
//  quietly wrong, so it is pure and separate from the posting.
//

import CoreGraphics
import Foundation

enum KeyboardInput {
    /// The keys worth naming: the ones with no character to type.
    ///
    /// Virtual key codes, which are positional -- 36 is Return on every
    /// layout, where the character produced by a letter key is not. That is
    /// exactly why typing goes through `type(_:)` below (which sends
    /// characters) and this table only covers keys that have no character.
    static let namedKeys: [String: CGKeyCode] = [
        "return": 36, "enter": 36,
        "tab": 48,
        "space": 49,
        "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "forwarddelete": 117,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    /// The modifier names accepted in a chord.
    static let namedModifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand,
        "ctrl": .maskControl, "control": .maskControl,
        "opt": .maskAlternate, "option": .maskAlternate, "alt": .maskAlternate,
        "shift": .maskShift,
        "fn": .maskSecondaryFn,
    ]

    struct Chord: Equatable {
        let key: CGKeyCode
        let flags: CGEventFlags
    }

    /// Reads "cmd+shift+p", "Return", "escape".
    ///
    /// Case and spacing are ignored, because the model writes these from
    /// memory and "Cmd + Shift + P" is the same chord as "cmd+shift+p".
    /// A letter is allowed as the final key so a chord like `cmd+s` works;
    /// anything longer than one character has to be a name, or the intent is
    /// unreadable.
    static func chord(from text: String) -> Chord? {
        let parts = text.lowercased()
            .split(whereSeparator: { $0 == "+" || $0 == "-" || $0 == " " })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let last = parts.last else { return nil }

        var flags: CGEventFlags = []
        for part in parts.dropLast() {
            guard let modifier = namedModifiers[part] else { return nil }
            flags.insert(modifier)
        }
        if let named = namedKeys[last] {
            return Chord(key: named, flags: flags)
        }
        guard last.count == 1, let letter = letterKeys[last] else { return nil }
        return Chord(key: letter, flags: flags)
    }

    /// The letter and digit keys, for chords. Not for typing -- see the note
    /// on `namedKeys` about layouts.
    static let letterKeys: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "[": 33, "]": 30, "\\": 42, ";": 41, "'": 39, ",": 43, ".": 47, "/": 44, "-": 27, "=": 24,
        "`": 50,
    ]

    // MARK: - Posting

    /// Types `text` wherever the keyboard focus is.
    ///
    /// By character rather than by key code: a key code is a position on a
    /// US keyboard, and posting "a" as key 0 types something else entirely on
    /// a Dvorak or a Korean layout. `keyboardSetUnicodeString` says what to
    /// type rather than which key was hit, which is what a paste does and is
    /// the only thing that is right on every layout.
    static func type(_ text: String) {
        guard !text.isEmpty else { return }
        // In chunks, because the event's own buffer is not unbounded and a
        // whole file pasted through one event is silently truncated.
        for chunk in Self.chunks(of: text, size: 20) {
            postUnicode(chunk)
            // A pause between chunks: an app that is doing work per keystroke
            // -- an editor with a live preview, a field with validation --
            // drops what arrives while it is busy.
            usleep(8_000)
        }
    }

    /// Split so no event carries more than `size` characters. On the
    /// character, not the byte: cutting a UTF-16 surrogate pair in half
    /// produces a replacement character rather than the emoji.
    static func chunks(of text: String, size: Int) -> [String] {
        guard size > 0 else { return [text] }
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if current.count >= size {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func postUnicode(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            return
        }
        var utf16 = Array(text.utf16)
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Presses one key, with modifiers.
    static func press(_ chord: Chord) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: chord.key, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: chord.key, keyDown: false)
        else {
            return
        }
        down.flags = chord.flags
        // On the release too: an app that reads the flags on key-up -- which
        // is where a menu shortcut is often matched -- sees a chord that was
        // let go of before it was pressed otherwise.
        up.flags = chord.flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Scrolls at the pointer's current position.
    ///
    /// Lines rather than pixels: a line is what a wheel notch sends, so an
    /// app that scrolls by lines moves by a sensible amount and one that
    /// scrolls by pixels still gets a proportional number.
    static func scroll(lines: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: CGEventSource(stateID: .combinedSessionState),
            units: .line,
            wheelCount: 1,
            wheel1: lines,
            wheel2: 0,
            wheel3: 0
        ) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }
}
