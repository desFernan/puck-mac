//
//  KeyboardInputTests.swift
//  PuckTests
//
//  Reading the key names the model writes, and cutting text into events.
//
//  The posting itself is not tested -- it puts real events into whatever app
//  is frontmost, which in a test run is the test runner.
//

import CoreGraphics
import XCTest
@testable import Puck

final class KeyboardInputTests: XCTestCase {
    func test_aBareKeyName() {
        XCTAssertEqual(KeyboardInput.chord(from: "Return")?.key, 36)
        XCTAssertEqual(KeyboardInput.chord(from: "escape")?.key, 53)
        XCTAssertEqual(KeyboardInput.chord(from: "tab")?.key, 48)
        XCTAssertEqual(KeyboardInput.chord(from: "Return")?.flags, [])
    }

    /// The model writes these from memory, so "Cmd + Shift + P" and
    /// "cmd+shift+p" have to be the same chord.
    func test_caseAndSpacingDoNotMatter() {
        let spaced = KeyboardInput.chord(from: "Cmd + Shift + P")
        let tight = KeyboardInput.chord(from: "cmd+shift+p")

        XCTAssertEqual(spaced, tight)
        XCTAssertEqual(tight?.flags, [.maskCommand, .maskShift])
        XCTAssertEqual(tight?.key, 35)
    }

    func test_everyModifierName() {
        XCTAssertEqual(KeyboardInput.chord(from: "command+a")?.flags, [.maskCommand])
        XCTAssertEqual(KeyboardInput.chord(from: "control+a")?.flags, [.maskControl])
        XCTAssertEqual(KeyboardInput.chord(from: "ctrl+a")?.flags, [.maskControl])
        XCTAssertEqual(KeyboardInput.chord(from: "option+a")?.flags, [.maskAlternate])
        XCTAssertEqual(KeyboardInput.chord(from: "alt+a")?.flags, [.maskAlternate])
        XCTAssertEqual(KeyboardInput.chord(from: "opt+a")?.flags, [.maskAlternate])
    }

    /// A modifier plus a named key, which is how most real shortcuts are
    /// written: cmd+Return, shift+tab.
    func test_aModifierWithANamedKey() {
        XCTAssertEqual(KeyboardInput.chord(from: "cmd+return")?.key, 36)
        XCTAssertEqual(KeyboardInput.chord(from: "cmd+return")?.flags, [.maskCommand])
        XCTAssertEqual(KeyboardInput.chord(from: "shift+tab")?.key, 48)
    }

    /// Something nobody can read is refused rather than pressed as whatever
    /// it happened to parse to. A press that did the wrong thing is worse
    /// than one that did not happen.
    func test_somethingUnreadableIsRefused() {
        XCTAssertNil(KeyboardInput.chord(from: ""))
        XCTAssertNil(KeyboardInput.chord(from: "meta+a"), "there is no meta modifier here")
        XCTAssertNil(KeyboardInput.chord(from: "cmd+banana"), "a word is not a key")
        XCTAssertNil(KeyboardInput.chord(from: "€"), "not on the table")
    }

    /// Typing goes by character rather than by key code, so this table is
    /// only ever used for the final key of a chord -- but that key still has
    /// to be the right one.
    func test_theLetterTableIsThePositionalOne() {
        XCTAssertEqual(KeyboardInput.letterKeys["a"], 0)
        XCTAssertEqual(KeyboardInput.letterKeys["s"], 1)
        XCTAssertEqual(KeyboardInput.letterKeys["z"], 6)
        XCTAssertEqual(KeyboardInput.letterKeys.count, Set(KeyboardInput.letterKeys.values).count,
                       "two names cannot share a key code")
    }

    // MARK: - Cutting text into events

    func test_textIsCutIntoChunks() {
        XCTAssertEqual(KeyboardInput.chunks(of: "abcdef", size: 2), ["ab", "cd", "ef"])
        XCTAssertEqual(KeyboardInput.chunks(of: "abcde", size: 2), ["ab", "cd", "e"])
        XCTAssertEqual(KeyboardInput.chunks(of: "", size: 2), [])
    }

    /// On the character, not the byte: cutting a surrogate pair in half
    /// produces a replacement character rather than the emoji.
    func test_aCutNeverLandsInsideACharacter() {
        let text = "🐈‍⬛가나다🎉"

        let rejoined = KeyboardInput.chunks(of: text, size: 2).joined()

        XCTAssertEqual(rejoined, text)
    }

    func test_aSizeOfZeroIsNotADivideByZero() {
        XCTAssertEqual(KeyboardInput.chunks(of: "abc", size: 0), ["abc"])
    }
}

final class ScrollHandlerArgumentTests: XCTestCase {
    /// "down" means the content moves up, which is the opposite sign to the
    /// wheel's own.
    func test_directionIsTheOppositeOfTheWheels() {
        XCTAssertEqual(ScrollHandler.direction(from: .object(["direction": .string("down")])), -1)
        XCTAssertEqual(ScrollHandler.direction(from: .object(["direction": .string("UP")])), 1)
    }

    /// Anything else is refused rather than guessed at.
    func test_anUnknownDirectionIsNoDirection() {
        XCTAssertEqual(ScrollHandler.direction(from: .object(["direction": .string("sideways")])), 0)
        XCTAssertEqual(ScrollHandler.direction(from: .object([:])), 0)
    }

    /// A model that asks for ten thousand lines means "to the bottom", and
    /// the wheel is not how you get there.
    func test_theDistanceIsBounded() {
        XCTAssertEqual(ScrollHandler.lines(from: .object(["lines": .number(10_000)])), 50)
        XCTAssertEqual(ScrollHandler.lines(from: .object(["lines": .number(0)])), 1)
        XCTAssertEqual(ScrollHandler.lines(from: .object(["lines": .number(-5)])), 1)
        XCTAssertEqual(ScrollHandler.lines(from: .object([:])), ScrollHandler.defaultLines)
    }
}
