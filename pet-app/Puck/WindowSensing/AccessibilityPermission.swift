//
//  AccessibilityPermission.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  AXIsProcessTrustedWithOptions check + Settings deep link
//
//  Thin wrapper around real OS permission APIs — not unit tested, since
//  calling it for real would either trigger a system prompt or open System
//  Settings on the developer's machine.

import AppKit
import ApplicationServices

enum AccessibilityPermission {
    /// Checks whether Accessibility access is granted. When `prompt` is true,
    /// macOS shows its own "add Puck to Accessibility" system prompt if not.
    static func isTrusted(prompt: Bool = false) -> Bool {
        let options = [Self.promptOptionKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// `kAXTrustedCheckOptionPrompt` is a `var` in the SDK's headers -- a
    /// global anything can write, as far as the compiler knows -- so reading
    /// it directly is a data race by the letter of the rule. It is a constant
    /// in every way that matters; copied once here so the rest of the app
    /// reads a real one.
    private static let promptOptionKey: String = {
        // Read once, behind a `let`, and read through `nonisolated(unsafe)`
        // because the SDK declares the constant as a global `var`: to the
        // compiler that is shared mutable state, and to everyone else it is
        // the string "AXTrustedCheckOptionPrompt". Copying it here is the
        // narrowest way to say "this one read is fine" without hard-coding a
        // system constant we do not own.
        nonisolated(unsafe) let key = kAXTrustedCheckOptionPrompt
        return key.takeUnretainedValue() as String
    }()

    /// Deep link to System Settings > Privacy & Security > Accessibility, for
    /// re-prompting a user who dismissed the initial system prompt.
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
