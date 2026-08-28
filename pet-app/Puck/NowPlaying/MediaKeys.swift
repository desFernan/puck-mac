//
//  MediaKeys.swift
//  Puck
//
//  Play, pause and skip for something that cannot be asked directly.
//
//  A browser takes no orders over AppleScript, but it does answer the keys on
//  the top row of the keyboard, because macOS routes those to whatever last
//  played something. Posting one is the only transport a browser has.
//
//  Posting events needs Accessibility, which Puck may not have been granted.
//  That is checked rather than assumed, so the panel can leave the buttons
//  out instead of showing three that quietly do nothing.
//

import AppKit
import Foundation

enum MediaKeys {
    /// The key codes macOS uses for the media row. From IOKit's HID usage
    /// tables, which is where `NX_KEYTYPE_PLAY` and its neighbours live.
    enum Key: Int32 {
        case playPause = 16
        case next = 17
        case previous = 18
    }

    /// Whether posting one would actually reach anything.
    static var isAvailable: Bool { AXIsProcessTrusted() }

    static func send(_ key: Key) {
        guard isAvailable else { return }
        post(key, isDown: true)
        post(key, isDown: false)
    }

    private static func post(_ key: Key, isDown: Bool) {
        // A media key is not a key event: it is a system-defined event whose
        // payload packs the key and its state into one field.
        let data1 = Int((key.rawValue << 16) | ((isDown ? 0x0A : 0x0B) << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
