//
//  KeyboardHandlers.swift
//  Puck
//
//  Typing, pressing a key, and scrolling -- the three things the pet could
//  not do to another app.
//
//  Together in one file because they are one capability with one shape: each
//  reads a couple of arguments, checks the same permission, posts one kind of
//  event, and answers. Three files of fifteen lines would say less.
//
//  The rules they depend on -- what "cmd+shift+p" means, how to type text on
//  a layout that is not US -- are in KeyboardInput, which is pure and tested.
//

import CoreGraphics
import Foundation

/// Types text wherever the keyboard focus already is.
///
/// Deliberately not "type into this element": moving the focus is a click,
/// which is its own tool with its own approval. Doing both here would be one
/// prompt for two acts.
final class TypeTextHandler: ToolHandler {
    let toolName = "type_text"

    /// Injectable for the reason ClickElementHandler's is: so the permission
    /// branch is testable without the real TCC state of whoever runs the suite.
    var isAccessibilityTrusted: () -> Bool = { AccessibilityPermission.isTrusted(prompt: false) }

    func execute(id _: String, args: JSONValue, completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard case .object(let fields) = args, case .string(let text)? = fields["text"], !text.isEmpty else {
            completion(.failure(.executionFailed("type_text requires a non-empty text")))
            return
        }
        guard isAccessibilityTrusted() else {
            completion(.failure(.permissionDenied))
            return
        }
        // Off the caller's thread: typing is paced (see KeyboardInput.type),
        // so a long string would otherwise hold up whatever is on this one.
        DispatchQueue.global().async {
            KeyboardInput.type(text)
            completion(.success(nil))
        }
    }
}

/// Presses one key, with modifiers: Return, Escape, cmd+S.
final class PressKeyHandler: ToolHandler {
    let toolName = "press_key"

    var isAccessibilityTrusted: () -> Bool = { AccessibilityPermission.isTrusted(prompt: false) }

    func execute(id _: String, args: JSONValue, completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard case .object(let fields) = args, case .string(let key)? = fields["key"] else {
            completion(.failure(.executionFailed("press_key requires a key")))
            return
        }
        guard let chord = KeyboardInput.chord(from: key) else {
            // Named rather than ignored: a key nobody can parse is a call the
            // model should correct, and silence would read as a press that
            // did nothing.
            completion(.failure(.executionFailed("press_key does not know the key \"\(key)\"")))
            return
        }
        guard isAccessibilityTrusted() else {
            completion(.failure(.permissionDenied))
            return
        }
        KeyboardInput.press(chord)
        completion(.success(nil))
    }
}

/// Scrolls at a point, or at the centre of a frame.
///
/// No approval, unlike the two above: scrolling changes what is on screen and
/// nothing else, and asking about it would be a prompt per look.
final class ScrollHandler: ToolHandler {
    let toolName = "scroll"

    var isAccessibilityTrusted: () -> Bool = { AccessibilityPermission.isTrusted(prompt: false) }

    /// How far one call scrolls when nothing says. Three lines is a small
    /// nudge -- the model can call again, and a default that jumped a page
    /// would make "scroll down a bit" unusable.
    static let defaultLines: Int32 = 3

    func execute(id _: String, args: JSONValue, completion: @escaping @Sendable (Result<JSONValue?, ToolExecutionError>) -> Void) {
        guard isAccessibilityTrusted() else {
            completion(.failure(.permissionDenied))
            return
        }
        let magnitude = Self.lines(from: args)
        let direction = Self.direction(from: args)
        guard direction != 0 else {
            completion(.failure(.executionFailed("scroll requires direction \"up\" or \"down\"")))
            return
        }
        // Where the pointer is, unless a frame says otherwise. The wheel goes
        // to whatever is under the cursor, so a scroll aimed at a pane has to
        // move the cursor there first.
        if let frame = args.extractFrame() {
            CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: frame.midY))
        }
        KeyboardInput.scroll(lines: magnitude * direction)
        completion(.success(nil))
    }

    /// Up is positive to the wheel, which is the opposite of how the argument
    /// reads -- "down" means the content moves up.
    static func direction(from args: JSONValue) -> Int32 {
        guard case .object(let fields) = args, case .string(let value)? = fields["direction"] else { return 0 }
        switch value.lowercased() {
        case "down": return -1
        case "up": return 1
        default: return 0
        }
    }

    static func lines(from args: JSONValue) -> Int32 {
        guard case .object(let fields) = args, case .number(let value)? = fields["lines"] else {
            return defaultLines
        }
        // Bounded: a model that asks for ten thousand lines means "to the
        // bottom", and the wheel is not how you get there.
        return Int32(max(1, min(value, 50)))
    }
}
